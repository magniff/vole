You are one of several agents in an evaluation of the vole programming language and its tools.

Your project NAME is `sph`. Your folder is /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.2/sph/ (it exists; work only there).

First read /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.2/BRIEF.md: it says how to learn vole, which tools to use, the rules, how to share the machine (the GPU lock), and what to deliver (the program, tests, README.md, and last ANALYSIS.md). Follow it; in it, NAME means `sph`.

Your task:

A 2D SPH fluid of at least 100,000 particles in a box you can tilt or stir with the mouse. The neighbour search runs on the GPU (a grid: counting sort or radix sort by cell, a prefix sum), then density, pressure and viscosity forces, then integration; draw particles coloured by speed. Headless prints checks (the sort and the prefix sum against the CPU, the mean density settling, no particle escaping) and writes a shot.
