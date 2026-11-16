## XFAIL: RT-111: renaming a field refuses a program that binds it in a shorthand pattern (`let P { x } = p;`): rename and field --rename write `P { xx }` and their check refuses it (0.30.2)
## The local's rename writes a shorthand literal right (`P { x }` becomes
## `P { x: x9 }`); the field's rename does not do the pattern's form
## (`P { x }` must become `P { xx: x }`), and both `refactor rename P.x xx`
## and `refactor field P --rename x xx` end in edit.breaks with
## `no field 'x' in struct 'P'`, nothing written. 0.26.0 and 0.27.0 wrote the field and the literal and left the pattern, a program that does not check; refused since 0.28.0.
$ refactor rename P.x xx
renamed crate::P.x to xx	main.vl	+3 -3 lines
% grep -n 'xx' main.vl
2:    xx: i64,
6:    let p = P { xx: 5 };
7:    let P { xx: x } = p;
$ run
5
