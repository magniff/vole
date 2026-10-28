# ANALYSIS: ocean

## 1. Result

Works: an FFT ocean on the GPU. Per frame: a compute pass evolves the
Phillips spectrum in time (h, Dx, Dz), 14 Stockham radix-2 compute passes
(7 along rows, 7 along columns) ping-pong the three fields between two
buffers, and a render pass draws a 128 x 128-quad mesh (3 x 3 tiles) that
reads the height field in its vertex shader (displacement, normal,
Jacobian for foam) and shades in the fragment shader (Fresnel sky
reflection, sun glint, foam, distance fog). The camera orbits, moves and
zooms from keys and mouse. Build: `volec main.vl -o ocean` in the folder.

Verified (headless, `./ocean --headless --shot shot.ppm --bench`, run
through gpu-run; output as printed):

```
FFT vs DFT, 8 x 8 grid (forward, and inverse of it = 64 x input): largest error 1.97e-5: ok
height field at t = 3 s, 128 x 128 grid: GPU vs CPU sum at 8 points, largest error 2.81e-7 (of rms 0.433 m): ok
height statistics: mean 1.60e-10 m (zero by construction), rms 0.433 m, max |h| 2.002 m
Parseval: mean h^2 / sum |H|^2 = 1.000000 (1 exactly): ok
shot: 640 x 400 at t = 4 s, written to shot.ppm
128 x 128 grid: 0.14 ms a frame for the time evolution and the 2-D inverse FFT
```

- The FFT check is a real comparison: forward 2-D transform against the
  DFT by definition, and the inverse of the forward against 64 x input.
- The height check compares the GPU field with a CPU sum over all k at 8
  sample points, so it covers both the evolution formula and the FFT.
- Parseval checks that the transform keeps energy (exact identity).
- `volec test main.vl`: 5 passed at -O0 and -O2 (Phillips limits, wave-number
  folding, the Stockham index map as a permutation, RNG range, length).
- Windowed: `./ocean --frames 120` through gpu-run ran 120 frames and quit.
  The display was occluded, so frames came from the 10 fps timer; the
  9.8 fps printed is not a measure. The window was not looked at.
- The shot (shot.png) shows a lit sea with a sun glint on the left and the
  horizon fog. I read the image; the look is plausible, not a reference.

Not done or weak:
- Foam is nearly invisible. The Jacobian threshold had to be lowered from
  a version that put white blobs everywhere, and at the chosen choppiness
  (1.8) it still shows only faint highlights. I did not tune it further.
- Windowed controls (keys, mouse drag) were written but never exercised.
- The spectrum h0 is made once on the CPU (the brief said "each frame";
  the time evolution and the IFFT are per frame on the GPU).
- The bench figure (0.14 ms) is the CPU time around submission plus
  wait_idle for 60 simulate-only frames, not a GPU timestamp.

## 2. How you worked

Commands and their rough counts:
- `volec guide` (once), `volec guide gpu` (once, long; read the saved
  output in two parts), `volec guide window`, `volec guide math`.
- `volec query items std::gpu`, `query items std::gpu::RenderPass`,
  `query items std::window::keys`, `query show` on types (Buffer, Format,
  Named, Logical, Mouse, PassDesc), `query context` on fluid2d's
  `Sim::snapshot_in` and `Sim::measure`. About 12 queries. They were the
  best tool here: one `query items` answered the exact signature of
  `dispatch`, `draw`, `set_bind_group`, which the guide did not list.
- Reading fluid2d's main.vl (with the Read tool, which the hook allows)
  for the frame loop, the headless path and the PPM readback. This did
  more for me than the guide did.
- `volec check`: about 6 runs; the hook auto-fixed the Rust spellings
  (`&mut x`, `*x`) and the missing `&` on two calls. The hook's report
  was clear and I did not need to fix them by hand.
- `volec build` (`volec main.vl -o ocean`): about 10 builds, each under a
  few seconds. The 120 s timeout on one `volec check` (a tiny probe) came
  back in the background; I think machine load (load average 12 at that
  moment), but it did not recur.
