# ANALYSIS: deferred

## 1. Result

What works (all verified, see README.md):
- Build: `volec main.vl -o deferred` succeeds. `volec check` is clean. `volec test main.vl`: 3 passed at -O0 and -O2.
- Headless: `./deferred --headless --frames 300 --check --shot shots/shot.ppm` through gpu-run: `1.3489 ms a frame` at 1280x720, 512 lights, 41 objects. Output: `culling: 64779 pixels, 410988 lit-by pairs, 0 missed, most lights in a tile 126 (average 58), 0 tiles over 256`. Four PPMs are written (lit, albedo, normal, depth); I converted them with ppm2png and read them: the lit frame shows coloured light pools on a floor with cubes and spheres, the G-buffers agree with the scene.
- The culling check found a real bug in my first cull (a projected disc, not conservative off-axis): 9 missed pairs. After switching to projecting the sphere's view-space box (8 corners), 0 missed.

What does not work or is not verified:
- The windowed mode. `gpu-run --timeout 60 -- ./deferred --frames 120` was killed at 60 s; `--frames 3 --timeout 30` also did not return. No frame output was seen. I did not debug it further (the brief says move on). Keys (1/2/3/0, Escape) and resize are written but untested.
- Frame time is wall time per frame of the whole encode-and-submit loop with one wait at the end; no GPU timestamps (std::gpu has none that I found).

## 2. How you worked

- Reading: `volec guide` (full), `volec guide gpu` (full, about 700 lines of output, read in two parts), `volec query items/show std::gpu` (many calls, the API signatures were the most useful), `volec query items std::window`, `query show std::window::Event`, `query show std::window::keys::KeyCode`, `query text` on fluid2d's main.vl and shaders.vl for style. The `query context` and `guide --find` commands were not used.
- Writing: I wrote the WGSL as Vole string constants with `\n\` continuation (shaders.vl), and the Vole files with the Write-by-heredoc tool and then Edit. I did not use `volec edit patch` or `volec refactor`, because the files were new and the edits were small.
- Checks: `volec check` ran after each edit (hook). About 9 check errors in total: the test allocator (`Gpa::default`), the struct field move (`own.escape`, `own.move_out`), the `Device` clone, a missing helper name, an arity mismatch, and the cull bug (found by the runtime check, not by check).
- Builds: 3 `volec main.vl -o deferred` builds, 0 failed (the failures were all in `volec check`). The first headless run worked.
- gpu-run: 3 headless runs that finished, and 3 windowed runs that were killed by the timeout. The waits before the runs were 88.7 s, 77.6 s and 34.9 s (load 4-25), and 0 s for the others.
- The query-first hook blocked `grep -n` and `head -c` on .vl files under 300 lines, so I used the Read tool for reading source in the workspace and `volec query text` for the fluid2d files. It cost about four blocked commands.
- The hook `volec fix --suggested` (run automatically after edits) applied a made-up fix for an undefined variable `check`: `use std::gpu::wgsl::uniformity::check;`. I removed it by hand. It was a fix for a missing parameter that I was in the middle of adding.

## 3. What went well

- The WGSL side was smooth: `texture_2d<f32>` with `textureLoad`, `atomic<u32>` in storage with `atomicAdd`/`atomicStore`, `storageBarrier` + `workgroupBarrier`, `select`, `mat4x4` in a uniform, instance_index with first-instance draws, `u32` integer wrap all compiled on the first try through `std::gpu::wgsl`.
- The std::gpu API is clear and close to wgpu. Descriptors with builder methods (`RenderDesc::new(...).depth(...)`, `VertexLayout`), `bind_texture`, `copy_texture_to_buffer` with the 256-byte row rule, and `gpu::f32s`/`u32s` for readback all worked as the guide says.
- Contracts were useful: `gpu.usage` and `gpu.align` messages are specific. I did not hit a runtime contract failure.
- The effects/ownership checks caught real problems at compile time (`own.escape` for a returned RenderDesc holding a shader borrow; `own.move_out` for a let parameter stored in a struct).
- The `volec test` runner: `#[test] fn x(gpa: Gpa)` works, and the three tests passed at both opt levels on the first run.

## 4. What went badly

