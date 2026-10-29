# terrain: the agent's analysis

> Saved verbatim by the orchestrator from the agent's final message: the harness refused the agent's own write of this file (subagents may not write report files). Nothing is edited but this note and the headings' markup.

## 1. Result

Works: `volec main.vl -o terrain` builds. `volec test main.vl` passes 8 of 8 at -O0 and -O2. `./terrain --headless` runs on the GPU and prints all checks ok. `--shot` writes a PPM that converts to a correct PNG. `./terrain --frames 120` runs and quits by itself.

What it does: heights from seven octaves of value noise, computed by one WGSL compute dispatch. 16 x 16 chunks of 32 quads, each at a step of 1, 2, 4 or 8 chosen by distance, with skirts under the edges against cracks. Vertices are not stored: a vertex is a grid index, height read from a storage buffer, normal from neighbours. A 2048 Depth32Float shadow pass with 3 x 3 PCF. Materials by height and slope (sand, grass, rock, snow), exponential fog, and an opaque sea at height 0.

Verified:
- `volec check main.vl`: ok, 0 errors.
- `volec test main.vl`: 8 passed, -O0 and -O2 agree.
- `gpu-run --timeout 300 -- ./terrain --headless --shot shot1.ppm --camera 1`: heights min -55.8, max 88.2, mean 3.8, 44.3% under sea level (relief, sea fraction and finite checks ok). Camera 0 chunks at steps 1/2/4/8: 24/45/104/83, 109376 triangles of 589824 at full detail. Shadow map 38.3% covered. Output in run-camera1.txt.
- shot1.png, viewed: grass, sand, rock on steep slopes, cast shadows, a snow cap on the far peak, the sea.

Not verified: the window on a visible display (the display was asleep, and the window said frames come 10 a second until it shows). Real frame times: the `--frames 120` run printed 101 ms, which reflects the throttled window, not the GPU. LOD seam cracks (reasoned about the skirts, did not zoom in). Shadow bias 0.002 and normal offset 1.5 were tuned by eye on one picture.

## 2. How you worked

- `volec guide` (full), `guide gpu`, `guide gpu-render`, `guide window`: 4 reads. The gpu-render depth-only and multi-target examples matched what the shadow pass needed.
- `volec query items std::gpu` (the most useful output: names with signatures and requires clauses), plus `query show` on RenderDesc, PassDesc and Device. `query show` on a struct shows only the struct, not its methods. One wrong guess (`query show is_set`, no such item).
- Not used: `query context`, `query refs`, `edit patch/replace`, `refactor`, `fix --suggested`. I wrote whole files with Write and relied on `volec check`.
- Hooks: check-after-edit and the Write hook ran `volec fix` and fmt. It made 3 `&mut x` to `&x` changes and one `&enc` lent-inout fix, all correct, and reported them. It helped. The "changed on disk since you last read it" notices are noisy when the hook itself rewrote the file. query-first.py blocked one shell grep over compiler/std/gpu/mod.vl (I wanted to know whether Device is Copy). The block gave the right query, but it cost a turn.
- Builds and checks: about 5 `volec main.vl -o terrain` and about 6 `volec check` (some via the hook). Builds took seconds.
- gpu-run: 6 runs. Two waited on the lock (86.8 s and 209 s, load 2.6 to 2.8). One ran a window by mistake and was killed at 120 s (see below).
- Attempts: first compile had 2 errors (Key has no field logical; Color::rgba takes f64), fixed in one edit each. Ownership took about 3 attempts: 3 `own.move_out`/`own.moved` errors on Device and Queue, then 2 errors from my own leftover local `sdev`. Fixed by making the constructor parameters `sink` and reading `s.dev` directly.
- A silent bug: `m.get("headless").is_some()` on a flag compiles and is always false. The program opened a window instead of running headless. Fixed with `m.flag("headless")`. This cost one killed 120 s GPU-lock run.

## 3. What went well

