# c-libc-tour

A walk through the C library from vole, using nothing but the
system's own headers: the environment (`setenv`, `getenv`, `unsetenv`),
time (`gmtime`, `localtime`, `strftime`, `mktime`, `tzset`), files
(`fopen`, `fwrite`, `chmod`, `mkdir`, `mkdtemp`) and directories
(`opendir`, `readdir`, `stat`, `unlink`, `rmdir`). The C structs involved
(`struct tm`, `struct stat`, `struct dirent`) differ between macOS and
Linux; `import` reads them from the headers of the system the program is
compiled for, so one source fits both.

With arguments, it lists those directories instead, like a small `ls -l`.

## Build and run

From this folder (with `volec` on your `PATH`, or as
`../../target/volec` from a built tree):

```sh
volec main.vl -o c-libc-tour && ./c-libc-tour
./c-libc-tour /etc ~       # list directories instead
```

Everything it calls is in the C library, so it links as it is on macOS
and Linux. `import` needs a C compiler that can preprocess the target's
headers: building for your own machine always works; cross-compiling
for Linux from a Mac needs `VOLE_CC` set to a cross C compiler with a
Linux sysroot (the compiler says so when it is missing).

## Expected output

The tour prints the same text on every run and system: it uses a fixed
moment, sets its own time zones, and makes (then removes) its own
directory.

```
== environment
TOUR_GREETING = Some("hello from setenv")
TOUR_MISSING  = None
PATH is set: true
== time
1234567890 is Friday, 13 February 2009, 23:31:30 UTC
  struct tm: year 2009, month 2, day 44 of the year, weekday 5
  UTC0      2009-02-13 23:31:30 +0000  (UTC+0:00)
  JST-9     2009-02-14 08:31:30 +0900  (UTC+9:00)
  NPT-5:45  2009-02-14 05:16:30 +0545  (UTC+5:45)
  <-03>3    2009-02-13 20:31:30 -0300  (UTC-3:00)
100 days later: 2009-05-24, a Sunday (8640000 seconds later)
== files
made three files and a directory: true
the directory: 4 entries
-rw-r--r--     12  data.csv
-rw-r--r--      0  empty
-rw-------     17  notes.txt
drwxr-xr-x  <dir>  subdir/
total 29 bytes in files
removed it again: true
```

A directory it cannot open is reported on stderr:

```
$ ./c-libc-tour /no/such/directory
cannot open /no/such/directory
```

## How it works

### Seven headers, one `c`

```tach
import "stdlib.h" as c;
import "time.h" as c;
import "dirent.h" as c;
import "sys/stat.h" as c;
// ... stdio.h, string.h, unistd.h
```

Every imported header adds to one C module, here called `c`: functions
(`c::readdir`), structs (`c::tm`, `c::stat`, `c::dirent`, `c::DIR`,
`c::FILE`), and integer macros as constants (`c::S_IFMT`, `c::S_IFDIR`).
The declarations are those of the target's libc: on macOS `struct stat`
has `st_birthtimespec` and a 16-bit `st_mode`, on Linux neither, and the
program never has to know. `volec --emit-imports main.vl -o
decls.vl` writes out what the headers gave, as vole source.

What headers cannot give: function-like macros (`S_ISDIR(m)`: the example
writes `is_dir` with `S_IFMT` instead), `static inline` functions, and
`errno` (a macro over `__error()` on macOS, `__errno_location()` on
Linux).

### Vole text and C strings

C wants NUL-terminated strings; a vole `&str` is a pointer and a
length with no NUL. Two small helpers cross the line, each with one
direction:

```tach
// vole -> C: copy the bytes and a 0 into a Vec; pass its as_ptr()
fn cstring(s: &str, gpa: Gpa) -> Vec<u8, Gpa> {
    let mut b = Vec::<u8, Gpa>::new_in(gpa);
    b.extend_from_slice(s.as_bytes());
    b.push(0);
    b
}

// C -> vole: copy the C string into a String of our own
unsafe fn owned(p: *const u8, gpa: Gpa) -> String<Gpa> {
    String::from_utf8_lossy_in(std::slice::from_raw_parts(p, c::strlen(p) as usize), gpa)
}
```

Copying out matters: `readdir` reuses its `struct dirent`, and a later
`setenv` may move what `getenv` returned. A `String` belongs to the
program, and is dropped (freed) at the end of its owner's scope. The
copy also checks the text: bytes that are not UTF-8 (a file name may
hold any) become U+FFFD.

Every `unsafe` block, `unsafe fn` and `extern` block in the program has
two comments above it: `// UNSAFE:` why it is needed, `// SAFETY:` why
it is sound. The snippets here leave them out.

### getenv: NULL becomes None

```tach
fn env(name: &str, gpa: Gpa) -> Option<String<Gpa>> {
    let cname = cstring(name, gpa);
    unsafe {
        let p = c::getenv(cname.as_ptr());
        if p.is_null() { None } else { Some(owned(p, gpa)) }
    }
}
```

The unsafe C call is wrapped once; the rest of the program uses a safe
function with a vole type. `{greeting:?}` prints the
`Option<String<Gpa>>` with Debug: `Some("hello from setenv")`.

