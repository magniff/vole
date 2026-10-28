# Eval round 2: vole 0.25.2.1, the same ten GPU demos

**Date:** 2026-10-28, 22:26–23:03 CET.

**The setup:**
- **Same as round 1** ([../0.25.2/SUMMARY.md](../0.25.2/SUMMARY.md)): the same ten tasks and prompts, and the same brief with only the paths changed. Round 1's harness notes are folded into the brief, so every agent saw them.
- **Agents:** Claude Haiku 5.5 at medium effort, at most five at a time.
- **GPU:** one shared GPU behind [tools/gpu-run](tools/gpu-run).
- **Compiler:** vole 0.25.2.1, the release built from round 1's feedback ([its notes](https://github.com/magniff/vole/releases/tag/v0.25.2.1)).
- **Records:** each folder has the agent's [ANALYSIS.md](qwen35/ANALYSIS.md), a [REVIEW.md](qwen35/REVIEW.md) and a [README.md](qwen35/README.md) with the prompt, parameters and tool counts.
- **Reviews:** two Opus reviewers, working to [REVIEW-RUBRIC.md](REVIEW-RUBRIC.md) (round 1's, plus two questions: did the program use 0.25.2.1's new features, and a note on the known compiler bug below). They rebuilt every program and re-ran every check. The orchestrator re-ran qwen35's check itself: 72 of 72 tokens, at load 26.

## Results

| project | time | tokens | tool calls | result | code | honesty | round 1 (time, calls, grades) |
|---|---|---|---|---|---|---|---|
| [qwen35](qwen35/) | 24.1 min | 362k | 113 | A | B+ | A- | 38.8 min, 180, A/B/A- |
| [ocean](ocean/) | 11.8 min | 204k | 59 | A- | B+ | A | 10.7 min, 76, A-/B+/A- |
| [sph](sph/) | 9.7 min | 222k | 39 | A- | A- | A- | 12.4 min, 69, B/B+/B+ |
| [physarum](physarum/) | 7.6 min | 180k | 51 | A | B+ | A- | 9.4 min, 59, B/B+/B+ |
| [cloth](cloth/) | 12.3 min | 237k | 56 | A- | B+ | B+ | 16.2 min, 103, B/B/B- |
| [mandelbulb](mandelbulb/) | 5.9 min | 154k | 32 | A- | B+ | A | 7.7 min, 72, A-/B+/B+ |
| [deferred](deferred/) | 12.6 min | 205k | 50 | A | A- | A | 15.2 min, 75, B+/B+/B |
| [terrain](terrain/) | 12.5 min | 186k | 63 | B+ | B+ | A- | 18.2 min, 68, B/B/B+ |
| [sdftext](sdftext/) | 11.0 min | 227k | 52 | A | A- | A | 11.9 min, 69, B+/A-/B+ |
| [windtunnel](windtunnel/) | 13.8 min | 253k | 81 | A- | B+ | A- | 24.3 min, 88, B-/B+/A |

Tool calls are as the harness reports them; [TOOL-STATS.md](TOOL-STATS.md) has the per-tool counts from the transcripts.

**Against round 1:**

