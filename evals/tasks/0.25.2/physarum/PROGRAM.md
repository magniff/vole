# physarum

Jones's Physarum (slime mould) model on the GPU, in vole 0.25.2. A million
agents sense the trail one step ahead and to both sides, turn towards the
strongest, move and deposit. The trail is a grid of f32s; each step it is
blurred 3x3, decayed, and has the food added under the mouse. The deposit
goes through a fixed-point `atomic<i32>` grid (`atomicAdd`), cleared every
step. The picture is the trail through a colour ramp.

    volec main.vl -o physarum
    ./physarum                              # the window (1024 x 1024)
    ./physarum --headless --steps 400 --every 100 --shot shot.ppm
    ./physarum --headless --check           # verdicts only
    volec test main.vl                      # the CPU-side tests

## Window controls

| key | does |
|---|---|
| left mouse, held | food: adds trail under the pointer |
| right mouse, held | repels: agents near the pointer turn away |
| `[` `]` | sensor angle -/+ 2.5 degrees |
| `d` `f` | sensor distance -/+ 1 cell |
| `t` `y` | largest turn -/+ 2 degrees |
| `-` `=` | trail decay -/+ 0.01 a step |
| `o` `p` | diffuse (blur) -/+ 0.1 |
| `z` `x` | agent speed -/+ 0.25 cells a step |
| `g` `h` | colour gain -/+ 0.25 |
| `c` | palette: blue, fire, green |
| space | pause (the picture still draws) |
| `r` | reset: agents back in the centre, no trail |
| `q`, Escape | quit |

The window title shows the parameters, since there is no text rendering.
Keys repeat while held.

## Options

`--agents N` (1000000), `--size N` (1024: the trail is N x N cells),
`--angle`, `--dist`, `--turn`, `--speed`, `--decay`, `--diffuse`,
`--deposit`, `--food`, `--gain`, `--palette` (the starting values, same
units as the keys), `--frames N` (window: quit after N frames and print
the mean frame time), `--shot FILE.ppm` (with `--headless` or `--frames`).

## Headless checks

`--headless` runs `--steps` steps (default 300), reads the trail's total
and the agents' positions every `--every` steps, prints them and four
verdicts:

1. the trail's total is finite, positive and not falling from the first
   checkpoint to the last;
2. the last total is the decay balance, n x deposit x (1 - decay) / decay,
   within 1% (the trail's mass settles where what the agents add a step
   equals what decays; this holds with no food or mouse);
3. every agent is inside the grid at every checkpoint.

The exit status is 0 when all pass. Check 2 needs enough steps to settle:
decay 0.01 on a 512 grid did not settle in 300 steps (exit 1), and the
verdict says so; run more steps.

## What was verified, and how

- `volec main.vl -o physarum`: builds clean, `volec check` clean.
- `volec test main.vl`: 3 `#[test]`s (the nudge range, the defaults, the
  packing of the uniform block) pass at -O0 and -O2.
- Headless, default settings (1M agents, 1024 grid, 400 steps, through
  `gpu-run`): all checks ok; the total settles at 4.600e7, the closed-form
  balance 1e6 x 4 x 0.92 / 0.08. Agents stayed inside.
- Headless with other settings: 512 grid, 500k agents, the 22.5/45/18
  sensor set and the fire palette with speed 2.5 both render; 128 grid,
  200k agents, speed 4 and turn 90 (agents hit walls often) stay inside.
- Timing, through `gpu-run` on an idle machine: 0.53 ms a step with 1M
  agents on 1024 x 1024; 1.40 ms a step with 4M. These include the one
  final checkpoint, which waits for the GPU.
- The picture was read as PNG (`shot.png`, the default run); it shows the
  network of trails, as the model does.

Not verified: the windowed mode and the keys. A windowed run with
`--frames` never returned under `gpu-run` in this session (killed after
60 s); `examples/gpu/fluid2d` behaved the same way, so it is the
environment, not this program. The key handling, mouse and resize code
compiles but has not run.

## Files

- `main.vl`: options, the headless run and its checks, the window loop and
  the keys.
- `sim.vl`: the GPU side: buffers, pipelines, bind groups, the step, the
  picture, the readbacks for the checks.
- `shaders.vl`: the WGSL, one module per kernel (init, agents, diffuse,
  clear, render), sharing a common header with the uniform block.
- `tune.vl`: the parameters, `nudge` (clamped change), and `pack` (the
  uniform block layout).
- `shot.ppm`, `shot.png`: the default run's picture at 400 steps.
- `ANALYSIS.md`: how the work went and what was wrong with vole.
