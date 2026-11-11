# errors-and-results

A config-file parser that treats errors as typed values: two layers of
error enums, `?` to pass errors up, `From` to convert a lower layer's
error into a higher one's, `map_err` and `ok_or` to add context, the
difference between "absent" (`Option`) and "failed" (`Result`), and a
`main` that returns a `Result`.

## Build and run

From this folder (with `volec` on your `PATH`, or `../../target/volec`):

```sh
volec main.vl -o errors-and-results
./errors-and-results < server.conf      # a good config: exit 0
./errors-and-results < broken.conf      # a bad one: exit 1
```

The config is one `key = value` per line, `#` starts a comment:

```text
# the demo server
name = demo
port = 8080
workers = 4
debug = true
```

`port` is required (1 to 65535); `name`, `workers` (1 to 64), `debug`
(`true`/`false`) and `timeout_ms` (0 to 60000) have defaults.

## Expected output

First the program parses a few built-in bad samples and prints why each
was rejected (errors handled as values), then it parses stdin. With
`server.conf`:

```text
rejected samples:
  "port = 80\nport = 81"     line 2: `port` is set twice
  "port: 80"                 line 1: expected `key = value`
  "port = 80\ncolour = blue" line 2: unknown key `colour`
  "port = 8o"                line 1: port: not a number (invalid digit found in string)
  "port = 70000"             line 1: port: 70000 is not in 1..=65535
  "port = 80\ndebug = yes"   line 2: debug: expected true or false
  "name = no port"           `port` is required
config: demo on port 8080
  workers 4, debug true, timeout 1000 ms
```

With `broken.conf` (`workers = many` on line 3) the same seven lines,
then on stderr, with exit status 1:

```text
Error: BadValue(3, "workers", NotANumber(ParseIntError { kind: InvalidDigit }))
```

## How it works

**Two layers, two error types.** The value layer parses one value and
knows nothing of files; the file layer knows lines and keys. Each layer
has its own enum, and `#[derive(Debug)]` writes the Debug text that
`main` prints on failure:

```vole
#[derive(Debug)]
enum ValueError { NotANumber(ParseIntError), NotABool, OutOfRange(i64, i64, i64) }

#[derive(Debug)]
enum ConfigError<A: Allocator> {
    Read(io::Error),
    NoEquals(i64),
    UnknownKey(i64, String<A>),
    Duplicate(i64, String<A>),
    BadValue(i64, String<A>, ValueError),
    Missing(String<A>),
}
```

**`?` with `From`.** `parse::<i64>()` fails with std's `ParseIntError`.
Because `ValueError` implements `From<ParseIntError>`, `?` converts the
error on its way out; no `match` needed:

```vole
impl From<ParseIntError> for ValueError {
    fn from(e: ParseIntError) -> ValueError { ValueError::NotANumber(e) }
}

fn parse_number(text: &str, lo: i64, hi: i64) -> Result<i64, ValueError> {
    let n = text.parse::<i64>()?; // Err(ParseIntError) returns Err(ValueError::from(e))
    if n < lo || n > hi { return Err(ValueError::OutOfRange(n, lo, hi)); }
    Ok(n)
}
```

The same happens in `main`: `io::read_to_string_in(io::stdin(), gpa)?`
turns std's `io::Error` into a `ConfigError` through `impl<A: Allocator>
From<io::Error> for ConfigError<A>`.

**`map_err` adds context.** A `ValueError` does not know its line or
key; the file layer wraps it with both before passing it up. When the
conversion needs more than the error itself, `map_err` with a closure
does it instead of `From`:

```vole
let n = parse_number(field.value, lo, hi).map_err(|e| {
    ConfigError::BadValue(field.line, String::from_in(key, *fields.allocator()), e)
})?;
```

(The error owns a copy of the key, made on the map's allocator: see
"An error that owns its text" below.)

**Option means absent, Result means failed.** A missing optional key is
not an error, a malformed one is, so the getter returns
`Result<Option<i64>, ConfigError<Gpa>>`. The caller decides what absence
means: a default with `unwrap_or`, or an error with `ok_or`:

```vole
Ok(Config {
    name: fields.get(&"name").map(|f| f.value).unwrap_or("unnamed"),
    port: number(&fields, "port", 1, 65535)?
        .ok_or(ConfigError::Missing(String::from_in("port", gpa)))?,
    workers: number(&fields, "workers", 1, 64)?.unwrap_or(1),
    debug: flag(&fields, "debug")?.unwrap_or(false),
    timeout_ms: number(&fields, "timeout_ms", 0, 60000)?.unwrap_or(1000),
})
```

`ok_or` also turns a failed split into an error with the line number
(the error's allocator is named, `::<Gpa>`: nothing else in the
expression says which it is, since `?` may convert the error):

```vole
let (key, value) = line.split_once("=").ok_or(ConfigError::<Gpa>::NoEquals(number))?;
```

**Drops run on every exit.** `parse_config` allocates a `HashMap`, which
is dropped when the function returns; each `?` that returns early drops
it too, so no path leaks it.

**Display for people, Debug for programmers.** `impl Display` writes
the messages printed for the rejected samples (`{e}`); the derived Debug
is what `main` prints on failure. Each `Display` impl may use the inner
error's own `Display`: `write(f, "not a number ({e})")`.

**`main` returns a Result.** On `Ok(())` the exit status is 0; on
`Err(e)` the program prints `Error: ` and `e`'s Debug text on stderr and
exits with 1, as Rust does:

```vole
fn main(gpa: Gpa) -> Result<(), ConfigError<Gpa>> {
    show_rejections(gpa);
    let input = io::read_to_string_in(io::stdin(), gpa)?; // io::Error -> ConfigError through From
    let config = parse_config(&input, gpa)?;
    ...
    Ok(())
}
```

**An error that owns its text.** `UnknownKey` and the others carry the
key as a `String`, a copy, not a `&str` borrowed from `input`: `main`
prints its error *after* it returns, and `input` is dropped when main
returns. A `&str` there would outlive its owner, which the borrow
checker rejects (`borrowck.return_local`: a reference to `input`, a
local of this function, escapes it). An owned field is what its help
suggests for a value that must outlive its source. The fields of a
`Config`, which never leave `main`, do borrow the text: `Field<'a>`,
`Config<'a>`.

## Language features

- `?`, `From`/`Into`, `main -> Result`, std's error enums: `volec guide conversions`
- `Option`/`Result` methods (`map`, `map_err`, `ok_or`, `unwrap_or`): `volec guide std`
- `#[derive(Debug)]`, `impl Display`, `{x:?}`, `{x:<26}`: `volec guide formatting`
- closures given to `map_err`, `map`, `any`: `volec guide closures`
- drops, `HashMap`, `lines`, `split_once`, `trim`: `volec guide std`, `volec guide memory`
- lifetimes on a struct and a `type` alias (`type Fields<'a> = HashMap<&'a str, Field<'a>, Gpa>;`): `volec guide generics`

## Going further

- No `Box<dyn Error>` or `anyhow`: errors are enums, one per layer, with
  `From` impls between them. Every case is visible to `match`.
- `unwrap` on an `Err` or `None` stops the program with a fixed message
  and exit status 101; for a message of your own, `match` and
  `unwrap_or_else`, or return a `Result` as here.
- `let ... else` is the other way to handle absence:
  `let Some(field) = fields.get(&key) else { return Ok(None); };` does
  what `number`'s `match` does, with one level less of nesting.
