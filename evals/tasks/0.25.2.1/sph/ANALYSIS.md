# sph: the agent's analysis

> Saved verbatim by the orchestrator from the agent's final message: the harness refused the agent's own write of this file (subagents may not write report files). Nothing is edited but this note and the headings' markup.

## 1. Result
Works. Headless run through gpu-run (120 frames, shot written):

    particles 102400, grid 134 x 94 cells of 0.015 m, padded to 12800
    sort at the start (counts, prefix sum, order vs CPU): 0 wrong
    prefix sum of 100003 counts vs CPU: 0 wrong
    67 substeps of 0.249 ms a frame
      frame 30: mean density 989.9 (-1.01% of rest)
      frame 60: mean density 1024.9 (2.49% of rest)
      frame 90: mean density 1029.7 (2.97% of rest)
      frame 120: mean density 1032.0 (3.20% of rest)
    120 frames: 39.00 ms a frame (67 substeps each)
    sort after the run (wrong entries): 0
    density settling: the last 30 frames moved it 0.227% of rest
    particles outside the box or not finite: 0
    checks: sort ok, prefix sum ok, escapes ok, density ok

Verified: sort and scan match the CPU exactly; the fluid settles; no escapes; shot.png (viewed) shows the tilted tank, pooled fluid, speed colouring and a free surface. window.png (viewed, 2560x1440) shows the untilted tank at rest.

Not verified: mouse stir and arrow-key tilt in a real window (the headless run scripts both; the window path reads the same Params). The windowed frame time is not a measurement: the display was occluded, so frames came from the 10 fps timer. Mean density sits about 3% above rest (weakly compressible, sound speed 15 m/s; the check tolerance is 5%). At 67 substeps a frame costs about 39 ms here, so the window runs below real time at 60 Hz; the substep cap defaults to 80.

## 2. How you worked
- volec guide (whole), guide gpu, guide window: read first (~3 calls). Read fluid2d main.vl and sim.vl in full as the model.
- volec query items/show (Named, Logical, Mouse, Color, PassDesc, monotonic_now, Color::rgba, std::window::keys): ~8 calls. Enough for signatures without reading std source.
- query-first hook blocked one sed over a compiler/std .vl (480 lines): one turn lost; the suggested query worked.
- volec check (after each Write via the hook): one useful auto-fix (let mut -> var). The first check listed 8 errors, fixed in one pass.
- volec test: 8 tests, passing after the fixes. Builds: about 6, each under 1 s.
- gpu-run: 4 runs (4-frame smoke, two 120-frame headless, one short windowed).
- Not used: query context, edit patch, refactor, query refs, probe. I wrote whole files with Write and fixed errors with perl/Edit. Faster for a fresh project; untested whether the edit tools save turns on later edits.
- agent-feedback: 3 lines recorded.

## 3. What went well
- Specific errors with fix lines ("'let mut' is Rust's spelling; a mutable binding is 'var x'"; "no associated function 'new' in 'Gpa' ... a #[test] fn takes the allocator as a parameter"; "a use names an item through a path"). The Gpa one saved a turn.
- Builds take 0.3 to 0.9 s.
- The GPU API works once you copy fluid2d's shape: one module per kernel, run(pass, pipe, group, groups) helper, many dispatches in one compute pass, map_read for readbacks.
- WGSL kernels worked first time, including a single-workgroup Hillis-Steele scan with barriers inside a uniform-bounded loop.
- volec test runs -O0 and -O2 and reports agreement.

## 4. What went badly
- Runtime crash, about 3 turns: "cpu.vl:121:32: index out of bounds: index 4294967295, length 12596". Cause: the sort check ran before any set_params, so the grid size in the uniform was zero and the cell ids were u32 of -1. The message points at my host line, not at the uniform never written. Logged with agent-feedback.
- First check: 8 errors at once, including "cannot deref non-pointer type 'u32'" for `for x in xs { *x }` (the loop variable is a value; the message does not say so), Gpa::new() in #[test] (correct help, but only after the first check), and `use cpu;` (parser error; cpu::x works without the import; the message does not say so). Logged.
- The query-first hook blocked a sed -n over a 480-line std .vl; the suggested query worked.
- "window: no frame in 3 s ... frames come 10 a second": a windowed timing check needs an awake, visible display; gpu-run cannot tell ahead of time.
- Retina units: win.size() is logical, surf.width physical (2560x1440 here). I used surf.width for view and mouse, following fluid2d; nothing says which units Mouse.x uses.
- WGSL reserved words: I avoided view, index, filter, target by habit, not from a list.
- GPU timing: wait_idle plus monotonic_now over N frames was the only method I found; no GPU timer query in the std API I could see.

## 5. The language
- Ownership did not bite: GPU handles (Device, Queue, Buffer, BindGroup, pipelines) are copyable values, passed by value as fluid2d does.
- map_read views must end before the next GPU use; I kept each read in a let inside a helper method and did not hit gpu.state.
- usize is i64; WGSL indices are u32; many `as` casts. Mixing i64 loop bounds with u32 ranges needs care.
- Constants with arithmetic (`pub const N: i64 = COLS * ROWS`, f64 consts) worked.
- Liked: Result with ? through `inst.adapter()?.device()?`; #[test] with gpa: Gpa and assert_eq on f64; f-strings in prints; fast builds.

## 6. Suggestions, ranked by time saved
1. Initialise uniform and storage buffers to an explicit value, or warn when a kernel runs before its uniform was written (cost 3 turns and a confusing message).
2. For `for x in xs`, say the variable is already a value and show the fix (`x`, not `*x`).
3. Give the Gpa::new hint outside #[test] too.
4. Say `use cpu;` is not needed: cpu::x is in scope.
5. A WGSL reserved-word list in volec guide gpu.
6. State the units of Mouse x/y and surf.width (logical or physical) in the window guide.
7. A GPU timestamp query in std::gpu, or a documented way to time GPU work without wait_idle.
8. Let query-first allow sed -n on a .vl range when asked (it blocked a 40-line read).

## Numbers
- Builds: about 6, under 1 s each. Failed: 1 check batch (8 errors, fixed in one pass), 1 runtime crash (3 turns to fix).
- Headless runs: 3. Windowed runs: 1.
- Frame at 67 substeps: about 39 ms (GPU, via gpu-run). Substep: about 0.58 ms.
- Sort and scan checks: 0 wrong, every run.

Stray files: sph/ has shot.png and window.png, plus the .volec folder that the compiler created. shot.ppm and window.ppm were removed.