- Error lines were short and mostly exact. The volec fix hook made the `&` marks correctly every time.
- `volec test` runs `#[test]` at -O0 and -O2 and checks agreement.
- The std::gpu API follows wgpu's shape (depth_only, with_depth, bind_texture, textureLoad on texture_depth_2d). Once I had the names the code was short.
- Vertex generation from vertex_index and instance_index with no vertex buffers worked on the first run. Keeping heights on the GPU avoided a readback and a mesh upload.
- map_read on a storage buffer and on a depth-texture copy worked for the numbers without extra code.

## 4. What went badly

- `m.get` on a flag compiles and silently means false (recorded via agent-feedback, "cli flags").
- `struct 'Key' has no field 'logical'`: the message does not list the fields. The real field is `key`. A field list would have saved a round.
- `own.move_out: cannot move 'dev' (Device) out of a reference ... take the parameter 'sink'`: the advice is right, but it also appears for a let parameter moved into a struct literal, and the help does not say a literal moves its fields. A `let sdev = s.dev` local then gave `own.moved` at the move site, which was confusing (recorded).
- `expected 'f64', got 'f32'` for `Color::rgba(SKY[0], ...)`: the try line fixed only the first argument. I replaced the array with literals (recorded).
- The gpu guide has no example of a vertex-less pipeline reading a storage buffer in @vertex, nor of instance-indexed draws (`pass.draw(0..n, c..c+1)`). I inferred both; both worked.
- `volec query show STRUCT` gives the struct only. Methods come from `query items`, a long dump.
- Window timing: when the display is asleep, the window prints "no frame in 3 s ... frames come 10 a second", yet the program still prints a frame time (101 ms). That looks like a measurement and is not one.
- Ownership in general: I do not know which std handles are Copy. Device was not (inferred from the error). Buffer, Texture, pipelines and bind groups were used by value in several places without error. The guide gives no one-line rule.
- `read_heights(inout self) -> [f32]` returning a borrow from self compiled. I did not test whether the borrow rule is what I expect.

## 5. The language

What fought me:
- Handle ownership across struct literals and parameters. "A let parameter cannot be moved out; use sink" is clear once shown, but I met it in three forms.
- `inout self` methods: `self.queue.submit` inside an inout method was fine. Closures passed to render_pass needed locals copied out of self first (`let p = self.scene_pipe;`). Not obvious from the guide.
- Literal typing: Color::rgba takes f64 while the rest of the GPU API is f32. A conversion at the boundary, which cost a round.
- Indexing with an i64 loop variable: `steps[c as usize]` compiled. I did not test whether the cast is needed.

What I liked:
- f-string format specs (`{x:.1}`) for check lines.
- `#[test]` beside the code with assert_eq on bool expressions (I used near() helpers for float comparisons).
- `sink`/`inout` in signatures makes data flow visible (`fn frame(inout self, enc: inout gpu::Encoder, ...)`).
- No vertex buffer at all for a terrain avoided a lot of boilerplate.

## 6. Suggestions, ranked by time saved

1. A flag read through `m.get` should not compile silently. `m.flag` exists and is right. This was the biggest time sink: a lock run, a window, a turn.
2. Unknown-field errors should list the fields (`has no field 'logical'; fields: win, code, key, mods, pressed, repeat, ime, text_follows`).
3. `own.move_out` and `own.moved` should point at the moving statement, including struct literals, not only the use.
4. A guide line on which std handles are Copy and which move (Device, Queue, Buffer, Texture, pipelines, bind groups, Shader).
5. `volec query show` with a methods option, or an items filter for one type.
6. Window timing: say when the frame timing is not valid (throttled, display asleep).
7. Guide examples: a vertex-less render pipeline reading a storage buffer in @vertex, and instance-indexed draws, in gpu-render.
8. Color::rgba taking f32, or an overload, would remove a conversion each time a colour is written.

Numbers: about 6 builds and checks; 3 ownership fix attempts; 1 wrong flag (one 120 s GPU run wasted); 2 lock waits (87 s and 209 s, not the program's fault); 8 tests; 3 fixed cameras; 1 PNG reviewed; about 1000 lines of vole in 5 files.

Tool friction recorded with tools/agent-feedback: "cli flags", "ownership errors", "std::window Key", "std::gpu Color::rgba".
