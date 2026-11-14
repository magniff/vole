## The allocator rules' fixes on a rust program (0.28.0;
## tests/refactor/allocrust/). alloc.field's fix makes the struct generic
## over `A: Allocator`, and std's prelude has no Allocator: the fix
## carries `use std::alloc::Allocator;` (it was refused: "'Allocator' is
## not a trait in scope"). A function that names `gpa` without having
## one gets the edit that adds the parameter and passes it at each call
## as its try: line (one function up at a time).
$ check
main.vl:2:12: error[alloc.field] the struct 'Log' holds an allocator its parameters do not name: 'Gpa', in field 'lines' | help: a type that holds an allocator says so in its parameters: make it generic over it (`struct P<A: Allocator> { v: Vec<u8, A> }`, used as `P<Gpa>`) | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:6:49: error[type error] undefined variable 'gpa' | help: a 'gpa: Gpa' comes from 'fn main(gpa: Gpa)': add the parameter `gpa: Gpa` to 'split_path' and pass it down | try: volec refactor signature split_path --add 'gpa: Gpa = gpa' --fill-calls --no-check main.vl
[exit 1]
$ fix --only alloc
fixed 1 suggested fix	main.vl	+4 -2 lines
main.vl:8:49: error[type error] undefined variable 'gpa' | help: a 'gpa: Gpa' comes from 'fn main(gpa: Gpa)': add the parameter `gpa: Gpa` to 'split_path' and pass it down | try: volec refactor signature split_path --add 'gpa: Gpa = gpa' --fill-calls --no-check main.vl
note fix.left: 1 error left (above)
% cat main.vl
use std::alloc::Allocator;

struct Log<A: Allocator> {
    lines: Vec<String<A>, A>,
}

fn split_path(path: &str) -> Vec<&str, Gpa> {
    let mut parts: Vec<&str, Gpa> = Vec::new_in(gpa);
    for p in path.split('/') {
        parts.push(p);
    }
    parts
}

fn main(gpa: Gpa) {
    let log = Log { lines: Vec::new_in(gpa) };
    let parts = split_path("/users/ada");
    println("{} {parts:?}", log.lines.len());
}
$ check
main.vl:8:49: error[type error] undefined variable 'gpa' | help: a 'gpa: Gpa' comes from 'fn main(gpa: Gpa)': add the parameter `gpa: Gpa` to 'split_path' and pass it down | try: volec refactor signature split_path --add 'gpa: Gpa = gpa' --fill-calls --no-check main.vl
[exit 1]
$ refactor signature split_path --add 'gpa: Gpa = gpa' --fill-calls
added parameter gpa: Gpa to crate::split_path, 1 call	main.vl	+2 -2 lines
$ check
ok: 0 errors in main.vl (1 file, 0 shaders)
% volec main.vl -o prog && ./prog
0 ["", "users", "ada"]
ok: built prog
