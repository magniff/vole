# cloth: the agent's analysis

> Saved verbatim by the orchestrator from the agent's final message: the harness refused the agent's own write of this file (subagents may not write report files). Nothing is edited but this note and the headings' markup.

## 1. Result

Works: a 64 x 64 position-based cloth on the GPU, two top corners pinned. Stretch and bend constraints are solved by Jacobi with averaging (4 substeps, 128 iterations per substep, each followed by sphere and floor collision). Also: gravity, a time-varying wind, a moving sphere, the floor, grab-and-drag, normals computed on the GPU, two-sided lighting. Headless mode prints the numbers, runs the checks and writes a PPM.

Verified (run from the cloth folder):
- `volec main.vl -o cloth` builds. `volec test main.vl`: 7 tests pass at -O0 and -O2.
- `../tools/gpu-run --timeout 100 -- ./cloth --solve-test`: stretch error falls monotonically, 0.164 (start) -> 0.0064 (32 iterations) -> 0.0021 (128) -> 0.0012 (256). Exit 0.
- `./cloth --headless` (wind on, 600 frames): no NaN, no particle through the floor or sphere, stretch rms 1.67%, max 23%. Exit 0.
- `./cloth --headless --calm`: same, and the kinetic energy settles to 0.08% of its peak. Exit 0.
- `./cloth --headless --calm --drag`: the grabbed particle is exactly on its target (worst distance 0.00e0 m). The cloth stretches a lot under the pull (rms 5.3%, max 136%); this is reported, not checked. Exit 0.
- Pictures shot_wind.png, shot_calm.png and shot_drag.png were looked at: the cloth drapes over the sphere, the front is orange and the back blue, the floor is checked, and the grabbed corner folds out toward the viewer.

Not verified:
- The windowed mode. `./cloth --frames 120` runs and exits, but the display was not shown ("no frame in 3 s: the window is occluded"). The printed 101 ms per frame is the window's 10 fps timer, not a GPU frame time. I did not drive the mouse or keys. The orbit and grab-from-mouse paths run only in windowed mode and are checked only by compiling; the drag itself is tested headless through the same kinematic path.
- Frame time in general: no trustworthy number. The 600-frame headless run (about 530 dispatches a frame) took 1.2 s wall time including 10 readbacks and process start, so the GPU cost is under about 2 ms a frame.

Known limits: the solver's stretch under a large pull is poor (Jacobi converges slowly). The cloth gains energy at contacts (section 4). The lower edge jitters where the cloth lies on the floor (no friction). No self-collision.

## 2. How you worked

About 75 tool calls in total; counts are my approximate tally.
- `volec guide` (overview), `guide gpu`, `guide window`, `guide testing`: 4 calls, all useful. The GPU guide is 39 KB, so its output was saved to a file and I read the parts I needed with sed.
- Reading examples: examples/gpu/fluid2d main.vl and sim.vl with `sed -n` (about 1000 lines). The most useful thing I did. I used `volec query show` on it (about 6 calls) rather than `query context`.
- `volec query show` on std items (PassDesc::color, RenderDesc::depth, Compare, Color, bytes_of_f32, f32s, map_read_copy_in, window Mouse/Event/Scroll/Named): one call each, each gave the answer. `volec query items std::window` helped for the list of names.
- One failed query: `volec query show sim.vl::Sim::snapshot_in` said "no definition" and suggested `--root evals/tasks/0.25.2/...`, a folder that does not exist here (see 4). `volec query show Sim::snapshot_in --root examples/gpu/fluid2d/main.vl` worked.
- `volec check` and the check hook: the hook printed errors after each write, which was useful (the two type errors appeared at once). `volec main.vl -o cloth` built in 0.9 s.
- `volec test main.vl`: 4 runs. The tests were written in one go and passed on the first run after the test-only fixes.
- `volec fmt`: I did not know about it until `volec fmt --check` reported unformatted files (4 runs in total, main.vl +22/-12 lines). The check hook does not format.
- `tools/agent-feedback`: 3 lines recorded.
- `gpu-run`: about 15 runs, waits 0.0-3.7 s, load 2.0-3.0. No contention blocked me.
- I did not use `volec edit`, `volec fix`, `volec refactor` or `volec probe`. I edited with python (string replace, asserting the match count) and `sed -i` for single constants. I did not need probe: every bug was visible in the output.
- The query-first hook never blocked me (I read .vl files with sed, and wrote mine with python).

## 3. What went well

- The example (fluid2d) gave the whole pattern: device, buffers, bind groups per kernel, one encoder per frame, a compute pass with a run() helper, a render pass, snapshot to PPM. I copied the shape, not the code.
- The WGSL front end accepted the whole shader set on the first build (about 230 lines of WGSL in 7 modules): `for` loops with `var`, branches, swizzles, struct constructors, `vec3<f32>(0.0, 0.0, 0.0)`.
- `Result` plus `?` on device creation and shader compilation kept the failure paths short.
- `volec test` (-O0 and -O2 compared), `assert`, `assert_eq`, and the `gpa` parameter for a test that allocates all worked as written.
- The error positions were precise.
- The gpu-run lock: waits were short.
- The CPU mirror of the shader's projection (View::pixel, View::ray) matched on the first test run ("ray and pixel agree"), so the grab ray and the shader projection agree.

## 4. What went badly

Build and check errors (2 failed builds, one turn each to fix):
- `error[type error] no 'parse_int' in module 'std::num' | help: did you mean 'parse_f64'?` I wrote `std::num::parse_int`. parse_int is a prelude item (the guide lists it); the help suggested parse_f64, which is wrong for an integer, and the prelude is not mentioned.
- `error[type error] unknown type 'BufferUsage'` for a parameter `extra: gpu::BufferUsage`. The usage values are u32 (`BufferUsage::STORAGE | ...`). The error does not say that BufferUsage is a namespace of constants. I changed the parameter to u32. The guide says "`BufferUsage::`, or them together" but never says the type is u32.

