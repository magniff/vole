# 14. Threads

Your computer has several cores, and so far every program in this
book has used one of them. A *thread* is a sequence of steps that runs
at the same time as the program's other threads, each on a core of its
own when there are enough. In this chapter you'll start threads, give
them data to work on, collect their results, and share state between
them through a lock, an atomic counter and a channel.

Our running example is the simplest useful parallel job: adding up a
big list of numbers, by splitting it into pieces and giving each piece
to a thread.

## Why threads are hard, and what vole checks

Two threads that read the same memory are fine. Two threads where one
writes memory while the other reads or writes it, with nothing to
order them, are a *data race*: the result depends on timing, changes
from run to run, and can be garbage. Races are some of the hardest bugs
to find, because they rarely happen while you're looking.

Vole checks for them when you compile, at the place a thread starts,
by looking at what the new thread gets:

- an owned value, such as a `Vec`, may *move* into a thread, which then
  has it to itself;
- a reference, such as a slice, may go only to a *scoped* thread, one
  that is guaranteed to finish before the data it borrows goes away;
- scoped threads may read the caller's data together, but they may not
  all change it, unless the change goes through a lock or an atomic;
- a raw pointer never goes to another thread, and a `static`, which
  every thread can reach, must be of a type that threads can share.

Safe code that follows these rules can't have a data race. The rest of
the chapter shows each rule, and the error you get when you break it.

## spawn and join

`thread::spawn_in` starts a thread that runs a closure. It takes an
allocator too, for the memory the closure and its result live in until
the thread is joined. Save this as `spawn.vl`:

```vole spawn.vl
use std::thread;

fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    for i in 1..=100 {
        v.push(i);
    }
    let h = thread::spawn_in(
        move || {
            let mut total = 0;
            for x in v {
                total += x;
            }
            total
        },
        gpa,
    );
    println("started a thread");
    let total = h.join().unwrap();
    println("the thread says: {total}");
}
```

```out
started a thread
the thread says: 5050
```

`spawn_in` returns a *handle*, `h`, right away; the new thread runs on
its own while `main` carries on and prints its first line. `h.join()`
waits for the thread to finish and gives back the closure's result, in
a `Result` that we `unwrap` (more on that in a moment).

The closure is a `move` closure: it takes what it uses. A spawned
thread may run longer than the function that started it, so it can't
borrow that function's variables, which might be gone by then. `v`
moves into the thread, and after the `spawn_in`, `main` can't use `v`
any more; the compiler says so if you try.

References can't go to a spawned thread at all, even in a `move`
closure, because the data they borrow stays behind:

```vole
use std::thread;

fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    for i in 0..10 {
        v.push(i);
    }
    let xs = v.as_slice();
    let h = thread::spawn_in(move || xs.len(), gpa);
    println("{}", h.join().unwrap());
}
```

```err
error[borrowck.dropped_borrowed]: 'v' is dropped while it is still borrowed (dropped at main.vl: line 3, column 19) (borrowed at main.vl: line 8, column 14)
 --> main.vl: line 8, column 14
  = help: declare it before what borrows it, so it is dropped after
```

`xs` borrows `v`, and `v` is dropped at the end of `main`, while the
thread may still be running: the borrow checker's error from chapter 4.
There are two ways out: give the thread its own copy
(`xs.to_vec_in(gpa)`), or use a scoped thread, which is the next
section.

If any thread panics, the whole program stops, with the usual message
and exit status 101. So the `Result` that `join` returns is always an
`Ok`, and `unwrap` on it can't fail: if the thread failed, `join` is
never reached.

```vole
use std::thread;

fn main(gpa: Gpa) {
    let h = thread::spawn_in(
        || {
            let v = [1, 2, 3];
            let i = 3;
            v[i]
        },
        gpa,
    );
    println("{}", h.join().unwrap());
    println("not reached");
}
```

```out exit=101
main.vl:8:13: index out of bounds: index 3, length 3
```

