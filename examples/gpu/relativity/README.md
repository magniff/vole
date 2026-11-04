# relativity

Walk through a small village at a speed of light you choose. A
logarithmic slider sets c as a multiple of walking speed, from 1.001x
(you walk at nearly the speed of light) to 10x (barely relativistic),
and the renderer turns your instantaneous velocity into the four
effects of special relativity: aberration, Doppler shift, relativistic
beaming and Lorentz contraction. Two clocks, yours (proper time) and the
village's, drift apart by gamma while you move; a row of pendulums
swinging in step shows retarded time, as their light reaches you at
different delays. Rendered on the GPU (`std::window` + `std::gpu`, Metal
on macOS).

```sh
target/volec -O2 examples/gpu/relativity/main.vl -o relativity
./relativity                                  # c = 1.5x walking speed
./relativity --mult 1.01                      # nearly at the speed of light
./relativity --headless --ui --out r.ppm      # no display needed: the self-check
```

There is one multiplier in the program: the slider, the presets, the
keyboard and the orbs all write it through `Lab::set_mult`. Walking is
by rapidity, so a step is always a walking pace in your own frame,
however close to c that is.

| input | action |
|---|---|
| `w` `a` `s` `d` | walk (shift: sprint) |
| drag | look around |
| arrow keys | nudge the slider (shift: faster) |
| `1`..`7` | the presets, 1.001x to 10x |
| `r` / `v` | reset everything / reset the view |
| tab | hide or show the panel |
| `f` | fullscreen |
| `q` / escape | quit |

The four effects can each be switched off in the panel, to see what
each one contributes.

`--headless` renders the same pipelines into a readback surface and
checks the frame: lit, detailed, changed by velocity, changed by the
slider, and (with `--ui`) changed by the panel. `--mult`, `--beta`,
`--pos`, `--yaw` and `--pitch` set the scene; `--size WxH`, `--ui-scale`
and `--out FILE.ppm` the image. `tests/examples/gpu-relativity.test`
runs it.
