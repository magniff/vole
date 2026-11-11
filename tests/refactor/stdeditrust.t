## (0.28) A std item named by an edit of a rust program, in a repository
## that has std's files: the program's std is std2, one built-in text that
## the files do not stand in for, so the edit is refused as outside the
## repository. (It ran itself again with --std-tree, and that run asked
## for another, without end.)
% mkdir -p compiler/std && touch compiler/std/std.vl compiler/std/embed.sh
% printf 'pub fn trim(&self) -> &str {\n    self\n}\n' > new.txt
$ edit replace str::trim --dry-run < new.txt
error edit.not-source: str::trim is in <std>, not in a file of the program
[exit 1]
$ edit patch str::trim --old self --new this --dry-run
error edit.not-source: str::trim is in <std>, not in a file of the program
[exit 1]