> **If you know Rust:** `spawn_in` is `spawn` with the allocator. `Send`
> and `Sync` are worked out from the types, as Rust's auto traits are,
> and checked where a thread starts. `join` returns a `Result` as in
> Rust, but a panic stops every thread, so it is never an `Err`.

## Scoped threads

Moving data into a thread works, but usually you want several threads
to read the same big piece of data. `thread::scope` makes that safe.
Save this as `sum.vl`:

```vole sum.vl
use std::thread;
use std::thread::ScopedJoinHandle;

fn sum(xs: &[i64]) -> i64 {
    let mut total = 0;
    for x in xs {
        total += *x;
    }
    total
}

fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    for i in 0..1000000 {
        v.push(i % 1000);
    }
    let xs = v.as_slice();

    let half = xs.len() / 2;
    let total = thread::scope(|s| {
        let a = s.spawn(|| sum(&xs[..half]));
        let b = s.spawn(|| sum(&xs[half..]));
        a.join().unwrap() + b.join().unwrap()
    });
    println("two threads: {total}");

    let n = thread::available_parallelism();
    let chunk = (xs.len() + n - 1) / n;
    let total = thread::scope(|s| {
        let mut handles: Vec<ScopedJoinHandle<i64>, Gpa> = Vec::new_in(gpa);
        for k in 0..n {
            let lo = k * chunk;
            let hi = if lo + chunk < xs.len() { lo + chunk } else { xs.len() };
            handles.push(s.spawn(move || sum(&xs[lo..hi])));
        }
        let mut t = 0;
        for h in handles {
            t += h.join().unwrap();
        }
        t
    });
    println("one thread per core: {total}");
}
```

```out
two threads: 499500000
one thread per core: 499500000
```

`thread::scope` calls its closure with a *scope*, `s`, and threads
started with `s.spawn` belong to it. Before `scope` returns, it waits
for every one of them. So the threads can't outlive anything that
existed before the scope started, and they may borrow it: both threads
read `xs`, a slice of `v`, with no copying.

The first part splits the numbers in two. The second asks
`thread::available_parallelism()` how many threads the machine can run
at once, and gives each a chunk. Its threads are `move` closures: `lo`
and `hi` are made inside the loop and are gone at the end of each trip,
so each thread takes its own copy of them. (`xs`, a reference, is
copied too, which copies nothing but its position and length.)

While the threads run, the scope's own closure must not change what
they read. That's the other half of the bargain, and the borrow checker
checks it.

## Sharing changes: Mutex

Here is a tempting mistake. Let's count the primes among the numbers
with two threads, each adding to the same counter:

```vole shared.vl
use std::thread;

fn is_prime(n: i64) -> bool {
    if n < 2 {
        return false;
    }
    let mut d = 2;
    while d * d <= n {
        if n % d == 0 {
            return false;
        }
        d += 1;
    }
    true
}

fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    for i in 0..100000 {
        v.push(i);
    }
    let xs = v.as_slice();
    let half = xs.len() / 2;
    let mut primes = 0;
    thread::scope(|s| {
        s.spawn(|| {
            for &x in &xs[..half] {
                if is_prime(x) {
                    primes += 1;
                }
            }
        });
        s.spawn(|| {
            for &x in &xs[half..] {
                if is_prime(x) {
                    primes += 1;
                }
            }
        });
    });
    println("primes: {primes}");
}
```

```err
error[borrowck.mut_twice]: cannot borrow 'primes' as mutable more than once at a time (mutably borrowed at shared.vl: line 26, column 17)
 --> shared.vl: line 33, column 17
  = help: finish the first borrow's uses before the second, or reborrow once and pass it on
```

`primes += 1` reads the counter, adds one, and writes it back. If both
threads do that at the same moment, they both read the same number and
one of the additions is lost. In a language that allows it, this
program prints a different wrong count on each run. Vole doesn't
compile it, and the rule that stops it is one you know: each closure
that changes `primes` borrows it mutably, and there can be only one
mutable borrow of a value at a time (chapter 4).

There are three fixes. The best is usually the one `sum.vl` already
uses: each thread counts its own half, returns its
count, and `join` brings the counts together. Nothing is shared, so
nothing can race.