Tool problems:
- `volec query show sim.vl::Sim::snapshot_in`: "no definition", and the three `try:` lines name `evals/tasks/0.25.2/<name>/main.vl`, the previous version's folder, not 0.25.2.1.
- `volec fmt --check` reported my .vl files unformatted after I had written them while the check hook passed. The check hook does not format. `fmt` appears only in `volec fmt --help`, which I found by looking.
- The harness reported "changed on disk since you last read it" for cpu.vl, sim.vl, main.vl and shaders.vl after volec runs. I did not change them by hand at those moments and could not tell what changed; the formatter is the likely cause.
- For a file's own top-level items I found no one-call way to read a 250-line file with its line numbers; `sed -n` was simpler.

Vole-specific:
- Passing a field as inout (`floats_in(self.dev, &self.pos0, gpa)`) and calling map_read on it compiled without complaint. I did not learn whether it was really a mutable borrow. No problem so far.
- I wrote `pub const WIND_DIR: V3 = V3 {...}` and replaced it with a function before compiling, expecting it to be refused. No information from the compiler either way.
- The stretch and energy checks needed several rounds (section 4.2 to 4.4). These were properties of the physics, not language problems.

Numerical and design time sinks, the largest part of the job:
1. Normals pointed away from the camera, so the whole cloth showed the back colour. I found it from the picture, not a check. Fix: `cross(tx, ty)` became `cross(ty, tx)`. One turn. A headless check that the front side faces the camera would have caught it earlier.
2. Stretch: 12 solver iterations gave rms 9%, max 149% under gravity. 32 gave 4.4% / 67%, 64 gave 2.6% / 37%, 128 gave 1.7% / 21%. Four runs. The solver test shows why: Jacobi with averaging needs on the order of 100 iterations to bring a 64-cell chain to about 1%. Over-relaxation (omega > 1) is unstable for this averaging Jacobi (the high-frequency modes reach magnitude 2 in its iteration matrix), so I did not try it. Chebyshev acceleration would need a three-buffer rotation with per-iteration weights; I did not attempt it. Cost stayed small, so 128 iterations was kept.
3. Energy: the first version checked "energy never above its start". It failed at the first impact: total energy +50% of the start's potential, kinetic energy about twice the free-fall value. This is the PBD solver adding energy at contacts (corrections move particles, and velocity is taken from positions). The check now asks that the kinetic energy settles to under 1% of its peak. The impact gain is printed, not hidden.
4. The t=0 reading showed sphere clearance -0.43: the flat cloth starts through the sphere's centre, since the sphere sits in the cloth's plane z=0. This is the initial state, not a solver bug. The penetration check now starts after the first frame.
5. The grab check passed at distance 0 at once (the particle is held in the collide kernel). Simple and it works.

Other reading and writing costs:
- The first read of fluid2d's sim took a few lines to get used to `inout self` and `&pass`. The closure style `enc.compute_pass(|pass| { run(&pass, ...) })` is clear once seen.
- The guide gpu examples are small and compiled; the big ones (life, fluid2d) are in the example folders. The guide does not show a mouse grab or a windowed loop with inout locals. I read guide window and the fluid2d loop instead.

## 5. The language

What fought me:
- Constants versus types (BufferUsage) and the prelude versus std:: split (parse_int).
- usize is i64 (the guide says so); I used i64 throughout. No friction.
- For the compute pass I copied each pipeline and bind group into a local before the closure (`let kp = self.k_predict;`), following fluid2d. I did not verify whether this is required; it is what the example does.
- `if` as an expression inside an f-string worked. f-string specs (`{s.err_rms:9.4}`, `{x:.2e}`) worked as in Rust.
- Tuples (`let (sx, sy, depth) = v.pixel(p)`) worked. Methods on `self` by value read the struct without moving it, which made the camera and view code short.
- Matching `Logical::Char(ch)` and comparing with `' ' as u32` is awkward, as in fluid2d, but fine.

What I liked:
- WGSL in string constants with `\n\` line continuation: all shaders stayed in the source, the translator reported line numbers, and there was no C helper.
- `volec test` runs -O0 and -O2 and compares them.
- `shader_wgsl` reports errors with WGSL positions.
- The check hook after each edit gave quick feedback.

## 6. Suggestions, ranked by time saved

1. State the type of the usage constants (BufferUsage is a u32 namespace). It cost a turn and a guess.
2. Fix the `try:` path in `query show FILE::item` (it names 0.25.2, not the current version).
3. Make the check hook run fmt on the files it checks, or say so; I found the formatting only by running `fmt --check`.
4. A prelude-aware "did you mean" for `std::num::parse_int` (the help named parse_f64).
5. A GPU guide note on Jacobi-with-averaging convergence and iteration counts, since solver stretch quality is the first thing a cloth author meets.
6. A checked property or helper for "front faces the camera" on generated normals, or a one-line probe that reads one value from a buffer.
7. Document how a closure captures self fields (by value or by reference) in the guide, next to compute_pass.

Numbers: failed builds 2 (one turn each); check errors 2 (both fixed in the next turn); test runs 4; GPU runs about 15 (wait 0-3.7 s); physics tuning runs 4 (iterations) plus 2 check rewrites; files formatted 3 (fmt).

Feedback recorded with tools/agent-feedback: parse_int help, query show's stale 0.25.2 path, BufferUsage type error.
