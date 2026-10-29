# ANALYSIS: deferred

## 1. Result

Works headless and builds with `volec main.vl -o deferred`.

- Pipeline: G-buffer (albedo Rgba8Unorm, normal Rgba16Float, linear depth R32Float, plus a Depth32Float buffer), a compute light-culling pass (16 x 16 tiles, per-tile depth range and four side planes, up to 127 lights per tile), a lighting pass into an Rgba16Float HDR target, and a tone-mapping pass to the frame or to a G-buffer view.
- Verified: `volec test main.vl` passes 7 of 7 at -O0 and -O2. `./deferred --headless --frames 600` exits 0 and prints the frame time. `--views PREFIX` writes PREFIX-final, -albedo, -normal, -depth and -lights as PPM; I converted them to PNG with tools/ppm2png.py and read them. Albedo shows the boxes and checkered floor with flat colours; depth is correct (near dark, sky black); the lights view is the tile heat map, with sky tiles at 0 lights and the tiles around boxes high. The final frame shows coloured light pools on the floor and boxes.
- Frame times (960 x 600, through gpu-run, wall clock over N frames submitted back to back and ended with wait_idle):
  - 512 lights, 600 frames: 0.372 ms a frame (earlier 30-frame run: 0.463 ms)
  - 256 lights, 600 frames: 0.264 ms
  - 4096 lights, 600 frames: 1.215 ms
  I did not check these against a second timing method, so treat the sub-millisecond numbers with caution.
- Not verified: the windowed mode. The windowed run (`--frames 120`) printed "no frame in 3 s: the window is occluded or not shown", so its 101.64 ms a frame is the window timer, not GPU time. The keys (0 to 4, space, q) and the resize path are written but never exercised. I have not looked at the window.
- Known limits, also in README: 127 lights per tile, silently dropped beyond that; light count fixed at start; the spheres are small and mostly hidden behind boxes from the default camera.

## 2. How you worked

- Read the brief, then `volec guide` (the core), `volec guide gpu`, `volec guide gpu-render`, `volec guide window`, and the fluid2d, life and std::gpu sources to match conventions. About 6 guide/read calls before the first line of code.
- `volec query items std::gpu` helped most: one call gave every std::gpu signature with its `requires` contracts. `volec query show` failed on `std::gpu::PassDesc`-style names (not found, exit 1); I then used `items`.
- The query-first hook blocked one `grep` of compiler/std/window/mod.vl (a 339-line file). That cost one turn; the hook's suggested `volec query items std::window` worked.
- Checks: `volec check` after each file; errors came with help text and `try:` lines. I used `target/tools/volec fmt` when the hook asked for formatting. I did not use `query context`, `edit patch`, `refactor`, or `fix --suggested` (the hook's auto-fix did the unused-import edit).
- Builds: `volec main.vl -o deferred`, several builds (exact count not recorded). The build that ran under gpu-run was slowed by queueing, not by compile time.
- GPU runs: 3 gpu-run invocations. Waits for the lock were 191.6 s and 202.9 s (load about 2.7).

## 3. What went well

- The std::gpu API is coherent: `RenderDesc::new` plus `target` and `depth`, `PassDesc::color(a).with_color(b).with_depth(d)`, `bind_group` with `gpu::bind`/`bind_texture`, `render_pass` and `compute_pass` closures. The MRT and depth-only guides matched the code.
- The contract messages on `bind_group`, `set_pipeline` and `render_pass` name the mismatch precisely (for example, "the pipeline has 2 color targets and the pass 3").
- Shaders as WGSL strings compiled without any MSL work, and WGSL compute with workgroup atomics and `bitcast` ran on the first try after the layout.
- Tests that take `gpa: Gpa` and `--check-alloc` are a good design.

## 4. What went badly

Compile errors I hit, with counts:
- `type error: expected '[f32; 3]', got '[f64; 3]' | help: a float literal is f64`. Float literals default to f64 in `let` bindings; I annotated 3 lets. Easy to fix, but the arrays are inferred from literals, so every literal-only array needs an annotation.
- `own.move_out: cannot move 'dev' (Device) out of a reference ... Device has no .clone()`. The `Renderer { dev: dev }` literal inside `new_in` failed because the `dev` parameter was a let parameter. The fix is `dev: sink gpu::Device`, which the message suggests but does not tell me that `sink` at the call site also means the caller loses the handle. I had to route later uses through `r.dev`.
- `unknown module 'math'`. Sibling `.vl` files are not modules until `mod math;` is in the program. The help line says so; I had expected `mod` in main.vl to be enough for siblings, and it was only after the first errors.
- `undefined variable 'gpa'` in `#[test]` functions. The help line says to take `gpa: Gpa` as a parameter. Clear, and it fixed all 3 at once.
- `use.unused` warnings on `cross3`, `dot3`. Harmless; the hook's auto-fix took them out.
- `ProcessRequest` / `query show` on `std::gpu::PassDesc` exited 1 with "===== not found" and no help line, unlike the other errors.
- A hook error text in the Bash tool: "NOTHING on this line ran (11 commands)" blocked my whole multi-command line, including harmless ones, because one `grep` hit a compiler std file. I had to re-run the rest.
- A `sed -i` edit of my own `.vl` failed with `unterminated substitute pattern` (my quoting, not vole); the hook had already applied the import fix, so I did not retry.

Turns (estimates, not counted exactly): about 8 to a clean `volec check`, 3 more for the ownership and module errors, 0 test failures, no runtime debugging (the first headless run printed correct-looking output).

## 5. The language

- `sink` versus `let` on handle types (Device, Queue) is the sharpest edge: a struct that stores a device must take it as `sink`, and every caller then loses the value. It is the right rule (Device is not Copy), but the messages do not say that the caller's `dev` is then dead.
- Float literal defaulting to f64 surprised me in five places. In Rust, the same code would infer f32 from the use; here it errors.
- Arrays of literals: `[0.0; 4]` and `[a, b, c]` work; tuples work (`.0` and `.1`).
- `Vec<T>` defaults to Gpa, so `Vec<f32>` in a signature is short; `Vec::new_in(gpa)` is needed everywhere else. Good.
- Liked: closures in `render_pass(desc, |pass| ...)` read naturally; `for _ in 0..n` works; `if` as an expression works.

## 6. Suggestions, ranked by time saved

1. Infer float literal types from the use site, or at least warn with the exact annotation at the first use (saved me 5 edit rounds).
2. When `sink` is needed for a parameter stored in a struct, say which call site the caller's value is moved out of (saved about 2 turns).
3. Make `query show` on std::gpu::PassDesc (and similar) find the item, or give a help line like the other errors (saved one turn).
4. The query-first hook blocks a whole multi-command line for one blocked command; running the other commands and reporting the block would save reruns.
5. A small "GPU example skeleton" in the guide (window, surface, one G-buffer pass, one compute pass) would have saved most of the reading.
6. Expose the GPU time of a pass (timestamp query) in headless mode. Wall-clock over back-to-back frames is the only frame-time measure I have, and I did not trust it fully.
