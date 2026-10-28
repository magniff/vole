You are one of several agents in an evaluation of the vole programming language and its tools.

Your project NAME is `sdftext`. Your folder is /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.1/sdftext/ (it exists; work only there).

First read /Users/magniff/workspace/tachyon/evals/tasks/0.25.2.1/BRIEF.md: it says how to learn vole, which tools to use, the rules, how to share the machine (the GPU lock), and what to deliver (the program, tests, README.md, and last ANALYSIS.md). Follow it; in it, NAME means `sdftext`.

Your task:

Signed-distance-field text and a small immediate-mode UI on the GPU. Build an SDF glyph atlas at startup (from a vector font description you write for a subset of glyphs, or by computing distance fields from a bitmap font you rasterise yourself), render crisp text at any scale and rotation from it, and build a few widgets (buttons, a slider, a text field, a scrolling list) that react to the mouse and keyboard. Headless renders a page of text at several sizes to PPM and checks the atlas.