- `volec test`: 1 run, all passed first time.
- `query-first` hook: it blocked my `sed -n` and `grep` on
  compiler/std/gpu/mod.vl (correctly, the message said so); I used
  `volec query text` and `query grep` instead. It did not block anything
  in my own folder.
- gpu-run: 7 runs. Waits were 0.0 s every time.
- Did not use: `volec edit`/`refactor` (the files were all new, whole-file
  writes were simpler), `volec fix --suggested` (the hook did the same),
  `volec probe`, `volec guide debug`, `ArtifactData`/`Artifact` tools.

Time sink: the shader pipeline failure. Roughly 4 build-and-run cycles
(renaming the entry point, changing workgroup_size to 2-D, reading
EVAL in isolation) plus a probe, before binding the shader to a `let`
fixed it. See section 4.

## 3. What went well

- The Stockham FFT: the index mapping `j = 2*tid - (tid & (ns-1))` and the
  twiddle `exp(-+2 pi i idx / (2 ns))` derived on paper for N = 4 were
  right first time; the GPU check confirmed it (2e-5 error).
- The `query items` output was precise: it gave the exact signatures
  (e.g. `dispatch(inout self, x, y = 1, z = 1)`), and `query context` on a
  fluid2d function gave me its source and its callees in one call.
- Errors from `volec check` were one line each, with the `try:` fix. The
  two `Result` type errors and the `inout` marker errors were trivial to fix.
