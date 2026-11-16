## XFAIL: RT-M2-11: refactor field --rename (and rename STRUCT.field) leaves the field's old name in patterns (open)
## A field renamed is renamed in its struct, its literals and its
## accesses, but not in a pattern (`Pt { x: 0, .. }`, `Pt { x, y }`,
## `Pt { x: 1, y: yy }`): the check then refuses the edit (3 new errors,
## `no field 'x' in struct 'Pt'`) and `--no-check` writes them. The
## patterns' fields are renamed too, a shorthand `x` becoming `xx: x`.
$ check
ok: 0 errors in main.vl (1 file, 0 shaders)
$ refactor field Pt --rename x xx
changed field x to xx in crate::Pt	main.vl	+7 -7 lines
$ check
ok: 0 errors in main.vl (1 file, 0 shaders)
% cat main.vl
struct Pt {
    xx: i64,
    y: i64,
}

fn f(p: &Pt) -> i64 {
    match p {
        Pt { xx: 0, .. } => 0,
        Pt { xx: x, y } => *x + *y,
    }
}

fn main() {
    let p = Pt { xx: 3, y: 4 };
    let Pt { xx: x, y } = p;
    let q = Pt { xx: 1, y: 2 };
    if let Pt { xx: 1, y: yy } = q {
        println("{yy}");
    }
    println("{} {x} {y}", f(&Pt { xx: 5, y: 6 }));
}
$ run
2
11 3 4