When threads really do need to change one value, put it in a
*mutex*, a lock that lets one thread at a time at the data inside. Or
use an *atomic*, a number whose operations can't be interrupted
halfway. Here are both, in `count.vl`:

```vole count.vl
use std::sync::Mutex;
use std::sync::atomic::{AtomicI64, Ordering};
use std::thread;

fn is_prime(n: i64) -> bool {
    if n < 2 {
        return false;
    }
    let mut d = 2;
    while d * d <= n {
        if n % d == 0 {
            return false;
        }
        d += 1;
    }
    true
}

fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    for i in 0..100000 {
        v.push(i);
    }
    let xs = v.as_slice();
    let half = xs.len() / 2;

    let primes = Mutex::new(0);
    thread::scope(|s| {
        s.spawn(|| {
            for &x in &xs[..half] {
                if is_prime(x) {
                    *primes.lock().unwrap() += 1;
                }
            }
        });
        s.spawn(|| {
            for &x in &xs[half..] {
                if is_prime(x) {
                    *primes.lock().unwrap() += 1;
                }
            }
        });
    });
    println("primes (mutex): {}", primes.lock().unwrap());

    let count = AtomicI64::new(0);
    thread::scope(|s| {
        s.spawn(|| {
            for &x in &xs[..half] {
                if is_prime(x) {
                    count.fetch_add(1, Ordering::Relaxed);
                }
            }
        });
        s.spawn(|| {
            for &x in &xs[half..] {
                if is_prime(x) {
                    count.fetch_add(1, Ordering::Relaxed);
                }
            }
        });
    });
    println("primes (atomic): {}", count.load(Ordering::Relaxed));
}
```

```out
primes (mutex): 9592
primes (atomic): 9592
```

A `Mutex` owns its data: the `0` inside `primes` can only be reached
through it. `primes.lock()` waits until no other thread holds the lock,
and returns a *guard*. The data is `*guard`, and when the guard is
dropped, here at the end of the statement, the mutex is unlocked. So
the read, the add and the write of `*primes.lock().unwrap() += 1`
happen while no other thread can get in. `lock` returns a `Result`,
which is always `Ok` here, so we `unwrap` it. `try_lock` is the same,
but gives up at once, with an `Err`, if another thread holds the lock.

Both threads use `primes` without a `move`: a scoped thread may borrow a
mutex, and the two shared borrows are fine, because the mutex does the
ordering itself.

A thread started with `spawn_in` can't borrow the mutex. To share one
with it, put the mutex in an `Arc`, a pointer to a value that counts
its owners: `Arc::new_in(Mutex::new(0), gpa)` makes one, `clone()`
makes another pointer to the same mutex for the thread to take, and
the value is dropped when its last `Arc` is.

The scoped threads here return nothing, so we don't keep their handles.
The scope waits for them anyway.

> **If you know Rust:** `Mutex` and its guard, `RwLock`, `Condvar`,
> `Once` and `Arc` (`Arc::new_in`) are Rust's, in `std::sync`. There's
> no poisoning: a panic stops the program rather than leaving a
> poisoned lock behind, so `lock()` never returns an `Err`.

## Atomics

The second half of `count.vl` uses an `AtomicI64` instead. `fetch_add`
adds to it as one indivisible step and returns the old value; `load`
reads it. `std::sync::atomic` has atomics for every integer type and
for `bool`, with the operations Rust and C++ have: `store`, `swap`,
`compare_exchange`, `fetch_sub`, `fetch_max` and so on.

Each operation takes an *ordering*, which says what else the operation
promises about memory around it:

- `Ordering::Relaxed` promises nothing beyond the atomic itself. That's
  right for a counter like this one, which nothing else depends on.
- `Ordering::Release` on a store and `Ordering::Acquire` on a load are
  for handing data over: everything one thread wrote before its release
  store is visible to a thread whose acquire load sees that store.
- `Ordering::SeqCst` is the strongest, one order of operations all
  threads agree on. When you're not sure, use it.

