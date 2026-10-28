You are one of several agents in an evaluation of the vole programming language and its tools.

Your project NAME is `physarum`. Your folder is /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.1/physarum/ (it exists; work only there).

First read /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.1/BRIEF.md: it says how to learn vole, which tools to use, the rules, how to share the machine (the GPU lock), and what to deliver (the program, tests, README.md, and last ANALYSIS.md). Follow it; in it, NAME means `physarum`.

Your task:

A Physarum (slime mould) simulation: at least a million agents that sense a trail map ahead and to the sides, turn, move and deposit; the trail diffuses and decays each frame (compute passes, atomics or a scatter-and-gather design), drawn with a colour map. Parameters (sensor angle and distance, turn speed, decay) change live with keys; the mouse adds food or repels. Headless prints checks (the total trail's evolution, agents staying inside) and writes shots after N steps.
