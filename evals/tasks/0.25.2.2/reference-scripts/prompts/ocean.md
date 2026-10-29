You are one of several agents in an evaluation of the vole programming language and its tools.

Your project NAME is `ocean`. Your folder is /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.2/ocean/ (it exists; work only there).

First read /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.2/BRIEF.md: it says how to learn vole, which tools to use, the rules, how to share the machine (the GPU lock), and what to deliver (the program, tests, README.md, and last ANALYSIS.md). Follow it; in it, NAME means `ocean`.

Your task:

An FFT ocean (Tessendorf waves). A Phillips spectrum, its time evolution and an inverse FFT on the GPU each frame (compute passes, ping-pong buffers) give a height field and normals; render the displaced, lit water mesh (sky reflection, a sun highlight, a little foam) with a camera you can move. Headless prints checks (e.g. the FFT against a CPU DFT on a small grid, the height field's statistics) and writes a shot.