An atomic counter is cheaper than a mutex, but it only works for one
number. For anything bigger, or for several values that must change
together, use a mutex.

## Channels

Sometimes threads don't share data so much as pass it along: one
produces work, another consumes it. A *channel* is a queue for that. It
has a `Sender` end and a `Receiver` end, and values sent into one come
out of the other, in order.

Here's a small worker pool. Three threads hash the lines of the input,
each taking every third line, and send their results to the main
thread, which collects them. Save it as `hash.vl`:

```vole hash.vl
use std::io;
use std::sync::mpsc;
use std::thread;

// FNV-1a, a simple hash of a line's bytes.
fn hash(line: &str) -> u64 {
    let mut h: u64 = 0xcbf29ce484222325;
    for b in line.bytes() {
        h = (h ^ b as u64).wrapping_mul(0x100000001b3);
    }
    h
}

fn main(gpa: Gpa) {
    let text = io::read_to_string_in(io::stdin(), gpa).unwrap();
    let all: Vec<&str, Gpa> = text.lines().collect_in(gpa);
    let lines = all.as_slice();
    let workers: usize = 3;

    let mut results = thread::scope(|s| {
        let (tx, rx) = mpsc::channel_in(gpa);
        for w in 0..workers {
            let tx = tx.clone();
            s.spawn(move || {
                let mut i = w;
                while i < lines.len() {
                    tx.send((i, hash(lines[i]))).unwrap();
                    i += workers;
                }
            });
        }
        drop(tx);
        let mut got: Vec<(usize, u64), Gpa> = Vec::new_in(gpa);
        for r in rx.iter() {
            got.push(r);
        }
        got
    });
    results.sort();
    for (i, h) in results {
        println("{:<8} {h:016x}", lines[i]);
    }
}
```

```in
apple
banana
cherry
date
elder
fig
grape
```

```out
apple    f74a62a458befdbf
banana   b4d3b6b1c372c890
cherry   52d2f6df6bced8f8
date     855b516730a34339
elder    828dd4aceeb21517
fig      dc9e8d18fec95535
grape    32ec8b2977fe3c70
```

