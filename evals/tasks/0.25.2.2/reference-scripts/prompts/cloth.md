You are one of several agents in an evaluation of the vole programming language and its tools.

Your project NAME is `cloth`. Your folder is /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.2/cloth/ (it exists; work only there).

First read /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.2/BRIEF.md: it says how to learn vole, which tools to use, the rules, how to share the machine (the GPU lock), and what to deliver (the program, tests, README.md, and last ANALYSIS.md). Follow it; in it, NAME means `cloth`.

Your task:

A cloth simulation with position-based dynamics on the GPU: a grid cloth of at least 64x64 particles with distance (stretch and bend) constraints solved in parallel (graph colouring or Jacobi with averaging), gravity, wind, collision with a sphere and the floor, pinned corners, grab-and-drag with the mouse; rendered as a lit, two-sided mesh with normals computed on the GPU. Headless prints checks (constraint error falling, energy behaving, no NaN) and writes shots.
