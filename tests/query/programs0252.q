## (0.25.2.1) A directory of programs (`--in DIR`, `--root DIR`, one
## main.vl each below it): grep reads each of them, a shader's WGSL in a
## string too; a program's directory is its main.vl. Another query on
## such a directory names the programs.
$ grep workgroupBarrier --in progs0252
# progs0252/blur/main.vl
1:31	comment	main	// Another: its comment names workgroupBarrier, its code does not.
# progs0252/wave/main.vl
4:5	string	WAVE	workgroupBarrier();\n\
note query.programs: 2 hits in the 2 programs under progs0252 (each main.vl: its code, comments and strings)
$ grep workgroupBarrier --root progs0252 --strings
# progs0252/wave/main.vl
4:5	string	WAVE	workgroupBarrier();\n\
note query.programs: 1 hit in the 2 programs under progs0252 (each main.vl: its code, comments and strings)
$ grep workgroupBarrier --in progs0252/wave
# progs0252/wave/main.vl
4:5	string	WAVE	workgroupBarrier();\n\
$ show main --root progs0252
error query.bad-root: 'progs0252' is a directory of programs, not one: name one of them
try: volec query show main --root progs0252/blur/main.vl
try: volec query show main --root progs0252/wave/main.vl
[exit 2]