`mpsc::channel_in(gpa)` makes a channel; it allocates its queue, so it
takes an allocator. ("mpsc" stands for "multiple producers, single
consumer": many senders, one receiver.) Each worker gets its own clone
of the sender, `tx.clone()`, and takes it with `move`.

`for r in rx.iter()` receives until the channel is empty and every
sender is gone. A sender is gone when it's dropped, which for the
workers' clones happens when their threads finish. The original `tx`
would keep the channel open forever, so we drop it ourselves with
`drop(tx)` once the workers have their clones.

The results arrive in whatever order the threads happen to finish, so
each carries its line number, and we sort them before printing. That
keeps the output the same on every run, which is a good habit for any
threaded program: decide the order yourself instead of letting the
timing decide it.

`send` returns a `Result` because it fails, giving the value back, when
the receiver is gone. `recv()` waits for one value, and fails when every
sender is gone and nothing is left.

> **If you know Go:** threads here are operating-system threads, not
> goroutines, so start tens of them, not millions. Channels are much
> like Go's, typed and in order. There's no `close`: a channel closes
> when the last sender is dropped.

## Globals and thread-locals

A `static` is a single value shared by the whole program, and every
thread can reach it. So its type must be one that threads can share:
an atomic or a mutex, which order their own changes, or data that never
changes.

```vole
use std::sync::Mutex;
use std::sync::atomic::{AtomicI64, Ordering};
use std::thread;

static COUNT: AtomicI64 = AtomicI64::new(0);
static LOG: Mutex<i64> = Mutex::new(0);

fn bump() {
    COUNT.fetch_add(1, Ordering::Relaxed);
    *LOG.lock().unwrap() += 10;
}

fn main(gpa: Gpa) {
    let h = thread::spawn_in(|| bump(), gpa);
    bump();
    h.join().unwrap();
    println("{} {}", COUNT.load(Ordering::Relaxed), LOG.lock().unwrap());
}
```

```out
2 20
```

Both threads call `bump`, and nothing is lost: the atomic and the mutex
see to it. A `static` of a type that isn't safe to share is an error
(`sync.static`).

A `static mut` is a plain variable that the whole program can change.
The compiler can't tell which threads use it, so reading or writing one
takes `unsafe` (chapter 15), and keeping threads apart is then up to
you. One kind is safe to use from any thread, though, a
*thread-local*: each thread gets its own copy, which starts from the
initial value the first time that thread uses it. It is still a `static
mut`, so the `unsafe` stays:

```vole
use std::thread;

#[thread_local]
static mut CALLS: i64 = 0;

fn work() -> i64 {
    for _ in 0..3 {
        unsafe {
            CALLS += 1;
        }
    }
    unsafe { CALLS }
}

fn main(gpa: Gpa) {
    let h = thread::spawn_in(|| work(), gpa);
    unsafe {
        CALLS = 100;
    }
    println("the thread counted {}, main has {}", h.join().unwrap(), unsafe { CALLS });
}
```

```out
the thread counted 3, main has 100
```

The thread's `CALLS` and `main`'s are different variables, so there is
nothing to race on.

## Threads and effects

Threads add three effects to the six from chapter 12: `thread` for
starting one, `sync` for an atomic, a lock, a join or a channel, and
`tls` for a thread-local. Ask about the thread-local program:

```console
$ volec query effects crate main.vl
crate::work	tls
crate::main	alloc(Gpa, extern) io static tls thread sync panic diverge
```

`work` uses a thread-local, which is `tls`, not `static`. `main` starts
a thread and joins it. It's also `alloc(Gpa, extern)`: `spawn_in` keeps
the thread's result in memory from the `Gpa` it was given, and the C
library allocates the thread itself with its own allocator, which the
compiler reports like any other allocation. And it's `diverge`: `join`
waits for as long as the thread runs. A `#[pure]` function
can do none of these things, so a pure function is also one you can
call from any thread.

## Raw pointers stay home

The last rule: a raw pointer (chapter 15) can't go to another thread,
because the compiler can't tell what it points to or who else is using
it:

```vole
use std::thread;

fn main(gpa: Gpa) {
    let x = 5;
    let p: *const i64 = &raw const x;
    let h = thread::spawn_in(move || unsafe { *p }, gpa);
    println("{}", h.join().unwrap());
}
```

```err
error[sync.not_send]: the closure cannot be sent between threads (it is not Send): it captures 'p', '*const i64', which is not Send; '*const i64' is a raw pointer, neither Send nor Sync
 --> main.vl: line 6, column 13
  = help: required by the bound 'F: Send' of 'std::thread::spawn_in'
```

## Summary

- `thread::spawn_in(move || ..., gpa)` starts a thread that owns what
  it uses; `join` waits for it and gives its result. A panic in any
  thread stops the program.
- `thread::scope(|s| ...)` starts threads with `s.spawn` that may
  borrow the caller's data, because the scope waits for them all before
  it returns.
- Threads read shared data freely, but change it only through a `Mutex`
  (`lock`) or an atomic; better still, each thread returns its own
  result. An `Arc` shares a value with threads that can't borrow it.
- Channels (`mpsc::channel_in`) pass values from threads to a receiver,
  and close when every sender is dropped.
- The compiler checks all of this when a thread starts, with the borrow
  checker and the `sync.*` errors: no borrows escaping into spawned
  threads, no shared writes, no raw pointers on another thread, and no
  `static` that threads can't share.

The next chapter goes where these checks can't follow: unsafe code,
raw pointers, and calling C.

## Try it yourself

- In `sum.vl`, make each thread return both the sum and the largest
  number in its chunk, as a tuple, and combine them after `join`.
- Change `hash.vl` to use one channel per worker instead of a shared
  one. Is it simpler or not?
- Make the word counter from chapter 11 count each file on its own
  thread, then merge the counts. (Each thread needs its own `HashMap`;
  merge them after `join`.)
