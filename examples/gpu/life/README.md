# life

A massive Conway's Game of Life — 4096×4096 cells by default, 16.7
million of them — computed and drawn on the GPU. Every generation is
one `@compute` kernel over a `u32` storage buffer; the window is one
fullscreen shader that reads that same buffer. Draw with the left
button, erase with the right, pan, and scroll to zoom from the whole
field down to individual cells.

```sh
target/volec -O2 examples/gpu/life/main.vl -o life
./life                         # 4096×4096
./life --grid 8192        # 67 million cells, if the GPU has the memory
./life --density 0.3 --seed 7
./life --headless              # no display needed: the self-check
./life --headless --out life.ppm --size 960x600
./life --headless --benchmark --grid 4096
```

The camera opens on the whole grid: at 4096 cells across, a cell is
about a fifth of a pixel, so the field opens as a field; scroll in to
see the cells, the grid lines and the age colours. The title bar
carries the frame rate and the generations per second.

| input | action |
|---|---|
| left drag | draw (Shift+left erases) |
| right drag | erase |
| middle drag | pan |
| scroll | zoom around the pointer |
| space | pause / resume |
| `n` / `.` | one generation |
| `r` | a new random field |
| `c` | clear |
| `g` | grid lines on / off |
| `[` / `]` | smaller / larger brush |
| `0` / Home | fit the whole grid |
| `+` / `-` | zoom in / out |
| `f` | fullscreen |
| `q` / Esc | quit |

## The parts

| file | what |
|---|---|
| [life.vl](life.vl) | the cell buffers, the `step` and `spray` WGSL kernels, and the `Life` that seeds, clears, paints and steps them |
| [view.vl](view.vl) | the `vs`/`fs` fullscreen shader (age colours, nine-tap minification, grid lines, brush ring), the `Viewer` pipeline and the camera uniform |
| [check.vl](check.vl) | `--headless`: a blinker, the torus' seam, density 0 and 1, a painted segment, the evolution against a CPU reference, one rendered frame read back, and `--benchmark` on the full grid |
| [main.vl](main.vl) | the CLI, the window, the event loop, the camera, the brush and the title's rates |

## What it shows on std::gpu

- **Ping-pong storage buffers.** `step` binds the current side as
  `var<storage, read>` and the other as `read_write`, counts eight
  neighbours (with `(x + w - 1) % w`, so the grid is a torus), and
  writes the next generation into the other side. `Life::step` flips
  `cur`; the renderer's two bind groups read whichever side is current.
  A dead cell with three neighbours is born at age 1, a living cell
  with two or three survives at `min(age + 1, 255)`.
- **No readbacks in the interactive path.** Seeding is a hash kernel
  (`hash2(x, y, seed) < density·2³²`), not a CPU loop, and painting is a
  capsule kernel: the segment between the pointer's last and current
  cell, swollen by the brush radius, over just its bounding box. A fast
  drag leaves an unbroken stroke in one dispatch, and nothing but the
  64-byte uniform and the mouse coordinates crosses the bus.
- **The renderer reads the simulation's buffers directly.** The
  fragment shader takes its own pixel position through the camera (a
  cell-space centre and pixels per cell) and reads `cells[...]` from the
  same storage buffer. Age drives the colour, young cyan to old amber;
  at less than one pixel per cell, five jittered taps average the cells
  under a pixel. Grid lines fade in once a cell is three pixels wide,
  and the brush is a ring in cell space.
- **A checked CPU reference.** `check.vl` runs the same rules, cell by
  cell in u32, double-buffered like the GPU, on a small grid (at most
  128×128 — the CLI's grid is used for the benchmark). It compares the
  exacter ages, not just life: the GPU and the CPU must agree on every
  cell's age after `--steps` generations. Blinkers check both
  orientations, a blinker on column 0 checks the seam, density 1 dies of
  overcrowding, and the eraser takes a painted line back to empty.

## How fast

The step is memory-bound: nine `u32` reads and one write per cell, all
in one pass. Measured on an Apple M5, `--benchmark`, twelve steps after
one warm-up:

| grid | cells | ms/step | cells/s |
|---|---|---|---|
| 1 024² | 1.0 M | 0.34 | 3.1 G |
| 2 048² | 4.2 M | 0.97 | 4.3 G |
| 4 096² | 16.7 M | 2.0 | 8.4 G |
| 8 192² | 67.1 M | 7.5 | 8.9 G |

At the default 4096², a generation costs about 2 ms, so 30 generations a
second fit comfortably in a 60 fps frame, with the render pass and the
window still to spare. An 8192² grid holds
two 256 MiB buffers and stays under the default 1 GiB buffer limit;
larger grids stop at the device's limit with a message rather than
failing in the driver.

New to vole? `volec guide gpu` and `volec guide window` cover the APIs
this example uses.
