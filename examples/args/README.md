# args

Prints how many command-line arguments the program got, then each of
them, the program's own name first.

## Build and run

From this folder (with `volec` on your `PATH`, or `../../target/volec`):

```sh
volec main.vl -o args && ./args foo bar
```

## Expected output

```text
argc: 3
-- ./args
-- foo
-- bar
```

## How it works

`std::env::args()` is an iterator over the program's arguments, each a
`&str`, the program's own name first (C's `argv[0]`):

```tach
use std::env;

fn main() -> i32 {
    println("argc: {}", env::args().count());
    for arg in env::args() {
        println("-- {arg}");
    }
    0
}
```

`count()` consumes one iterator, so the loop asks for another; a program
that needs them twice can keep them, `env::args().collect_in(gpa)` (a
`Vec<&str, Gpa>`, with `fn main(gpa: Gpa)`).

## The same with std::cli

A program that takes flags and options declares them instead, with
`std::cli`, which parses them and gives `--help` and the errors for bad
arguments: [cli](../cli/) is this program with a flag and two options.

## Language features

- `std::env::args()`: `volec guide io`
- iterators, `count`, `for`: `volec guide iterators`
- format strings: `volec guide formatting`
- parsing flags and options instead: `volec guide cli`, [cli](../cli/)