### Time: struct tm, strftime, TZ

```tach
let mut utc: c::tm = unsafe { *c::gmtime(&when) };
let long = format_time("%A, %d %B %Y, %H:%M:%S UTC", &utc, gpa);
```

`gmtime` and `localtime` return a pointer to a static `struct tm` inside
the C library; `*` copies it into a vole local, after which it is
ours. `&when` passes the address of an `i64` where C wants a `time_t *`.
`format_time` calls `strftime` into a stack array (`[u8; 128]`, passed as
`out.as_mut_ptr()`) and keeps the `n` bytes it wrote.

`localtime` follows the `TZ` environment variable, which `tzset` rereads.
The zones are POSIX strings (`JST-9`: a name and the offset *west* of
UTC), which need no time zone database, so the output is the same on a
minimal Linux container. `mktime` goes the other way and normalizes: day
113 of February 2009 is the 24th of May. It writes the normalized fields
back, so it takes `&mut utc`.

### Directories: opendir, readdir, stat

```tach
let d = unsafe { c::opendir(cdir.as_ptr()) };
if d.is_null() {
    return None;
}
let _dir = Dir { d };
loop {
    let name = unsafe {
        let ent = c::readdir(d);
        if ent.is_null() {
            break;
        }
        owned((*ent).d_name.as_ptr(), gpa)
    };
    ...
}
```

`DIR` is whatever the header says it is; the program only holds a
pointer. `Dir` is a guard: its `Drop` calls `closedir`, so the directory
is closed on every way out of the function:

```tach
struct Dir { d: *mut c::DIR }

impl Drop for Dir {
    fn drop(&mut self) { unsafe { c::closedir(self.d); } }
}
```

`d_name` is a `char` array inside the struct: `(*ent).d_name.as_ptr()`
is its address, a C string. `readdir` returns names in the file system's
order, so the entries are sorted with a closure:
`entries.sort_by(|a, b| a.name.cmp(&b.name))`.

`stat` fills a `struct stat` the program has to provide. Its fields
differ between systems, so it is not written out field by field but
made of zero bytes:

```tach
unsafe fn zeroed<T>() -> T {
    let p = c::calloc(1, size_of::<T>() as u64) as *mut T;
    if p.is_null() { panic("out of memory"); }
    let value = std::ptr::read(p);
    c::free(p as *mut u8);
    value
}

let (status, st) = unsafe {
    let mut st: c::stat = zeroed();
    (c::stat(path.as_ptr(), &mut st), st)
};
if status == 0 {
    e.size = st.st_size;
    e.mode = st.st_mode; // u16 on macOS, u32 on Linux: it widens
}
```

`zeroed` is generic: `T` comes from the type the result is given
(`c::stat`), and the same function serves any C struct whose all-zero
bytes are a valid value, which is its `unsafe` contract. Assigning
`st.st_mode` to a `u32` field compiles on both systems because integer
widening (`u16` to `u32`) is implicit and lossless; narrowing would need
`as`.

### Files and permissions

`write_file` opens with `fopen`, writes the text with
`fwrite(text.as_ptr(), 1, text.len() as u64, f)` (a `&str` needs no NUL
when its length goes along), and sets the mode with `chmod` so the umask
does not change the output. C's octal `0755` is written `0o755`, in a
named constant. `mkdtemp` writes the random part of the name into its
template, so the template is a `Vec` of the program's
(`template.as_mut_ptr()`), not a read-only `c"..."` literal.

## C interop rules in brief

- **Declaring C**: `import "header.h" as c;` brings the system's
  declarations; `extern "C" { ... }` declares by hand. All C calls are
  `unsafe`.
- **Structs from headers** are `#[repr(C)]` structs with the target's
  layout; use their fields by name, never by offset.
- **Pointers from C** are raw: ask `p.is_null()` for NULL, and read
  through them only inside `unsafe`. Turn NULL into `None` at the
  boundary.
- **Strings**: `c"..."` for literals; copy a `&str` into a
  NUL-terminated buffer for C; copy C strings out
  (`String::from_utf8_lossy_in` over `slice::from_raw_parts`) before C
  reuses them.
- **Memory**: whatever C allocates, C frees (`closedir`, `free`); whatever
  vole allocates (`String`, `Vec`), vole frees, when it is dropped.
- **Linking**: all of this is libc, which `volec -o prog` links.

## Language features

- `import "x.h" as c`, C structs and constants, `c"..."`, C strings:
  `volec guide c-interop`
- `unsafe fn` with a contract (a generic one, `zeroed<T>`), raw
  pointers, `&mut x` where C wants a pointer: `volec guide unsafe`
- a guard with `Drop` for C resources, `String` and its drop: `volec guide memory`
- `Option` at the boundary, `{x:?}` on an `Option<String<Gpa>>`:
  `volec guide conversions`, `volec guide formatting`
- `sort_by`, `split`, `count`, `enumerate` with closures and iterators:
  `volec guide iterators`, `volec guide closures`
- implicit widening (`u16` to `u32`): `volec guide conversions`