| measure | round 1 (0.25.2) | round 2 (0.25.2.1) |
|---|---|---|
| agent time, all ten | 165 min | 121 min (−26%) |
| tokens | 2.33 M | 2.23 M (−4%) |
| tool calls (transcripts) | 849 | 586 (−31%) |
| hook blocks | 53 | 5 |
| failed tool calls | 79 | 29 |
| wrong automatic fixes | in 4 of 10 runs | none reported or found |
| hand-written sin/cos/sqrt | in every program | in none (std's math everywhere; a few hand-rolled `clamp`) |
| windowed `--frames N` runs that returned | 5 of 10 | 10 of 10 (frames from the 10 Hz timer: the display was asleep) |
| results graded B or lower | 5 of 10 | 1 of 10 (terrain, B+) |
| results graded A or A- | 3 | 9 |

The grades come from different reviewer agents in the two rounds, so read them as rough. The measured rows above them carry more weight.

**Things only 0.25.2.1 made possible:**
- **deferred** writes its G-buffer in one MRT pass, where round 1 needed three.
- **terrain**'s shadow map is a depth-only pass, with no dummy colour target.
- **sdftext** and **terrain** read back with `map_read_copy_in`.
- **windtunnel** found vortex shedding at Strouhal 0.163 at Re 100 (published: about 0.164). Round 1's agent reported no shedding.

## What the agents said

**Still loved:**
- the check hook after every edit;
- its automatic fixes, now only the mechanical ones: `&mut x` to `&x`, a missing `&` for an inout argument, `let mut` to `var`. Each one reported was right. qwen35 got dozens.
- `volec test` comparing -O0 with -O2;
- `query items` and `query show` for std's signatures.

**No longer complained about:**
- the query-first hook: one block for four agents, none for the other six;
- the window hang;
- the missing float math;
- wrong automatic fixes.

**Still unused:** `edit`, `refactor`, `probe` and `query context`, for all practical purposes. Agents write whole files and use Python string replacement. Every program here was new code, so these tools had little to do; a maintenance task would test them.

## Bugs found

- **Soundness:** `dev.compute_pipeline(dev.shader_wgsl(SRC)?, "e")?` reaches the pipeline with a shader that has no entry points, at -O0 and -O2. Binding the shader to a `let` first works. It belongs to the `f(make()?)?` family that 0.25.2.1 fixed, in a form the fix and its 4,340-case sweep missed.
  - Found by ocean (about 4 build-run cycles) and terrain (about 15 turns, the costliest single problem of the round).
  - Reproduced by the orchestrator. A CPU-only program of the same shape passes, so something about `Shader` or `Device` matters.
  - Being fixed for 0.25.2.2.
- **std::gpu:** `Format::is_storable` says `Rgba16Float` is storable, but the WGSL translator refuses it (deferred).
- **A uniform read before it was ever written is silently zero.** sph lost about 3 turns to it this round. windtunnel lost about 10 turns and never found the cause, which the reviewer did. physarum lost turns to it in round 1. 0.25.2.2 makes std::gpu report it.
- **Misleading help:**
  - `own.move_out` suggests `std::take(&self.field)` for a GPU handle chosen by `if`, which would empty the field (physarum, windtunnel: about 9 turns);
  - a `std::` path to a prelude name suggests a wrong near name: `std::num::parse_int` gets "did you mean `parse_f64`" (cloth, sdftext), and mandelbulb hit the same with `std::fmt::format_in` and `std::heap_gpa`.
- **Tools:** `query show`'s `try:` lines pointed into round 1's folders, which are other programs (physarum, cloth). `query show std::window::Surface::frame` found nothing.

## What the reviews add

- **Checks improved but some still can't fail.** cloth rewrote its energy check after it failed honestly, physarum caught a hash bug by looking at its picture, and sdftext's checks are all real. But several remain true by construction:
  - physarum's agents-inside and sph's escape check, because the kernels clamp;
  - cloth's drag and penetration checks;
  - terrain's noise range, which is clamped;
  - deferred's colour range.
- **std goes unfound.** Agents still hand-roll things std has:
  - `clamp` and `is_finite`;
  - UTF-8 decoding, an RNG, and a string map instead of `HashMap`;
  - `map_read_copy_in`: cloth rewrote it even after looking it up.
- **Borrowing:** fluid2d's `kernel`, `run` and `snapshot_in` were copied nearly verbatim into most programs. Two agents called them their own.
- **A real bug the agent missed:** qwen35's window samples greedily although its README says temperature 0.7, because std::cli's default makes its fallback dead code.

## Into 0.25.2.2

- the soundness fix;
- `gpu.unwritten` for a uniform buffer never written;
- `is_storable` and the translator made to agree;
- `gpu.layout` naming the entry point that brought in each binding;
- `gpu.limits` in the names a user writes;
- the buffer-size default;
- ten diagnostics from the list above;
- tool fixes:
  - `query show` across programs;
  - one summary line for repeated hook fixes;
  - the hook saying what it rewrote;
  - a ready-to-rerun command after a blocked compound line;
  - bounded line-range reads;
- guide additions: a textured quad, HiDPI units, integer math, atomics, buffer limits, one compute pass for many dispatches.

Round 3 runs the same ten tasks on 0.25.2.2.
