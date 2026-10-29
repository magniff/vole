## (0.25.2.2) A NAME of other programs under the directory (no root
## here): the examples' first, never one under evals/ or tests/ (the
## 0.25.2.1 eval's `try:` lines named other agents' programs).
$ show snap_shot
error query.no-root: no root (VOLE_ROOT, ./main.vl, ./compiler/src/main.vl)
try: volec query show snap_shot --root xroots0252/examples/demo/main.vl
try: volec query show snap_shot --root xroots0252/tools/gen/main.vl
[exit 2]
## FILE::item: the programs with that file; one answers.
$ show sim.vl::Sim::snap_shot
// crate::sim::Sim::snap_shot	xroots0252/examples/demo/sim.vl:6-8	effects: none
    pub fn snap_shot(self) -> i64 {
        self.n
    }
note query.other-root: not in this directory's program; answered from xroots0252/examples/demo/main.vl (--root xroots0252/examples/demo/main.vl)
$ show first_tick
// crate::sim::first_tick	xroots0252/examples/demo/sim.vl:11-13	effects: none
pub fn first_tick() -> i64 {
    1
}
note query.other-root: not in this directory's program; answered from xroots0252/examples/demo/main.vl (--root xroots0252/examples/demo/main.vl)
## A std path no definition answers: std's nearest names, not other
## programs (every program has std).
$ show std::window::Surface::frame
error query.no-match: no definition 'std::window::Surface::frame'
try: volec query show std::gpu::Surface::frame
try: volec query show std::window::script::Script::frame
try: volec query show std::gpu::Frame
[exit 1]
