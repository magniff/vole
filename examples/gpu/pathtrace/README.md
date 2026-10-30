# pathtrace

An interactive GPU path-tracing laboratory written in Vole. `std::gpu` compute
shaders trace and accumulate every path; `std::window` owns the real application
window, events and camera controls. A full-screen GPU render pass tone-maps the
accumulation buffer into the native surface, then a second, alpha-blended pass
draws the on-screen immediate-mode panel over it. There is no CPU renderer and
no per-frame image readback.

## Build and run

From the repository root:

```sh
target/volec -O2 examples/gpu/pathtrace/main.vl -o pathtrace
./pathtrace
```

The window opens on the **Studio** scene: diffuse, glass, chrome and rough-gold
spheres, a glossy checkerboard floor, red/blue walls and a rectangular area
light. On a high-DPI display, paths are traced at logical resolution and
upscaled by the display shader to keep interaction responsive; the panel is
drawn at native resolution.

## The panel

The panel in the top-right corner is a five-section accordion, written as an
immediate-mode UI (`ui.vl`, `ui_panel.vl`): the program describes it every frame
and the widgets return clicks and new values. It is the primary way to change
the laboratory.

| section | controls |
|---|---|
| **Scene** | four complete presets: Studio, Fog hall, Mirror field, Material grid |
| **Camera** | field of view, depth of field and aperture, focus distance, focus on the selected sphere, reset view |
| **Atmosphere** | volumetric fog on/off, density, anisotropy, fog color, environment, light intensity and height, light color, global illumination |
| **Material** | M1–M4 picker, base color, roughness, metallic, index of refraction, transmission, absorption tint and density, emission |
| **Display** | debug view, comparison split, render size, frame time, mode |

The footer has **PAUSE**, **CLEAR** (accumulation) and **RESET ALL** (the whole
scene). Drag the title bar to move the panel, **HIDE** to collapse it to a
`SHOW UI` tab, and **Tab** to toggle it from the keyboard. A dropdown opens
below its box (or above it near the bottom edge) and floats over the panel.
Each control writes the same `Lab` the keyboard shortcuts write, and every edit
resets accumulation except display-only changes.

The scenes:

- **Studio** — four spheres, area light, glossy checkerboard, red/blue walls.
- **Fog hall** — a long room of orbs fading into a blue homogeneous medium.
- **Mirror field** — open sky, a mirror floor and four free-standing spheres.
- **Material grid** — the 4×4 roughness × metallic comparison wall.

The window title remains a compact dashboard (scene, samples, frame time, render
resolution, debug mode).

## Controls

Everything on the panel is also on the keyboard, as an accelerator. Camera
orbit and zoom are constrained together to keep the eye inside the current
scene, with margins from the side walls, back wall and floor.

### Camera and rendering

| input | action |
|---|---|
| drag / arrow keys | orbit; reset accumulation |
| scroll | zoom; reset accumulation |
| `,` / `.` | decrease / increase field of view |
| `o` | toggle thin-lens depth of field |
| `;` / `'` | decrease / increase aperture |
| `u` | focus on the selected sphere |
| space | pause / resume accumulation |
| `r` | reset accumulation |
| `b` | split-screen one-sample / converged comparison |
| F1 / F2 | decrease / increase exposure without invalidating samples |
| Backspace | restore the current scene's defaults |
| Tab | hide / show the panel |
| `f` | fullscreen |
| `q` / Esc | quit |

### Material playground

The panel's M1–M4 chips select M1 diffuse, M2 glass, M3 chrome or M4 gold. Every
material edit resets accumulation.

| input | action |
|---|---|
| `c` | cycle base-color palettes |
| `[` / `]` | decrease / increase GGX roughness |
| `-` / `=` | decrease / increase metallicness |
| `e` | toggle dielectric transmission |
| `n` / `m` | decrease / increase index of refraction |
| `a` | cycle Beer–Lambert absorption tint |
| `v` / `w` | decrease / increase absorption density |
| `9` / `0` | decrease / increase emission strength |
| `t` | jump between the Studio and Material grid scenes |

