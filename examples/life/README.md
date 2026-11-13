# life

Conway's Game of Life in the terminal, as large as the window, starting
from random cells. Live cells are white; dead ones fade from blue to black
with the time since they died (ANSI 24-bit colour).

## Build and run

From this folder (with `volec` on your `PATH`, or `../../target/volec`):

```sh
volec main.vl -o life && ./life
```

It runs until interrupted (Ctrl-C). It needs a terminal with 24-bit
colour (most are), and prints `ioctl failed` when its output is not a
terminal.

## Expected output

An animation filling the window; nothing to compare. The test suite only
builds it.

## How it works

**The window size from C.** `ioctl(1, TIOCGWINSZ, &size)` fills a
`struct winsize`, declared with C's layout:

```tach
#[repr(C)]
struct Winsize { rows: u16, cols: u16, xpixel: u16, ypixel: u16 }
```

`#[repr(C)]` asks for C's field order and padding: a plain vole struct
has no fixed layout. `ioctl` is variadic, declared by hand with `...`.

**One binary per system, chosen at run time.** The request number differs
between Linux (`0x5413`) and macOS (`0x40087468`); `uname` tells which
system the program runs on. Its `struct utsname` starts with the system's
name on both, so the program compares the first bytes:

```tach
fn on_macos() -> bool {
    let mut names: [u8; 1280] = [0; 1280];
    if unsafe { uname(names.as_mut_ptr()) != 0 } {
        return false;
    }
    names.starts_with(b"Darwin")
}
```

`b"Darwin"` is a byte string, and `starts_with` compares bytes.

**The world** is two `Vec<Cell>`s, the current generation and the next;
`step` computes one from the other and swaps them. A `Vec` owns its
cells, so `step` cannot move one out of `self` (it would leave a hole):
`std::mem::swap` trades the two in place. A `Vec` moves as three words
(a pointer, a length, a capacity), not the cells:

```tach
std::mem::swap(&mut self.cells, &mut self.next);
```

The edges wrap around (a torus): `(x + width) % width`.

**One write per frame.** Each frame is built in a `String` (escape
codes to set the background colour, a space per cell) and written with
one `write`. The colour of a dead cell is a format string appended with
the prelude's `write` (which is why C's `write` is declared under
another name, `#[link_name = "write"] fn c_write(..)`):

```tach
let color = 255 - cell.age as i64;
write(out, "\x1B[48;2;{};{};{color}m ", color / 2, color / 5).unwrap();
```

## Language features

- `#[repr(C)]` structs, variadic `extern "C"` functions: `volec guide c-interop`
- a `Vec` that owns its cells, `std::mem::swap`, `String`: `volec guide memory`, `volec guide std`
- byte strings and slices: `volec guide text`
- format strings appended to a `String` (`write`): `volec guide formatting`
