You are one of several agents in an evaluation of the vole programming language and its tools.

Your project NAME is `deferred`. Your folder is /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.2/deferred/ (it exists; work only there).

First read /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.2/BRIEF.md: it says how to learn vole, which tools to use, the rules, how to share the machine (the GPU lock), and what to deliver (the program, tests, README.md, and last ANALYSIS.md). Follow it; in it, NAME means `deferred`.

Your task:

A deferred renderer. A scene of simple meshes (generated: cubes, spheres, a floor), a G-buffer pass into several render targets (albedo, normal, depth), then a lighting pass with at least 256 moving coloured point lights (light culling in a compute pass: tiles or clusters), then tone mapping. Keys toggle the G-buffer views. Headless writes each G-buffer view and the final frame, and prints the frame time.
