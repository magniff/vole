## (0.25.3) The tools' cache keeps what `std::NAME` names (std's own item,
## or what std re-exports under NAME): show's `// use` line for std's
## items, and a NAME `std::...`, ask it. The program from the cache has
## neither the scopes nor the table of the items' nodes that the front
## end asks it of: the answer read that table, never made, through a null
## pointer (a crash, SIGSEGV, every time show answered from the cache
## for an item of std; `query show parse_primary` in the compiler). Each
## line runs once without the cache and twice with it (run.sh): the same
## answers.
$ show print
// std::fmt::print	<std>:15164-15173
// x on stdout (`print("{x}")`); stdout is line-buffered when a terminal.
// later: format_fns
#[effects(io, panic, diverge, T)]
pub fn print<T: Display>(x: T) {
    let mut out = crate::io::stdout();
    if crate::io::Write::write_fmt(&mut out, x).is_err() {
        let msg: &str = "failed printing to stdout";
        crate::panic::panic(msg);
    }
}
$ show Vec::push
// std::vec::Vec::push	<std>:4541-4556
    // Appends x, growing from A when it is full. (0.28.0) Inline, and its
    // clauses `debug` (checked by volec test): a push is a compare, one
    // copy of x into its slot and an increment, the growth out of line.
    // Its `ensures` made it a call of push$body, out of line, at every
    // push (about 7% of the rust-edition compiler's check of itself).
    #[inline]
    #[effects(panic, T, A)]
    pub fn push(&mut self, x: T)
        debug ensures self.len() == old(self.len()) + 1
        debug ensures self.len() <= self.capacity()
    {
        if self.len == self.cap {
            self.grow_one();
        }
        self.put(x);
    }
$ show HashMap::len
// std::collections::hash_map::HashMap::len	<std>:11146-11149
    #[effects()]
    pub fn len(&self) -> usize {
        self.table.items
    }
