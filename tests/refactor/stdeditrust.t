## (0.28) A std item named by an edit: std is one text, `<std>`, whether
## the compiler's or a repository's files joined, and no file of the
## program, so the edit is refused. (In a repository it ran itself again
## with --std-tree, and that run asked for another, without end.)
% printf 'pub fn trim(&self) -> &str {\n    self\n}\n' > new.txt
$ edit replace str::trim --dry-run < new.txt
error edit.not-source: str::trim is in <std>, not in a file of the program
[exit 1]
$ edit patch str::trim --old self --new this --dry-run
error edit.not-source: str::trim is in <std>, not in a file of the program
[exit 1]
