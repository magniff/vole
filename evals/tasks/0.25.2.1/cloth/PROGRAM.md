# cloth

Position-based dynamics for a cloth, on the GPU (std::gpu compute kernels in
WGSL), drawn lit and two-sided in a window (std::window).

A 64 x 64 grid of particles (`--n` sets the side), the two top corners
pinned. Stretch constraints (the 4 neighbours) and bend constraints (the 4
neighbours two cells away) are solved by Jacobi with averaging: each particle
reads its neighbours and writes its corrected position, weighted by the
constraints' stiffness, every iteration. Each frame is 4 substeps of predict
(gravity, wind, damping), 128 solver iterations (each followed by the sphere
and floor collision), then the normals, all computed on the GPU. The cloth
is drawn from the particle and normal buffers, so nothing is read back for
drawing.

## Files

- `main.vl`: the command line, the window loop, the headless checks, the solver test.
- `sim.vl`: the GPU side (buffers, kernels, pipelines, draw, snapshot).
- `shaders.vl`: the WGSL (predict, solve, collide, normals, cloth draw, sphere and floor draw).
- `cpu.vl`: the camera and its projection (the same one the shader makes), picking, the drag's
  point, the uniform packing, the sphere's motion, the start state, and the measurements.

## Build and run

    volec main.vl -o cloth
    ./cloth                                   # the window
    ./cloth --headless                        # the checks, 600 frames (10 s)
    ./cloth --headless --calm --shot a.ppm    # no wind; writes a PPM picture
    ./cloth --headless --calm --drag          # grabs one particle and pulls it
    ./cloth --solve-test                      # the solver alone: stretch error by iteration
    volec test main.vl                        # the CPU tests (7)
    ./cloth --frames 240 --shot w.ppm         # windowed, quits after 240 frames

Options: `--n N` (grid side, 8..256), `--steps N` (headless frames), `--still`
(the sphere does not sway), `--calm` (no wind), `--drag`, `--shot FILE.ppm`.

`python3 .../ppm2png.py a.ppm a.png` converts a picture.

## Controls (window)

- Left button on the cloth: grab the nearest particle and drag it (it moves on
  the plane through it that faces the camera). Left button elsewhere, or right
  button anywhere: orbit the camera.
- Scroll: zoom.
- Space: pause. R: reset. W: wind on or off. M: the sphere sways or stands still.
  Q or Escape: quit.

## What the checks show

Headless runs print, once a second: the stretch error (rms and max, relative to
the rest length), the fastest particle, kinetic and gravitational energy, the
count of non-finite values, the lowest particle above the floor and the nearest
particle to the sphere's surface. The checks:

- no NaN or infinity;
- no particle inside the floor or the sphere (after every frame);
- stretch within 5% rms and 50% at the largest (not under `--drag`);
- calm only: the kinetic energy settles to under 1% of its peak;
- `--drag`: the grabbed particle is exactly on the target (distance 0).

`--solve-test` starts a jittered grid (no gravity, no sphere) and reports the
stretch error after 0, 2, ..., 256 iterations: it must fall monotonically to a
tenth of its start (it falls from 0.164 to 0.0012).

## Verified

- `volec test main.vl`: 7 tests pass at -O0 and -O2 (camera centre, ray and pixel
  agree, drag point stays on its ray, push-out onto the sphere and the floor,
  the sphere's motion, the start grid's pins, picking the particle under the mouse).
- `--solve-test`: error falls 0.164 -> 0.0064 at 32 iterations -> 0.0021 at 128 -> 0.0012 at 256.
- Headless, 600 frames, wind on: no NaN, no penetration, stretch rms 1.67%, max 23%.
- Headless, 600 frames, calm: no NaN, no penetration, stretch rms 1.66%, max 21%,
  kinetic energy 9.8 at the end (0.08% of its 11572 peak). At the first impact the
  total energy is 5954 above its start (50% of it): the position-based solver adds
  energy at contacts; this is reported, not checked.
- Headless, drag: the grabbed particle is held exactly on its target; the cloth
  stretches a lot under the pull (rms 5.3%, max 136%), which is reported, not checked.
- Pictures: `shot_wind.png`, `shot_calm.png`, `shot_drag.png` (checked by eye: the
  cloth drapes over the sphere, the back side is blue, the floor is checked).
- The window: `./cloth --frames 120` runs and quits. The display was not shown
  during the run, so no frame time is measured here (see ANALYSIS.md).

## Limits

- Jacobi with averaging converges slowly: 128 iterations a substep is what keeps
  the stretch near 2%. A pull of half a metre stretches far more.
- The impact gain of the solver is not modelled away (no velocity-level correction).
- Cloth lying on the floor has a slightly jagged lower edge (contacts are projected, not friction).
- Self-collision is not modelled.
