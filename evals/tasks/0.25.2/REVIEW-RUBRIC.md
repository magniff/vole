# Review rubric (eval 0.25.2)

For each project folder evals/tasks/0.25.2/NAME/ (the agent's prompt is .claude/briefs/eval-0252/prompts/NAME.md; the shared brief evals/tasks/0.25.2/BRIEF.md; its own report ANALYSIS.md and its README.md):

1. Reproduce: rebuild with `/Users/magniff/workspace/tachyon/target/volec main.vl -o /tmp-or-scratch/NAME` (vole 0.25.2; never write into the project folder), run `volec test main.vl`, and run its headless checks exactly as its README/ANALYSIS say, through `/Users/magniff/workspace/tachyon/evals/tasks/0.25.2/tools/gpu-run --timeout 120 -- ...`. Don't open windows. Record the commands and the key output lines.
2. Claims vs reality: does every claim in ANALYSIS.md hold (numbers, "PASS", what is verified)? Note overstatements and understatements.
3. Task coverage: each requirement of the prompt: done / partial / missing, one line each.
4. Correctness of the core: read the GPU kernels (WGSL) and the CPU side: algorithms right (cite the line for a bug), synchronisation, buffer usages, numerical choices; do the checks actually test what they say (or are they weak/tautological)?
5. Code quality: structure and module split, naming, idiomatic vole (ownership conventions let/inout/sink, Result/? use, allocator passing), duplication, dead code, comments; any `unsafe` (should be none; if present: justified?); hand-rolled math (expected: std had none in 0.25.2).
6. Borrowing: how much came from examples/gpu/* (fluid2d etc.): adapted patterns (fine) vs copied blocks (say which).
7. Tests: what the #[test]s and the headless checks cover; what they miss.
8. Verdict: one paragraph, plus a grade A–F for (i) result, (ii) code, (iii) honesty of the report.
Be specific (file:line), concise (400–700 words per project), and fair: these are first programs in an unfamiliar language written in 8–40 minutes.