- Multiple render targets are missing. `PassDesc` has one color target (`pub struct PassDesc { pub color: ColorAttachment, pub depth: Option<DepthAttachment> }`, docs say "several color targets: 0.22.x"). A G-buffer with 3 targets is therefore 3 geometry passes over the same geometry, each with its own depth clear, which is 3x the vertex work and not what the task asked for. Repro: `RenderPass` has no way to set a second color attachment; `PassDesc::color(view)` is the only constructor.
- Misleading hint: `own.move_out: cannot move 'dev' (Device) out of a reference ... help: copy it ('.clone()')`. `Device` has no `clone` (`no method 'clone' on type 'Device'`). I had to restructure so the Renderer takes the Surface in `resize`. The hint pointed to a method that does not exist.
- Bogus auto-fix: the hook `volec fix --suggested` for `undefined variable 'check'` suggested `use std::gpu::wgsl::uniformity::check;`, a path that does not exist. A bad automatic fix in the hook is worse than none.
- `query-first` hook: it blocked `grep -n PATTERN file.vl` for a 260-line file (the message says a file under 300 is read whole freely, but grep is blocked), and blocked `head -c` on a 491-line file. The suggested replacement (`volec query grep ... --root FILE`) worked but cost a turn each time.
- No math in std: there is no `std::math` module (no sin, cos, sqrt, pi) on the CPU side. I needed an orbit animation and a camera; I moved the trig into WGSL and made the camera exact (rational basis), which is fine for a fixed camera but would be a problem for anything more. `query items std` lists no math module; the `std::num` items are bit-level only.
- Windowed mode: `./deferred --frames 3` under gpu-run did not return in 30 s. I did not find out whether it is my code (the event loop and `request_frame`, the same pattern as fluid2d) or the window on this machine. The harness notes say another agent saw the same. No diagnostics were printed by std.
- Headless frame timing: there is no GPU timestamp query in std::gpu (I looked in `query items std::gpu` and the guide): the only timing is wall time around submit + wait_idle, which includes CPU encoding. A timestamp API would be the first thing a renderer benchmark needs.
- std::gpu `Device` is not `Clone` and not `Copy`, so it has to be moved into the first owner (Renderer) and everything else reached through it. Passing `dev` to the surface before moving it was workable, but the clone hint above sent me in the wrong direction first.

## 5. The language

- Ownership: `let` for read-only borrows, `inout` for the mutated, and `sink` for ownership transfer were clear once I had read the guide. The main friction: a `let` parameter cannot be stored into a struct (`own.move_out`); a function that returns a descriptor holding a `let Shader` field cannot return it (`own.escape`). Both messages were accurate and the fixes (make the param `sink`, build the pipeline inside the function) were simple.
- Closures for passes: `enc.render_pass(desc, |pass| { ... })` worked well; capturing values through local `let` copies (`let upd = self.update;`) is needed because closures cannot borrow `self`. Good to know, but I had to find it by the error.
- Passing an `inout` closure parameter to a helper: `draw_scene(&pass, ...)`; this worked.
- Strings: multi-line WGSL as `"...\n\` continuation lines in a `const X: [u8]` was fine, but a shader error would show a line in the WGSL text, not in the file, and I did not test that path.
- Integer and float literals: `1.0e9` as f64 for `Color::rgba` and `f32` elsewhere was clear; `as f32` casts were needed everywhere, which is fine.
- I liked: `#[test] fn t(gpa: Gpa)`, `assert_eq`, `format_in(f"...")` for PPM headers, `gpu::f32s`/`u32s` for typed readback, `Buf::push_str`.

## 6. Suggestions, ranked by how much time each would have saved me

1. Multiple color targets in `PassDesc` (or `render_pass_mrt`): one pass for albedo + normal + position would have removed 2 of 3 geometry passes and the depth re-clears. Also the G-buffer in the task is exactly the case it exists for.
2. GPU timestamp queries (or at least a documented way to time a frame): the frame time I report is wall time with a CPU encode. A renderer demo cannot report GPU time without it.
3. A `std::math` module (sin, cos, sqrt, pi, a 4x4 matrix and lookAt) on the CPU side, the one in the queued plan. I spent turns deciding where the trig should go.
4. Fix the `own.move_out` hint for types without `clone` (say "move it into the callee with `sink`, or store it in a `sink` parameter").
5. Remove or verify auto-fixes that name paths that do not exist (`volec fix --suggested` for `undefined variable 'check'`); the fixer should only offer names that resolve.
6. `query-first` hook: allow `grep -n` on small files and say why it blocks; the current message suggests a query that needs `--root` I did not know about.
7. Windowed-mode diagnostics: when `app.wait()` does not return a Frame, say so (or document how to run a headless window test). I could not tell a hang in my code from the window server.
8. Numbers: 6 gpu-run headless runs, 0 failed builds, about 9 `volec check` errors across the session (3 turns on the `Device` move, 2 on arity, 1 on the cull that the runtime check found).