### Lighting and atmosphere

| input | action |
|---|---|
| `i` / `k` | move the area light back / forward |
| `j` / `l` | move the area light left / right |
| `1` / `2` | decrease / increase light intensity |
| `3` / `4` | decrease / increase light width |
| `5` / `6` | decrease / increase light height |
| `7` / `8` | decrease / increase procedural environment illumination |
| `x` | cycle light color |
| `g` | toggle direct-only / full global illumination |
| `h` | toggle homogeneous volumetric fog |
| `y` | cycle fog density |

### Diagnostics

`d` cycles beauty, surface normals, albedo, depth, intersection-test cost,
material IDs, bounce depth, relative-variance heatmap and ray-path view. These
are display modes and normally preserve accumulated radiance. Right-click a
pixel to trace and inspect its path: yellow diffuse segments, cyan reflections,
magenta refractions and orange fog scattering. Entering ray-path mode resets
accumulation so the selected path is recorded by the compute shader.

The scene uses a small analytic intersection list, so a BVH would add complexity
without useful acceleration. Traversal mode reports actual intersection tests;
there are deliberately no fabricated BVH counters.

## Rendering architecture

- **PBR materials:** opaque surfaces combine Lambert diffuse and GGX specular
  with Schlick Fresnel and Smith masking. BSDF sampling uses the corresponding
  diffuse/GGX mixture PDF. Glass uses Fresnel reflection/refraction and
  Beer–Lambert absorption.
- **Correct area-light sampling:** the rectangle is sampled uniformly by area
  and converted to solid-angle PDF with both cosines and distance. Shadow rays
  include homogeneous-media transmittance. Rectangle emission is accepted after
  specular events but skipped after NEE-sampled diffuse events, avoiding double
  counting. Object emission is BSDF-sampled and is not also next-event sampled.
- **Scene geometry:** `trace.wgsl` selects one of three analytic families from
  the scene index (the fourth preset reuses the studio geometry with the 4×4
  material wall). Shadow rays use the same per-scene blocker list as the camera
  rays, so light does not leak through geometry that is not there.
- **Progressive moments:** each pixel keeps radiance sum, squared-luminance sum
  and its first sample (three `vec4<f32>` slots). The variance view estimates
  relative standard error from those moments, not brightness. `b` compares the
  saved first sample with the current average. Adaptive sampling is not enabled;
  the estimate is diagnostic rather than an arbitrary stopping heuristic.
- **Volumetric fog:** free-flight distance sampling, Henyey–Greenstein phase
  sampling and next-event area lighting simulate a homogeneous participating
  medium with a per-channel scattering albedo. Multiple scattering is expensive
  and intentionally noisy at low sample counts. There is no heterogeneous
  medium or claim of converged caustics.
- **Diagnostics:** a primary-hit G-buffer stores normals, albedo, depth, material
  ID, intersection count and bounce depth. A tiny separate GPU buffer records up
  to 15 nodes for the selected ray. Instrumentation does not require host image
  readback.
- **Presentation and performance:** compute and rendering are encoded in order
  on one queue. Interactive frames accumulate four samples but execute only one
  display pass, so sampling is not capped by the window refresh rate. Static
  diagnostic modes stop after one sample. The integrator uses 16×16 workgroups,
  lightweight ID-only candidate hits, early-out any-hit shadow traversal,
  canceled Smith visibility terms and unbiased Russian roulette from the third
  path segment, with at most six segments. Swapchain textures remain render
  targets, as required by `std::gpu`; the display fragment shader reads storage
  buffers directly. The panel's vertex buffer and atlas are uploaded once per
  frame and drawn in a blended pass that loads the scene target instead of
  clearing it. Exposure, comparison and most debug changes use
  `Renderer::redraw`, which does not add or invalidate a sample. Camera,
  material, light, GI, fog and resize changes reset it.

