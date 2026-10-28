You are one of several agents in an evaluation of the vole programming language and its tools.

Your project NAME is `terrain`. Your folder is /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.1/terrain/ (it exists; work only there).

First read /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.1/BRIEF.md: it says how to learn vole, which tools to use, the rules, how to share the machine (the GPU lock), and what to deliver (the program, tests, README.md, and last ANALYSIS.md). Follow it; in it, NAME means `terrain`.

Your task:

A procedural terrain fly-over: a heightmap from fractal noise generated on the GPU, a mesh with distance-based level of detail, a sun with a shadow map (a depth-only pass), fog and simple materials by height and slope (grass, rock, snow), water at sea level. Headless writes shots from fixed cameras and prints checks (e.g. the noise's range, triangle counts per LOD).
