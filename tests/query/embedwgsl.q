## (0.26.0) embed wgsl blocks (embedwgsl/): a block is its static, shown
## and listed as `embed wgsl K`; grep classifies its text by WGSL's rules
## (a comment, the rest code); refs of `SIM.step` reach the WGSL `fn step`.
$ items crate
# crate	embedwgsl/main.vl
4	static	embed wgsl DRAW
16	static	embed wgsl SIM
35	static	embed wgsl FILL from "shaders/fill.wgsl"
37	fn	fn main() -> i32
$ show SIM
// crate::SIM	embedwgsl/main.vl:16-33
embed wgsl SIM {
    @group(0) @binding(0) var<storage, read_write> cells: array<u32>;

    @compute @workgroup_size(64)
    fn init(@builtin(global_invocation_id) id: vec3<u32>) {
        cells[id.x] = 0u;
    }

    // rule: the next state; cells[] is read once
    fn rule(x: u32) -> u32 {
        return x + 1u;
    }

    @compute @workgroup_size(64)
    fn step(@builtin(global_invocation_id) id: vec3<u32>) {
        cells[id.x] = rule(cells[id.x]);
    }
}
$ grep cells
# embedwgsl/main.vl
17:52	code	SIM	@group(0) @binding(0) var<storage, read_write> cells: array<u32>;
21:9	code	SIM	cells[id.x] = 0u;
24:30	comment	SIM	// rule: the next state; cells[] is read once
31:9	code	SIM	cells[id.x] = rule(cells[id.x]);
31:28	code	SIM	cells[id.x] = rule(cells[id.x]);
$ refs SIM.step
# embedwgsl/main.vl
30:8	def	fn step(@builtin(global_invocation_id) id: vec3<u32>) {
39:31	read	main	println(f"{SIM.init} {SIM.step}");
$ def FILL
crate::FILL	embedwgsl/main.vl:35:12	static	embed wgsl FILL from "shaders/fill.wgsl"
## (0.26.2) the file form's file is a file of the program: grep lists its
## lines, by WGSL's rules, and FILL.fill is defined in it.
$ grep workgroup_size
# embedwgsl/main.vl
19:15	code	SIM	@compute @workgroup_size(64)
29:15	code	SIM	@compute @workgroup_size(64)
# embedwgsl/shaders/fill.wgsl
1:11	code	crate	@compute @workgroup_size(1)
$ refs FILL.fill
# embedwgsl/shaders/fill.wgsl
2:4	def	fn fill() {}
