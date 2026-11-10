# md5

The MD5 digest (RFC 1321) of a file, or of stdin, printed in hex like
`md5sum`. Fixed-size arrays, `u32` arithmetic that wraps, a streaming
hash state, and `std::fs` and `std::io` for the bytes.

## Build and run

From this folder (with `volec` on your `PATH`, or `../../target/volec`):

```sh
volec main.vl -o md5
printf abc | ./md5
./md5 README.md          # a file
```

## Expected output

```text
900150983cd24fb0d6963f7d28e17f72
```

for `abc`; `d41d8cd98f00b204e9800998ecf8427e` for empty input. The result
agrees with `md5sum` (the Linux checks of the bootstrap compare them on 3
MB of random bytes), and the benchmarks (`bench/run.sh`) time it against
the same program in C.

## How it works

**Tables as statics.** The 64 round constants and shifts are arrays of
`u32`, known at compile time:

```tach
static K: [u32; 64] = [0xd76aa478, 0xe8c7b756, ...];
```

**Arithmetic that wraps.** MD5 is defined modulo 2^32. A plain `+` that
overflows panics at -O0 (and wraps at -O1 and above), so the additions
say what they mean: `f.wrapping_add(a).wrapping_add(K[i])` wraps at
every level.

**A streaming state.** `Md5` keeps the four state words, the bytes of an
incomplete 64-byte block, and the total length; `update` takes any number
of bytes, and `finish` pads the message and returns the digest as a
`[u8; 16]` (an array, a value: returned by copy):

```tach
struct Md5 { state: [u32; 4], block: [u8; 64], used: usize, total: u64 }

impl Md5 {
    fn update(&mut self, data: &[u8]) { ... }
    fn finish(&mut self) -> [u8; 16] { ... }
}
```

Methods take `&mut self`, an exclusive borrow, to change the state in
place; `hash.update(...)` borrows `hash` itself.

**Slices of an array.** `compress` gets each block as a slice,
`&rest[..64]`, a pointer and a length into the bytes read: no copy.
Indexing and slicing are bounds-checked. The pending block is the
exception: `self.compress(&self.block)` would borrow `self.block` while
the call borrows `self` mutably (`borrowck.conflict`), so `update` copies
the 64 bytes first.

**Reading through std::io.** `digest` is generic over `io::Read`, which
a `File` and stdin both implement, and reads 64 KiB at a time; `?`
passes a read error up as an `io::Error`. The `File` closes when it is
dropped, whatever path `main` leaves by:

```tach
fn digest<R: Read>(input: &mut R) -> io::Result<[u8; 16]> {
    let mut hash = Md5::new();
    let mut chunk: [u8; 65536] = [0; 65536];
    loop {
        let n = input.read(&mut chunk)?;
        if n == 0 { break; }
        hash.update(&chunk[..n]);
    }
    Ok(hash.finish())
}
```

**Hex output.** Each byte is two hex digits; the format spec `02x` pads
with a zero to a width of 2:

```tach
for byte in bytes {
    write(&mut hex, "{byte:02x}").unwrap();
}
```

## Language features

- fixed-size arrays, slices, `u32`/`u64` and wrapping arithmetic: `volec guide types`
- statics, structs, methods on `&mut self`: `volec guide syntax`
- files, `io::Read`, `io::Result` and `?`: `volec guide io`
- generics with a trait bound: `volec guide generics`
- hex format specs, `write` to a String: `volec guide formatting`