- The `own.move_out` message ("cannot move 'dev' out of a reference:
  what it points to keeps its value", with the sink/let options) pointed
  to the right fix.
- `volec test` with `assert_eq` worked without ceremony.
- gpu-run: quick, and its wait line printed the load.

## 4. What went badly

1. **The shader pipeline failure (the real time sink).** In `Ocean::new_in`
   I wrote `dev.compute_pipeline(dev.shader_wgsl(EVAL)?, "evolve")?`. The
   runtime said:
   `ocean: gpu: the pipeline was rejected: no compute entry point 'evolve' in the shader`.
   The entry `fn evolve` is in the shader. I changed the name, then the
   workgroup size, then ran a probe with the shaders alone, which all
   compiled. The probe with the exact `Ocean::new_in` reproduced the error;
   binding the shader to a `let` first made the eval pipeline pass, and
   the same inline form for the stage shader then failed with
   `no compute entry point 'stage'`. Binding both to lets fixed it. My
   reading: an inline `shader_wgsl(X)?` as an argument does not give the
   pipeline the module it was built from. That is a compiler bug or a
   missing diagnostic; the message names an entry that exists and sends
   the reader to the WGSL, which is correct. Recorded with
   tools/agent-feedback.
   Minimal repro (in a scratch folder): `let p = dev.compute_pipeline(dev.shader_wgsl(SRC)?, "main")?;`
   versus `let s = dev.shader_wgsl(SRC)?; let p = dev.compute_pipeline(s, "main")?;`
   with a SRC that has `@compute fn main`. I did not reduce it further.
2. **Device ownership.** `Ocean::new_in(dev, queue, ...)` took the device by
   `sink` (I wanted the struct to own it). Then the window's surface needs the
   same device and I got `own.moved: 'dev' is used here after it moved`.
   A `Device` is not `Copy`. The guide does not say how one device is
   shared between an owner struct and a surface. The fix that worked is
   fluid2d's: the struct creates its own device and the window uses
   `o.dev` as a `let` argument (`inst.surface(o.dev, ...)`). I would have
   guessed a clone; there is none for Device (the error says so).
3. **Buffer moves in a loop.** Writing `let (src, dst) = if t % 2 == 0 { (a, b) } else { (b, a) };`
   inside the stage loop gave `own.moved: 'a' is used here after it may
   have moved at 220:70 (on some paths)`. The fix was to build the bind
   group in each branch with the buffers in a different order (the bind
   takes the buffer as a view, so this is fine); that was not obvious.
   The error message does not say that a loop reuses a moved value; the
   column numbers were hard to map.
4. **Probe check timeout.** One `volec check` on a 25-line probe ran past
   120 s and went to the background. Load was high (load average 12). I
   did not see the output until I reran it.
5. **My own mistake, not vole's:** `sed -i 's/.../' file` on macOS takes
   the script as the backup suffix; the error was `sed: 1: "ocean.vl ...": invalid command code o`.
   I should have used `sed -i ''`. (Recorded here so it is not blamed on
   the tools.)
6. **Compile-time things that cost turns but are fine as designed:**
   `&mut x` for an inout argument, `*x` for a field of an inout param
   (the hook fixed both); `Result` needed on any function that uses `?`
   (the error was clear but I had to change two returns).
7. **Keys.** `Logical::Char(c)` is a `u32`, so every key test is
   `c == 'w' as u32`. A `match` on a char literal, or `Logical::Char('w')`,
   would read better.
8. **Missing from the guide** (the GPU section is long and I read it in
   two parts): PassDesc/RenderDesc are in `query items`, not the guide;
   there is no example of a depth-tested full-screen-free mesh (the
   fluid2d example has none, and the depth-only example is a shadow map).
   I had to work out `RenderDesc::depth(format, compare, write)` and
   `PassDesc::color(...).with_depth(view)` from the signatures.
9. **WGSL.** No WGSL errors at all after the entry-name issue was gone;
   the rest of WGSL worked as in the usual spec (`select` not needed,
   `vec2<f32>(...)`, `smoothstep` with ordered edges, `reflect`, `cross`).
   I used `smoothstep(e0, e1)` with e0 < e1 on purpose after reading the
   WGSL rule that e0 >= e1 is undefined.

Numbers: about 10 builds, 6 `volec check` runs, 7 gpu-run runs (3 of them
failed at pipeline creation, 1 windowed, 3 with the checks), 1 probe
program (2 runs). Turns on the pipeline problem: roughly 4 build-run
cycles.

## 5. The language

What fought me:
- Ownership of device/buffers in structs (section 4, items 2 and 3). The
  rules are simple once seen, but the error messages do not always name
  the fix I needed (a struct that owns a Device must receive it by sink,
  and then the device cannot be shared).
- Explicit allocators: `Gpa` threaded through every function that makes a
  Vec or a string. Fine, but it adds a parameter to nearly everything
  (`spectrum_h0(n, ..., gpa)`), and I had to pass `gpa` into the check
  functions too.
- `Result` propagation: a function that has `?` must return a Result; a
  function that returns a tuple at the end must wrap it in Ok (I did this
  twice).
- `inout self` methods: receivers that change state need `var`; receivers
  that only read need `let`. The rule is clear; calling `o.simulate(&enc, t)`
  while `enc` is a local `var` was fine.
- Closures in `compute_pass(|pass| ...)`: they capture the handles that
  are locals; reading `self.field` inside them would have been an issue,
  so I copied the handles to locals first (I did not test whether that
  was necessary).

What I liked:
- `volec check` fixing my `&mut` and `*x` spellings on its own.
- The `own.moved` / `own.conflict` messages say which line moved it.
- `#[test]` with `assert_eq`, and `volec test` running -O0 and -O2.
- `volec query items` as a signature reference; `query context` as a
  source reader.
- The windowed and headless split in one file with `App::new_in` returning
  Err under no display (the fluid2d pattern) worked the same here.

## 6. Suggestions (ranked by time saved)

1. Fix or diagnose the inline `shader_wgsl(X)?` argument: a wrong pipeline
   should not be reported as "no entry point 'name'" when the entry exists.
   Cost me about four build-run cycles and a probe.
2. Document device/surface ownership in `guide gpu`: a struct holding a
   Device, and a window surface that needs the same device, with the
   fluid2d pattern (`o.dev` lent to `inst.surface`). Cost me two turns.
3. Make the loop-move error name the loop ("moved in the previous
   iteration of the `for` at L:C") rather than "may have moved on some
   paths", with the right column.
4. Add a short gpu "render with depth, a mesh from a storage buffer"
   example. Writing RenderDesc.depth and PassDesc.with_depth from the
   signatures took several queries.
5. A `Logical::Char` literal form (`'w'`) or a `Key::is_char('w')` helper.
   Each key check is `c == 'w' as u32`.
6. Keep `volec check` under the timeout when the machine is busy, or
   report progress; a 120 s silent check looks like a hang.
