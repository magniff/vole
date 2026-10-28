# ocean: the agent's analysis

> Saved verbatim by the orchestrator from the agent's final message: the harness refused the agent's own write of this file ("return findings as text"). Nothing is edited but this note and the headings' markup; section A (deliverables) is the message's first half, section B its analysis.

## A. Deliverables

- Program: main.vl (CLI, headless checks, windowed loop), ocean.vl (GPU side), shaders.vl (WGSL: init, evolve, fft, mesh, sky), cpu.vl (trig, sqrt, reference DFT, camera matrices, 4 tests). Builds with `volec main.vl -o ocean`.
- README.md in the folder (run, controls, what was verified).
- shot.png (the headless picture), shot.ppm.

Verified:
- `volec test main.vl`: 4 passed at -O0 and -O2.
- `gpu-run ./ocean --headless --shot shot.ppm`:
  - FFT vs f64 CPU DFT, 16x16 and 32x32, all 4 lanes: relative error 1.7e-7 and 2.3e-7.
  - 256x256 height: mean 1.1e-10, rms 0.4846 m, skew 0.023.
  - Parseval (mean h^2 vs sum |H_k(t)|^2 from CPU-recomputed spectrum): 1.000000.
  - Height at 16 cells vs CPU spectral sum: worst 2.1e-7 m. This covers evolve and both FFT passes.
- `gpu-run ./ocean --frames 120`: windowed, 8.48 ms/frame at 2560x1440, quits by itself.
- The picture (640x360) reads as a sky gradient with a sun, lit water with a glint, some foam. I read the PNG only.
- Not exercised: the interactive keys (WASD, arrows, space, R, Esc). The code is there, but I have not driven it.
- Not verified: a second device; the wind option is ignored in headless (hard-coded 10 m/s).

Design: h0 (Phillips with hash-RNG Gaussians) is generated once on the GPU by `init`. Each frame: `evolve` writes spectra; row then column inverse FFT, one 256-thread workgroup per line, radix-2 in workgroup memory, ping-pong a0/a1 and b0/b1; then the depth-tested mesh (256x256 vertices, 1 m apart), with a full-screen sky pass drawn first.

Compiler/tool contention did not block me. gpu-run waited 0 to 32 s (load 2.0-2.5).

## B. Analysis

### 1. Result

Works: the whole per-frame pipeline on the GPU (evolve, row and column IFFT with ping-pong, depth-tested mesh, sky). The checks in section A pass with real numbers. The window runs.
Unverified: interactive controls; a second device; headless ignores --wind.
Foam: a threshold on the Jacobian, no advection.

### 2. How I worked

- `volec guide` (full), `guide gpu`, `guide testing`, `guide --find` x3 (`ln` had no match). Read fluid2d's main.vl and sim.vl for patterns.
- `query items std::gpu`, `query show` (~6), `query text` (1), `query refs abs` (1; this exposed the truncation bug below), `query grep` (1, no hits).
- `volec check` through the hook after almost every edit: the most useful loop. 21 errors on the first full check.
- `volec fix --suggested`: twice by hand, and the hook ran it again on later edits. The second applied 17 fixes, including the harmful one in section 4.
- `volec try` (1), `volec test` (1), builds: 5 successful, no failed compiles. Two runtime failures (sky bind group; wrong amplitude).
- gpu-run: 5 runs. agent-feedback: 4 lines.
- Hooks blocked me 4 times: grep over examples/ (said query only), `sed -n` on a 467-line .vl in my own folder, `sed -i` on one constant, a python rewrite of main.vl. Fallback was Edit or heredoc.

### 3. What went well

- The WGSL was correct on the first run: the workgroup FFT, init, evolve, mesh, sky.
- The GPU API (buffer_init, bind_group, compute_pass, render_pass, with_depth, copy_texture_to_buffer) is pleasant. fluid2d was enough to model on.
- Test harness with `gpa: Gpa` and `assert` was quick.
- Most error messages were specific. The `expects 4 arguments, got 3 | help: its signature: ...` message made call-site fixes mechanical. `entries.len() = 1, layout.count = 3` was clear.

### 4. What went badly

- SILENT TRUNCATION (worst). `volec fix --suggested` rewrote float `x.abs()` to `std::abs(x as i64)`. std::abs is i64-only, so the checks compared truncated values. The FFT check printed `largest error 0.00e0 ... ok`, and Parseval printed FAILED at ratio 1.000000. Only `query refs abs` showed it. The tool's own re-check passed. Observed in main.vl; I did not separately test the minimal case.
- No float abs, sqrt, sin, cos, max, min, floor in std. I wrote a Taylor sin/cos, Newton sqrt and abs_f (~40 lines). The GPU side has them in WGSL.
- Bind groups are per module, not per entry point. My sky pass is a second entry in the mesh's module, so its bind group needed all 3 bindings: `gpu.layout: ... entries.len() = 1, layout.count = 3`. The message is right, but the docs should say the layout is per module.
- Amplitude: first AMP 0.0005 gave rms 15.3 m. One constant fixed it (rms scales with sqrt(AMP)); I found it only from headless output.
- Black sky above the horizon until I added a sky pass. The guide does not say how a pipeline's depth state must relate to its pass's depth attachment; I chose the states to match and did not hit an error, so this is not verified as a rule.
- About 21 first-check errors, all my own Rust-isms: `*v` deref of an iterator value, `.abs()`/`.max()`, `mods.ctrl` without `()`, slice vs array in a test, an unannotated f64 var mixed with f32, a test without `gpa: Gpa`.
- Hooks: 4 interruptions in about an hour; the fallback worked each time.

### 5. The language

Fought: no numeric methods, so my own abs/sqrt/sin; many `as` casts between the f32 GPU uniforms and f64 CPU code; `for v in slice` yields values, not references; closures passed to compute_pass/render_pass need the handles copied to locals first (fluid2d does this; the guide's closure section does not say so).
Liked: owned GPU objects in one struct with no lifetimes; bytes_of_f32 / f32s readback; `[0.0; N]` repeat literals and `[f32; 16]` returns; fast `volec check`.

### 6. Suggestions (by time saved)

1. Never let a suggested fix change a type (f64 -> i64 here). Re-check the rewritten expression's type against the original and refuse on a change.
2. Add float math to std (abs, sqrt, sin, cos, min, max, floor). Every numeric demo needs them.
3. Bind-group errors should name the module's bindings and the entry point ("layout is for the module; bind 0, 1, 2").
4. A headless-friendly assert_near(a, b, tol) that prints both values.
5. Hooks: allow a `sed -n` read of a project file of 300+ lines (the message offers query text, which is equivalent), and the single-constant `sed -i` case.
6. Document: layouts per module; pass and pipeline depth states must match (verify first).
7. A short "numerics in vole" page with abs/sqrt/sin for f32 and f64.

Tool feedback recorded (tools/agent-feedback): volec fix --suggested truncation; no float math in std; query-first hook blocks; bind-group layout per module.
