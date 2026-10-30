## (0.25.3) The tools' cache keeps what `std::NAME` names (std's own item,
## or what std re-exports under NAME): show's `// use` line for std's
## items, and a NAME `std::...`, ask it. The program from the cache has
## neither the scopes nor the table of the items' nodes that the front
## end asks it of: the answer read that table, never made, through a null
## pointer (a crash, SIGSEGV, every time show answered from the cache
## for an item of std; `query show parse_primary` in the compiler). Each
## line runs once without the cache and twice with it (run.sh): the same
## answers.
$ show print_int
// std::fmt::print_int	../../compiler/std/fmt.vl:194-204	effects: io panic
// use std::print_int;
#[inline(never)]
pub fn print_int(v: i64) {
    print_acquire();
    var f = Fmt::to_fd(1);
    // (decimal only: not Fmt::int, whose hex and binary every program
    // using print_int would compile)
    let negative = v < 0;
    fmt_decimal(&f, if negative { (-(v + 1)) as u64 + 1 } else { v as u64 }, negative);
    f.flush();
    print_release();
}
$ show Vec::push
// std::Vec::push	../../compiler/std/std.vl:300-310
    #[stores(x)]
    pub fn push(inout self, x: sink T) {
        if self.len == self.cap && !self.reserve_more(1) {
            out_of_memory();
        }
        // UNSAFE: a raw write. SAFETY: len < cap here, so ptr[len] is room; len counts x.
        unsafe {
            self.ptr[self.len] = x;
        }
        self.len += 1;
    }
$ show HashMap::len
// std::collections::hash_map::HashMap::len	../../compiler/std/collections/hash_map.vl:37-40
    #[inline]
    pub fn len(self) -> i64 {
        self.table.len()
    }
