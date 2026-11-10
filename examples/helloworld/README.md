# helloworld

The smallest vole program: one line of output and an exit status.

## Build and run

From this folder (with `volec` on your `PATH`, or `../../target/volec`
after `bootstrap/bootstrap.sh`):

```sh
volec run                                   # build main.vl (when it changed), run it
volec main.vl -o helloworld && ./helloworld # the executable itself, here
```

`volec` compiles the program and links it with the system's C compiler
(`cc`, or `$VOLE_CC`); `volec run` keeps the executable in volec's cache
(`volec run examples/helloworld` from the tree's root). `-o
helloworld.o` makes an object instead, and `-o helloworld.s` assembly.

## Expected output

```text
Hello from vole!
```

## How it works

```tach
fn main() -> i32 {
    println("Hello from vole!");
    0
}
```

- `main` returns the process's exit status. Its last expression, `0`,
  written without a `;`, is the value of the body: there is no `return`.
  `fn main()` with no result type exits with 0 too.
- `"Hello from vole!"` is a `&str`, UTF-8 text. A literal needs no
  allocation; text that grows is built in a `String`, on an allocator.
- `println` comes from the prelude, the part of `std` every module sees
  without a `use`. It takes a format string (`println("{x} {}", y)`,
  any `Display` value) and adds a newline; `print` leaves the newline
  out. It is a function: vole has no macros, so no `!`.

## Language features

- functions, the block's value as the result: `volec guide syntax`
- string literals, `&str`: `volec guide text`
- the prelude (`println`, `print`, `Vec`, `Option`, ...): `volec guide modules`
