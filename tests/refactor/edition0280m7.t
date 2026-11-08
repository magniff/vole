## (0.28.0) An `embed wgsl` block is an item, not a struct of the
## program: it derives nothing (the translator wrote `#[derive(Clone,
## Copy)]` inside its declaration). A file that starts with embed blocks
## gets its imports at the first item after them, on that item's line, as
## it would at the first item: fmt keeps a block's text as it is only
## when the block starts its line (the imports before it on that line
## made fmt read the WGSL as vole).
$ main.vl -o mvs
ok: built mvs
% ./mvs
2 1
$ fix --edition rust main.vl
main.vl:1:14: error[type error] expected '[u8]', got 'str'  [in crate::K]
fixed, 1 var to 'let mut', 1 import, 1 copy type derived Clone, Copy	main.vl	+3 -2 lines
warning edit.breaks: 1 new error (1 in crate::K, which the edit does not change); written anyway (--no-check); the error: main.vl:1:14: expected '[u8]', got 'str'
try: volec check main.vl
% cat main.vl
embed wgsl K {
    @compute @workgroup_size(1)
    fn main() {}
}

use std::collections::HashMap; #[derive(Clone, Copy)] struct P { x: i64 }

fn main(gpa: Gpa) {
    let mut m: HashMap<i64, P, Gpa> = HashMap::new_in(gpa);
    let p = P { x: 2 };
    m.insert(1, p);
    println("{} {}", p.x, m.len());
}
// EDITION: rust
$ fmt --check main.vl
