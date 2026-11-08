# Threads

Threads and atomics, Rust's. Safe code cannot make a data race: what
crosses threads is checked where a thread starts, from the types
(`Send` and `Sync`, inferred, as in Rust) and the borrow checker. The
errors are `sync.*` (`volec explain sync.not_send`) and `borrowck.*`.

## Atomics

`std::sync::atomic` has `Atomic<T>` for integers, `bool` and raw
pointers, with Rust's names as aliases (`AtomicI64`, `AtomicU32`,
`AtomicUsize`, `AtomicBool`, `AtomicPtr<T>`...) and Rust's methods:
`new`, `load`, `store`, `swap`, `compare_exchange` (`Ok(old)` or
`Err(found)`), `compare_exchange_weak`, `fetch_add`, `fetch_sub`,
`fetch_and`, `fetch_or`, `fetch_xor`, `fetch_nand`, `fetch_max`,
`fetch_min`, `get_mut`, `into_inner`, and `fence(order)`,
`compiler_fence(order)`. The bound `T: AtomicValue` checks T
(`Atomic<f64>`: "the trait 'AtomicValue' is not implemented for
'f64'"); no program can implement it. The orderings are Rust's
(`Ordering::Relaxed`, `Acquire`, `Release`, `AcqRel`, `SeqCst`). An
atomic is Sync, so a plain `static` of one is shared by every thread:
`static HITS: AtomicI64 = AtomicI64::new(0);`.

```vole
use std::sync::atomic::{AtomicI64, Ordering};

fn main() {
    let n = AtomicI64::new(5);
    let old = n.fetch_add(3, Ordering::Relaxed);
    let r = n.compare_exchange(8, 10, Ordering::AcqRel, Ordering::Acquire);
    println("{old} {} {}", r.is_ok(), n.load(Ordering::SeqCst));
}
```
```out
5 true 10
```

On AArch64 they are `ldar`/`stlr` and LSE's `ldadd`, `cas`, `swp`... on
macOS, exclusive-pair loops (`ldxr`/`stxr`) on Linux (`--atomics=lse` or
`--atomics=llsc` chooses). The optimizer moves no memory access across an
atomic or a fence, and invents no store to memory another thread may see.

## Threads

`std::thread::spawn_in(f, gpa)` runs the closure on a new thread (Rust's
`spawn`, with the allocator its closure and result live on until the
join); its handle's `join()` waits and gives `Ok(result)`. The closure
is `FnOnce() -> T + Send + 'static`: the thread may outlive the caller,
so it owns what it captures (`move`), and a borrow of a local is
`borrowck.dropped_borrowed`; a raw pointer is not Send
(`sync.not_send`). `thread::scope(|s| ...)` joins every thread started
with `s.spawn(..)` before it returns, so those may borrow the caller's
locals, shared or (one thread) mutably, as the borrow checker allows.

```vole
use std::sync::atomic::{AtomicI64, Ordering};
use std::thread;

static HITS: AtomicI64 = AtomicI64::new(0);

fn sum(s: &[i64]) -> i64 {
    let mut t = 0;
    for x in s { t += *x; }
    HITS.fetch_add(1, Ordering::Relaxed);
    t
}

fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    for i in 0..1000 { v.push(i); }
    let s = v.as_slice();
    let total = thread::scope(|sc| {
        let a = sc.spawn(|| sum(&s[0..500]));
        let b = sc.spawn(|| sum(&s[500..]));
        a.join().unwrap() + b.join().unwrap()
    });
    let h = thread::spawn_in(move || v.len(), gpa);
    println("{total} {} {}", h.join().unwrap(), HITS.load(Ordering::Relaxed));
}
```
```out
499500 1000 2
```

`thread::yield_now()`, `thread::sleep(d)`, `thread::available_parallelism()`
(a `usize`). Printing is safe from any thread: once threads run, each
print holds a lock, so output never interleaves.

Not in std2 yet: `Mutex`, `RwLock`, `Arc`, `Once`, `Condvar` and the
channels (`std::sync::mpsc`); share an atomic, or join and return the
results.

## Thread-locals

`#[thread_local] static mut X: T = INIT;` gives each thread its own `X`,
made from `INIT` when the thread first uses it; using it is `unsafe`, as
any `static mut`. A thread-local's drop does not run. A `static` of a
`Cell` is `sync.static` (a Cell is not Sync).

```vole
use std::thread;

#[thread_local]
static mut CALLS: i64 = 0;

fn work() -> i64 {
    for _ in 0..3 { unsafe { CALLS += 1; } }
    unsafe { CALLS }
}

fn main(gpa: Gpa) {
    let h = thread::spawn_in(|| work(), gpa);
    unsafe { CALLS = 100; }
    println("{} {}", h.join().unwrap(), unsafe { CALLS });
}
```
```out
3 100
```

## Effects

Three effects: `sync` (an atomic, a fence, a join), `thread` (starting a
thread) and `tls` (a thread-local). `query effects f` shows them;
`#[pure]` excludes them.
