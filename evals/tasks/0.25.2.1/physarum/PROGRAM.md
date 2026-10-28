# physarum

Physarum (slime mould) on the GPU, in vole: 1,048,576 agents sense a
trail map ahead and to both sides, turn toward the strongest, move, and
deposit into the trail. The trail is blurred (3 x 3), mixed with its old
value, decayed, and drawn through a colour ramp (black, teal, pale yellow).
The map wraps at its edges (a torus).

## Files

- `main.vl`: the command line, the headless checks, the windowed loop,
  the keys and the mouse.
- `sim.vl`: the buffers, the pipelines, one step (four dispatches in one
  submission), the picture and the read-backs used by the checks.
- `shaders.vl`: the WGSL: init, clear, agents, diffuse, render. Each
  kernel is its own module, joined to a shared prefix (`COMMON`).
- `tune.vl`: the knobs, the pointer, key mapping, the CPU-side recurrence,
  and the `#[test]`s.

## Build and run

```sh
volec main.vl -o physarum
./physarum                                   # the window (1024 x 1024)
./physarum --headless                        # checks, 300 steps, 1M agents
./physarum --headless --steps 1000 --shot trail.ppm
```

Headless options: `--agents N` (1000 to 4194240), `--size N` (the map's
side, 64 to 2048, default 1024), `--steps N`, `--every N` (a check every N
steps), `--shot FILE.ppm` (the trail after the steps). Window options:
`--agents`, `--size`, `--frames N` (quit after N frames), `--shot FILE.ppm`
(with `--frames`, the last frame).

The GPU runs through the shared lock, e.g.
`../tools/gpu-run -- ./physarum --headless`.

## Controls (window)

| key | does |
|---|---|
| a / z | sensor angle down / up (0.05 to 1.5 rad) |
| s / x | sensor distance down / up (1 to 40 cells) |
| d / c | turn speed down / up (0.01 to 1.5 rad a step) |
| f / v | decay down / up (0 to 0.5 of the trail a step) |
| g / b | diffuse down / up (0 to 1: the share of the blur) |
| left mouse, held | adds food (a disc of 8 cells, +6 a step) |
| right mouse, held | adds repellent (the same disc, -6 a step) |
| space | pause / resume (the agents and the trail stop) |
| r | restart: trail empty, agents placed again |
| q or Escape | quit |

The title bar shows the knob values and whether the run is paused.

## What the headless run checks

1. **Trail total.** The blur keeps the sum of the trail, and every agent
   adds exactly one unit a step, so the total must follow
   `T' = (1 - decay) * (T + agents)`. Every check (every `--every` steps)
   compares the GPU's total (summed on the CPU in f64) with that
   recurrence. The verdict is `ok` when the worst relative error is
   under 1e-3.
2. **Agents inside.** Every agent's position must be finite and inside
   `[0, size) x [0, size)`. Verdict `ok` when all of them are.

It also prints the mean resultant length of the headings after the reset
(about 1/sqrt(n) for a uniform spread).

Exit status is 0 when both checks pass, 1 otherwise.

## What I verified and how

- `volec check main.vl`: ok, 0 errors.
- `volec test main.vl`: 5 passed (-O0 and -O2 agree). They cover the knob
  clamps, the key mapping, the recurrence's fixed point and the relative
  error.
- Headless, 1M agents, 1024 map, 300 steps (run through gpu-run):
  worst relative error of the trail total 2.5e-7, all agents inside,
  about 0.9 ms a step with the read-backs (0.65 ms over 1000 steps).
- Headless, 4,194,240 agents, 2048 map, 1000 steps: trail check ok
  (2.4e-7), all agents inside, about 5.4 ms a step.
- The picture after 300 steps (`shot.png`, from `shot.ppm`) shows the
  developed network. An early version with a weak integer hash showed
  diagonal bands: the early-step picture and the heading check were how
  I found it, and the hash was replaced (a lowbias32 mix, applied twice).
- The window: `./physarum --frames 120 --shot win.ppm` runs and writes a
  frame, through gpu-run. The display was asleep, so frames came from the
  10 fps timer; I could not watch the window or time its frames.

Not verified: the keys and the mouse. They compile and go through the same
`Tune::adjust` and `Pointer` paths the headless run uses, but I did not
drive them with real input.

## Limits

- The agent count is at most 4194240 (65535 workgroups of 64 in one
  dimension); the map side is at most 2048 (the clear pass uses
  workgroups of 256 in one dimension).
- Deposits are fixed point: 1024 units per agent a step, u32 per cell.
  Beyond about 4 million agents in one cell it would overflow.
