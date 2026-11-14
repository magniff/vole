## (0.29) A file that is no vole source: a shader a block embeds, and a
## text file that is no file of the program (a README). show prints
## either whole; grep --in searches a shader as a file of the program
## (code or comment, by WGSL's rules) and a text file as text; a file
## given as a pattern is an error, not `0 hits` (tools/textfile.vl).
$ show textfile0290/shade.wgsl
// textfile0290/shade.wgsl:1-6
// The level of grey the fragment shader writes.
@fragment
fn fs() -> @location(0) vec4<f32> {
    let level = 0.5;
    return vec4<f32>(level, level, level, 1.0);
}
$ show textfile0290/README.md
// textfile0290/README.md:1-7
# shade

A program that embeds one shader, `shade.wgsl`, and prints the length
of its fragment entry's name. The level of grey is a constant of the
shader.

    volec check main.vl
$ grep level --in textfile0290/shade.wgsl
# textfile0290/shade.wgsl
1:8	comment	crate	// The level of grey the fragment shader writes.
4:9	code	crate	let level = 0.5;
5:22	code	crate	return vec4<f32>(level, level, level, 1.0);
5:29	code	crate	return vec4<f32>(level, level, level, 1.0);
5:36	code	crate	return vec4<f32>(level, level, level, 1.0);
$ grep level --in textfile0290/README.md
# textfile0290/README.md
4:35	text	-	of its fragment entry's name. The level of grey is a constant of the
$ grep Level --in textfile0290/README.md --ignore-case --count
1
$ grep nosuchtext --in textfile0290/README.md
note query.empty: 0 hits in textfile0290/README.md (a text file, searched as text)
$ grep level textfile0290/README.md
error query.not-in-program: textfile0290/README.md is a file, not a pattern, and it was not searched: --in FILE names the file to search
try: volec query grep level --in textfile0290/README.md
[exit 1]
$ grep level --in textfile0290/missing.md
error query.bad-in: no file, module or item 'textfile0290/missing.md' in the program
try: volec query grep level
[exit 1]