All host-side application and state logic is Vole. The WGSL is in
`trace.wgsl`, `display.wgsl` and `ui.wgsl`, embedded at compile time by
`include_str` in `shaders.vl` and `ui_render.vl` and compiled at run time by
`std::gpu::shader_wgsl`. Live editing is not included: the API can compile WGSL
at runtime, but a shader text editor is outside this example's core renderer.

## Headless verification

The same pipelines run into `RawSurface::Headless`; readback is used only for
checks and optional PPM output:

```sh
./pathtrace --headless --samples 16 --size 96x64 --out pathtrace.ppm
./pathtrace --headless --grid --samples 64 --size 320x200 --out grid.ppm
./pathtrace --headless --fog --dof --samples 128 --size 320x200 --out fog.ppm
./pathtrace --headless --direct --samples 32 --size 320x200
./pathtrace --headless --scene 1 --samples 64 --size 320x200 --out fog-hall.ppm
./pathtrace --headless --debug 1 --samples 4 --size 96x64
./pathtrace --headless --debug 8 --samples 8 --size 320x200 --out rays.ppm
./pathtrace --headless --ui --scene 1 --samples 4 --size 1280x720 --out panel.ppm
./pathtrace --headless --ui --ui-section 2 --ui-scale 2 --size 2560x1440 --out hidpi.ppm
```

`--scene N` picks one of the four presets; `--grid` is the same as `--scene 3`.
`--ui` draws the actual panel over the final frame through the window's own UI
pipeline; `--ui-section N` opens a section and `--ui-scale S` sets physical
pixels per UI point, so the HiDPI layout can be checked without a display.

Checks cover non-empty changing output, decreasing local pixel noise for
progressive scenes, and exact reproduction of sample one after reset. Diagnostic
modes intentionally have a static first-hit image and skip the noise-decrease
assertion. `target/volec test examples/gpu/pathtrace/main.vl` runs the Vole
state, camera-bounds, scene-switch, panel-hit and immediate-mode widget tests.

## Reproducible benchmark

```sh
./pathtrace --benchmark --samples 1024 --size 640x400
```

Benchmark mode uses the selected scene (default Studio) and a fixed RNG seed.
Initialization (including shader compilation) is reported separately.
Steady-state wall time covers uninterrupted offscreen GPU frames plus one final
readback synchronization; there is no per-frame readback or presentation pacing.
`--grid`, `--direct`, `--fog`, `--dof` and `--scene` also select benchmark
workloads. CPU frame interval in the interactive title is not represented as GPU
execution time: `std::gpu` currently exposes no timestamp queries.

Measured on an Apple M5 with Metal (1024 samples, 640×400): 1.76 ms
initialization, 0.484 ms/sample wall time, 2065.9 accumulated samples/s and
528.86 Mpaths/s. These are measurements, not GPU timestamp estimates; rerun the
command above for local numbers.

## Files

| file | role |
|---|---|
| [main.vl](main.vl) | CLI, native window, input routing, pause/reset policy and shortcuts |
| [state.vl](state.vl) | Vole scene presets, material/light/camera state, bounds and unit tests |
| [render.vl](render.vl) | `std::gpu` resources, uniform packing, dispatch and presentation |
| [ui.vl](ui.vl) | immediate-mode widgets, draw list and unit tests |
| [ui_panel.vl](ui_panel.vl) | the five-section panel and its actions |
| [ui_render.vl](ui_render.vl) | the UI pipeline, atlas upload and blended pass |
| [ui.wgsl](ui.wgsl) | WGSL for one textured, alpha-blended quad |
| [font.vl](font.vl) | 5×7 bitmap font and its atlas |
| [shaders.vl](shaders.vl) | the two path-tracing shaders, `embed wgsl K from` the `.wgsl` files |
| [trace.wgsl](trace.wgsl) | WGSL integrator, scene geometry, media, G-buffer and accumulation |
| [display.wgsl](display.wgsl) | WGSL tone mapping and display modes |
| [check.vl](check.vl) | headless readback checks, PPM output (with `--ui`) and benchmark |

On macOS the current backend is Metal. No additional frameworks, assets or link
flags are required. `volec guide gpu` and `volec guide window` describe the APIs.
