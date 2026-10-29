# Review rubric (eval 0.25.2.2, round 3)

For each project folder evals/tasks/0.25.2.2/NAME/ (the agent's prompt is .claude/briefs/eval-02522/prompts/NAME.md; the shared brief evals/tasks/0.25.2.2/BRIEF.md; its own report ANALYSIS.md and its README.md):

1. Reproduce: rebuild with `/Users/magniff/workspace/tachyon/target/volec main.vl -o /tmp-or-scratch/NAME` (vole 0.25.2.2; never write into the project folder), run `volec test main.vl`, and run its headless checks exactly as its README/ANALYSIS say, through `/Users/magniff/workspace/tachyon/evals/tasks/0.25.2.2/tools/gpu-run --timeout 120 -- ...`. Don't open windows. Record the commands and the key output lines.
2. Claims vs reality: does every claim in ANALYSIS.md hold (numbers, "PASS", what is verified)? Note overstatements and understatements.
3. Task coverage: each requirement of the prompt: done / partial / missing, one line each.
4. Correctness of the core: read the GPU kernels (WGSL) and the CPU side: algorithms right (cite the line for a bug), synchronisation, buffer usages, numerical choices; do the checks actually test what they say (or are they weak/tautological)?
5. Code quality: structure and module split, naming, idiomatic vole (ownership conventions let/inout/sink, Result/? use, allocator passing), duplication, dead code, comments; any `unsafe` (should be none; if present: justified?); hand-rolled math (std has float math since 0.25.2.1: Float methods, std::math; hand-written sin/sqrt is now a finding).
6. Borrowing: how much came from examples/gpu/* (fluid2d etc.): adapted patterns (fine) vs copied blocks (say which).
6b. New in 0.25.2.2: did the program use what fits its task: one WGSL module serving several pipelines (a pipeline's layout is now the bindings its own entry points use), the Rgba16Float/Rgba8Uint/Rg32Float storage formats, integer methods (`abs`, `min`, `max`, `clamp`, `pow` on integers), `adapter.limits()`; and did `gpu.unwritten` (a uniform buffer read before it was written now stops the submit) fire or shape the code? Say where, or where it worked around them.
6c. A known std::gpu soundness bug in 0.25.2.2, found this round: a `map_read` view (`let v = gpu::f32s(buf.map_read(dev))`) kept alive while a later submit writes the same buffer (a copy into it, or a shader writing it through a bind group) changes under the program, and nothing refuses it. Check whether the program keeps a mapped view alive across a submit that writes that buffer; if so, say where and whether its results depend on it. Don't count it against the agent beyond its effect on correctness.
7. Tests: what the #[test]s and the headless checks cover; what they miss.
8. Verdict: one paragraph, plus a grade A–F for (i) result, (ii) code, (iii) honesty of the report.
Be specific (file:line), concise (400–700 words per project), and fair: these are first programs in an unfamiliar language written in 6–29 minutes.
