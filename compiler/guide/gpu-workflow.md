# Working on a GPU example: shader, check, headless run

The loop for a change to a program that uses `std::gpu` (the examples
under `examples/gpu/`): edit, check, build, run without a window, look
at the numbers. The API itself is `volec guide gpu` (long: ask for one
section, `volec guide gpu#compute`, or `volec guide --find WORDS`).

## Where the shader is

A shader is WGSL in an `embed wgsl` item: a block, `embed wgsl NAME {
.. }`, or a file beside the source, `embed wgsl NAME from "x.wgsl";`.
`volec query grep 'embed wgsl' --root DIR/main.vl` lists a program's.
A `.wgsl` file is a file of the program that embeds it: `volec query
show x.wgsl` prints it (a long one: `query text x.wgsl:A-B`), `query
grep TEXT --in x.wgsl` finds a line, and `volec edit patch x.wgsl
--old A --new B` changes it, checked: an edit that breaks the shader
is refused with its error.

## Check after every shader edit

The shader is checked with the program that embeds it, not alone:

```sh
volec check examples/gpu/pathtrace/main.vl   # or, in the directory: volec check
```

A clean check says what it read, `ok: 0 errors in
examples/gpu/pathtrace/main.vl (9 files, 3 shaders)`; `0 shaders`, or
another root, means it was not your program (`volec check` with no ROOT
at the tree's root checks the compiler). A WGSL error is at the
shader's own line: `trace.wgsl:51:34: error[wgsl.name] unknown name
'x'`. An edit made without `volec edit` is checked by nobody: run
`volec check --changed` (every program the changed files belong to).

## Build and run headless

```sh
volec -O2 examples/gpu/pathtrace/main.vl -o pathtrace     # about a second
./pathtrace --headless --samples 16 --size 96x64 --out shot.ppm
```

`--headless` needs no display: the same pipelines draw into a surface
that is read back, the program checks its own image (`render ok`,
`reset ok`; exit 1 when a check fails) and `--out` writes a PPM. Start
small: the path tracer runs from `--samples 1 --size 1x1` (its noise
check wants 2 samples and 8x8, and says `progress skipped` under that).
`PROG --help` lists the options; each example's README has its command
lines:

| example | where in its README | a first command |
|---|---|---|
| pathtrace | Headless verification, Reproducible benchmark | `--headless --samples 16 --size 96x64` |
| life, galaxy | the top (the run commands) | `--headless --out x.ppm --size 960x600` |
| fluid2d | The headless check | `--headless --check` |
| voxel | Verification, Benchmark | `--headless --size 320x200 --out voxel.ppm` |
| galaga, relativity | the top (the run commands) | `--headless` |

Its tests are the cases whose name holds the example's:
`tests/run.sh pathtrace`.

## Sweeping a parameter: do not edit the shader

To try values of a number the shader reads, make it data:

- a uniform: a field of the `#[repr(wgsl)]` struct the program writes
  each frame, set from a command-line option (`std::cli`); one build,
  many runs;
- a constant: a `const` named in the block's `with` is the shader's
  `const` too, so one line of vole changes it (a rebuild a value).

```vole
const BOUNCES: u32 = 4;

embed wgsl TRACE with BOUNCES {
    @group(0) @binding(0) var<storage, read_write> image: array<f32>;
    @compute @workgroup_size(1) fn main() {
        image[0] = f32(BOUNCES);
    }
}

fn main() {
    println("{} bounces, shader embedded: {}", BOUNCES, TRACE.src.len() > 0);
}
```
```out
4 bounces, shader embedded: true
```

`volec guide gpu#shared-constants-and-structs` has the struct form.
