## (0.29) `edit patch FILE` on a file that is no vole source. A shader a
## block embeds (`embed wgsl K from "shade.wgsl"`) is a file of the
## program: the patch is checked, the check validating the shader, and
## refused with the shader's error when it breaks it. A text file git
## tracks that is no file of the program (a README, a script) is patched
## as text: the same exact-match rules, no check, and `volec undo` takes
## it back (tools/textfile.vl).
$ edit patch shade.wgsl --old 'let level = 0.5;' --new 'let level = 0.25;'
patched crate	shade.wgsl	+1 -1 lines
% cat shade.wgsl
// The level of grey the fragment shader writes.
@fragment
fn fs() -> @location(0) vec4<f32> {
    let level = 0.25;
    return vec4<f32>(level, level, level, 1.0);
}
## an edit that breaks the shader is refused, with its error
$ edit patch shade.wgsl --old 'let level = 0.25;' --new 'let level = 0.25 + nosuchname;'
shade.wgsl:4:24: error[wgsl.name] unknown name 'nosuchname'  [edited]
error edit.breaks: 1 new error; nothing written; the error: shade.wgsl:4:24: unknown name 'nosuchname'
try: volec edit patch shade.wgsl --old 'let level = 0.25;' --new 'let level = 0.25 + nosuchname;' --no-check
[exit 1]
% cat shade.wgsl
// The level of grey the fragment shader writes.
@fragment
fn fs() -> @location(0) vec4<f32> {
    let level = 0.25;
    return vec4<f32>(level, level, level, 1.0);
}
## the exact-match rules are the items': an OLD that occurs several times
$ edit patch shade.wgsl --old 'level, ' --new 'level * 2.0, '
error patch.ambiguous: OLD 1 occurs 3 times in crate, lines 5, 5, 5; give more of the text around it, or --nth N (--all: every one)
try: volec edit patch shade.wgsl --old 'return vec4<f32>(level, level, level, 1.0);' --new 'return vec4<f32>(level * 2.0, level, level, 1.0);'
try: volec edit patch shade.wgsl --old 'return vec4<f32>(level, level, level, 1.0);' --new 'return vec4<f32>(level, level * 2.0, level, 1.0);'
try: volec edit patch shade.wgsl --old 'return vec4<f32>(level, level, level, 1.0);' --new 'return vec4<f32>(level, level, level * 2.0, 1.0);'
[exit 1]
$ edit patch shade.wgsl --all --old 'level, ' --new 'level * 2.0, '
patched crate	shade.wgsl	+1 -1 lines
% git diff --stat
 shade.wgsl | 4 ++--
 1 file changed, 2 insertions(+), 2 deletions(-)
$ undo
undid patched crate	shade.wgsl	+1 -1 lines
$ undo
undid patched crate	shade.wgsl	+1 -1 lines
% git status --short
## a text file: exact match, no check
$ edit patch README.md --old 'one shader' --new 'a shader'
patched README.md	README.md	+1 -1 lines (a text file: not checked)
% head -3 README.md
# shade

A program that embeds a shader, `shade.wgsl`, and prints the length
$ undo
undid patched README.md
% git status --short
$ edit patch README.md --old 'two shaders' --new 'a shader'
error patch.no-match: OLD 1 is not in README.md as written (a text file: the match is exact, blanks and line breaks too)
try: volec query show README.md
[exit 1]
$ edit patch README.md --old 'shader' --new 'SHADER'
error patch.ambiguous: OLD 1 occurs 2 times in README.md, lines 3, 5; give more of the text around it, or --nth N (--all: every one)
[exit 1]
$ edit patch README.md --nth 2 --old 'shader' --new 'SHADER' --dry-run
would patch README.md	README.md	+1 -1 lines (a text file: not checked)
$ edit patch README.md --nth 9 --old 'shader' --new 'SHADER'
error patch.nth: OLD 1 occurs 2 times in README.md: no occurrence 9
[exit 1]
$ edit patch README.md --all --old 'shader' --new 'SHADER' --old '# shade' --new '# Shade'
patched README.md	README.md	+3 -3 lines (a text file: not checked)
% cat README.md
# Shade

A program that embeds one SHADER, `shade.wgsl`, and prints the length
of its fragment entry's name. The level of grey is a constant of the
SHADER.

    volec check main.vl
$ undo
undid patched README.md
$ edit patch run.sh --old './shade' --new './shade --verbose'
patched run.sh	run.sh	+1 -1 lines (a text file: not checked)
% cat run.sh
#!/bin/sh
# builds and runs the program
volec main.vl -o shade && ./shade --verbose
$ undo
undid patched run.sh
## only a file git tracks; a shader no program embeds is no program's file
% printf 'a note\n' > notes.txt
$ edit patch notes.txt --old 'a note' --new 'the note'
error edit.not-tracked: notes.txt is no file of the program and git does not track it: edit patch changes a program's files and the text files of the checkout
[exit 1]
% printf 'fn f() {}\n' > other.wgsl
$ edit patch other.wgsl --old 'fn f' --new 'fn g'
error query.no-match: no file 'other.wgsl' in the program main.vl: a shader is a file of the program that embeds it (--root DIR/main.vl)
try: volec query items
[exit 1]
% git status --short
?? notes.txt
?? other.wgsl
