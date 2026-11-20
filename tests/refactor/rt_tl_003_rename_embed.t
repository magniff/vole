## XFAIL: RT-TL-3: query refs and refactor rename miss the uses of an embed wgsl item and of a const its `with` names (open)
## TRACE is an `embed wgsl` item used as TRACE.src and TRACE.main;
## BOUNCES is a const named in `with BOUNCES` and read by the shader.
## refs must list every use, and rename must rename them (or say why it
## cannot), not refuse with "undefined variable" errors of its own making.
$ query refs TRACE
# main.vl
3:12	def	embed wgsl TRACE with BOUNCES {
12:57	read	main	println("{} bounces, shader embedded: {}", BOUNCES, TRACE.src.len() > 0);
13:19	read	main	println("{}", TRACE.main);
$ refactor rename TRACE T2
renamed crate::TRACE to T2	main.vl	+3 -3 lines
$ query refs BOUNCES
# main.vl
1:7	def	const BOUNCES: u32 = 4;
3:23	with	TRACE	embed wgsl T2 with BOUNCES {
7:24	read	T2	image[0] = f32(BOUNCES);
12:48	read	main	println("{} bounces, shader embedded: {}", BOUNCES, T2.src.len() > 0);
$ check
ok: 0 errors in main.vl (1 file, 1 shader)
