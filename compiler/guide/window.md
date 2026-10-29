# Windows: std::window (0.23; guide updated 0.25.4)

`std::window` opens windows and reads their input, winit's objects with
events pulled rather than pushed. 0.23.0 runs on macOS (Cocoa); Wayland
and X11 come in 0.23.1 behind the same API.

```text
use std::window::{App, Event, WindowDesc};

fn main(gpa: Gpa) -> i32 {
    var app = App::new_in(gpa).unwrap();              // Err(NoDisplay) under ssh
    let desc = WindowDesc::new("demo", 800, 600);     // logical points
    var win = app.window(desc).unwrap();
    win.request_frame();
    loop {
        match app.wait().unwrap() {                   // blocks; nothing busy-waits
            Event::Frame(_) => draw(win),             // once per request_frame
            Event::Key(k) => if k.pressed && !k.ime { on_key(k) },
            Event::Text(t) => typed(t.bytes[0..t.len as i64]),  // UTF-8, inline
            Event::Resize(_, s) => resize(s.w, s.h, s.scale),   // physical pixels
            Event::Readable(fd) => read_more(fd),     // a watched fd (app.watch)
            Event::Close(_) | Event::Quit => break,
            _ => {}
        }
    }
    0                                                 // win, then app, dropped
}
```

- **Events**: `Frame`, `Key` (physical `KeyCode`, logical `Logical`,
  `Mods` with left and right, `repeat`, `ime`, `text_follows`), `Text`,
  `Preedit` (`app.preedit()` is the composition), `Resize` (physical
  pixels and the scale), `Mouse` (press, release, move; pixels from the
  top-left; `clicks`), `Scroll` (`precise`: pixels, else lines),
  `Cursor` (enter, leave), `Focus`, `Readable`, `Close`, `Quit`.
- **Calls**: `app.wait()`, `poll()`, `wait_timeout(ms)`; `app.watch(fd)`;
  `app.clipboard_get_in(gpa)`, `clipboard_set(text)`;
  `app.on_live_resize(f, ctx)` (`ctx` a raw `*u8`; macOS runs its own loop while a window
  edge is dragged: `f` is called there and may `poll` and draw).
  `win.request_frame()`, `size()`, `raw_surface()` (the CAMetalLayer),
  `set_title`, `set_cursor`, `hide_cursor_while_typing`,
  `set_ime_area(x, y, w, h)`, `set_fullscreen`, `focused`, `close`.
- **HiDPI units** (0.25.2.2): only `WindowDesc::new(title, w, h)` is in
  logical points. Everything a program reads back is in physical pixels:
  `win.size()` (a `Size { w, h, scale }`), `Resize`'s size, `Mouse.x`
  and `.y`, `Scroll`'s precise deltas. On a Retina display (`scale`
  2.0) `WindowDesc::new("demo", 800, 600)` gives `win.size()` 1600 x
  1200. Configure the surface with that size (`surf.configure(dev,
  s.w, s.h, ..)`, again at each `Resize`), so `surf.width` and
  `surf.height` are the drawable's pixels too; a snapshot of the window
  (a copy of its frame, a canvas, a PPM) is `surf.width` x
  `surf.height`, never the WindowDesc's numbers (those give its top-left
  quarter at scale 2). The scale is the window's, not the surface's:
  `Surface` has none (its fields are `raw`, `configured`, `width`,
  `height`, `format`); keep the last `Size`'s `scale` (`win.size()`,
  then each `Resize`'s) beside the surface, and divide by it only for
  logical points (UI sizes meant to look the same on every display). The
  mouse maps with the surface's size now (`window#mouse-and-surface-size`).
- **Frames when the window is not shown** (0.25.2.1) come from a
  10 Hz timer: their times are not the program's
  (`window#when-the-window-is-not-shown`).
- **Keys and text**: a key that types something is a `Key` with
  `text_follows`, then a `Text`. Encode keys that do not (arrows, Return,
  Control-letters); send `Text` as it is. `ime` marks keys an input
  method took.
- **Linking**: nothing to add. std::window's extern blocks name what
  they link (`#[link(framework = "AppKit")]`, `guide c-interop`), so
  `volec main.vl -o app` links AppKit, QuartzCore and libobjc.
- **Tests**: `tests/window/run.sh`; the checks that need a display skip
  without one (`VOLE_NO_DISPLAY_TESTS=1` too). (0.25.4) A program's own
  event loop runs without a display, its input and frames from a script:
  `VOLE_WINDOW_SCRIPT='frames 2; key space; click 40 30; shot a.ppm;
  frames 1' ./prog` (`window#testing-input-without-a-display`).

## Mouse and surface size

`Mouse.x` and `.y` are physical pixels from the content's top-left,
the units of `surf.width` and `surf.height`. Map them with the
surface's size now: `surf.configure` at each `Event::Resize` sets
`surf.width` and `.height` (a `Resize` also comes first, after
`app.window`). A size taken once at the start (`let px = win.size();`)
is wrong once the window is resized or moved to a display of another
scale: the pointer then lands on the wrong cell. To a grid of `cells`:
`m.x / surf.width as f64 * cells`; to a shader's coordinates (y up):
`2 * x / width - 1` and `1 - 2 * y / height`.

```vole
use std::gpu;
use std::gpu::RawSurface;
use std::window::{App, Button, Event, MouseAction, WindowDesc};

const GRID: f64 = 128.0; // the simulation's cells across and down

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    var app = match App::new_in(gpa) {
        Ok(a) => a,
        Err(_) => return Ok(()),
    };
    var win = match app.window(WindowDesc::new("mouse", 512, 512)) {
        Ok(w) => w,
        Err(_) => return Ok(()),
    };
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var _queue) = inst.adapter()?.device()?;
    var surf = inst.surface(dev, RawSurface::MetalLayer(win.raw_surface()))?;
    let px = win.size(); // the size now: stale after a Resize
    surf.configure(dev, px.w, px.h);
    var scale = px.scale; // the window's; a Surface has no scale
    var down = false;
    loop {
        match app.wait() {
            Ok(Event::Resize(_, s)) => {
                surf.configure(dev, s.w, s.h); // surf.width, .height follow
                scale = s.scale;
            }
            Ok(Event::Mouse(m)) => {
                if m.button == Button::Left && m.action != MouseAction::Move {
                    down = m.action == MouseAction::Press;
                }
                if down {
                    // with the surface's size, never px
                    let cx = (m.x / surf.width as f64 * GRID) as i64;
                    let cy = (m.y / surf.height as f64 * GRID) as i64;
                    let nx = 2.0 * m.x / surf.width as f64 - 1.0;
                    let ny = 1.0 - 2.0 * m.y / surf.height as f64;
                    let pt = m.x / scale; // logical points, for UI sizes
                    println(f"cell {cx} {cy}, shader {nx:.2} {ny:.2}, x {pt:.0} pt");
                }
            }
            Ok(Event::Close(_)) | Ok(Event::Quit) => break,
            _ => {}
        }
    }
    Ok(())
}
```

## When the window is not shown

The display gives no frames while it is asleep (the screen locked,
nobody there), or while the window is covered, hidden, minimized or on
another Space. A request is then answered by a timer, 10 frames a
second (60 without a display link), so a `--frames N` loop still ends;
after 3 s without a display frame stderr gets one line, `window: no
frame in 3 s: the window is occluded or not shown (the display is
asleep); ...`. A frame time measured then is the timer's 100 ms, not
the program's. A program started from a background shell is not made
active: its window is ordered front regardless.

So a check that times GPU work does it headless, without the window:
submit the work of N frames with no wait between them, `wait_idle`
once, and divide by N. That is throughput, the frames a second the GPU
sustains with submissions overlapping, not latency, how long one frame
takes from its submit to its end (one submit, then a wait:
`gpu#timing-gpu-work`). Warm up first, and say which one a report
gives.

```vole
use std::gpu;
use std::gpu::BufferUsage;

const STEP: [u8] = """
    @group(0) @binding(0) var<storage, read_write> xs: array<u32>;
    @compute @workgroup_size(64) fn main(@builtin(global_invocation_id) id: vec3<u32>) {
        xs[id.x] = xs[id.x] * 3u + 1u;
    }
    """;

// A frame's GPU work: what the windowed program submits each frame.
fn frame(dev: gpu::Device, queue: inout gpu::Queue, pipe: gpu::ComputePipeline, group: gpu::BindGroup) {
    var enc = dev.encoder();
    enc.compute_pass(|pass| {
        pass.set_pipeline(pipe);
        pass.set_bind_group(0, group);
        pass.dispatch(1024);
    });
    queue.submit(enc.finish());
}

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    let pipe = dev.compute_pipeline(dev.shader_wgsl(STEP)?, "main")?;
    let xs = dev.buffer(1024 * 64 * 4, BufferUsage::STORAGE);
    let group = dev.bind_group(pipe.bind_layout(0), [gpu::bind(0, xs)][..]);
    frame(dev, &queue, pipe, group); // a warm-up: the first submit sets things up
    queue.wait_idle()?;
    let n = 200;
    let t0 = std::time::monotonic_now();
    for _ in 0..n {
        frame(dev, &queue, pipe, group); // no wait between them
    }
    queue.wait_idle()?; // all n done
    let ms = std::time::monotonic_now().saturating_sub(t0).as_millis_f64() / n as f64;
    println(f"{n} frames timed: {ms > 0.0}"); // a report prints f"{ms:.3} ms a frame"
    Ok(())
}
```
```out
200 frames timed: true
```

## Checking the pixels headless

A windowed program's pixels can be checked without a window: give it a
`--headless` mode that draws its final frame with the same code into a
`RawSurface::Headless` surface (frames, no window), copies the frame's
texture into a `MAP_READ | COPY_DST` buffer (rows 256-byte aligned),
optionally draws the overlay first (`gpu-render#drawing-over-the-image-you-just-made`),
and then compares pixels or writes a PPM to look at (`sips -s format png
shot.ppm --out shot.png` on macOS makes an image a viewer opens). The
worked example is examples/gpu/pathtrace: `--headless --ui --size
1280x720 --out panel.ppm` draws the panel over the final frame through
the window's own UI pipeline (`--ui-scale 2` for a Retina layout), and
its case in tests/examples checks it.

```vole
use std::{fs, gpu};
use std::gpu::{BufferUsage, Color, Format, PassDesc, RawSurface, TextureView};

// The frame's drawing, shared with the window's Event::Frame: here a
// clear; in a program its scene passes, then the overlay.
fn draw(dev: gpu::Device, queue: inout gpu::Queue, view: TextureView) {
    var enc = dev.encoder();
    enc.render_pass(PassDesc::color(view, clear: Color::rgba(1.0, 0.5, 0.0, 1.0)), |_| {});
    queue.submit(enc.finish());
}

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let (w, h) = (64, 32);
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    var surf = inst.surface(dev, RawSurface::Headless)?; // frames, no window
    surf.configure(dev, w, h, format: Format::Bgra8Unorm, vsync: false);
    let frame = surf.frame()?;
    draw(dev, &queue, frame.texture.view());
    let stride = (w * 4 + 255) / 256 * 256; // rows 256-byte aligned
    var readback = dev.buffer(stride * h, BufferUsage::MAP_READ | BufferUsage::COPY_DST);
    var enc = dev.encoder();
    enc.copy_texture_to_buffer(frame.texture, readback, stride);
    queue.submit(enc.finish());
    frame.present(&queue);
    let px = readback.map_read(dev); // B, G, R, A a pixel
    var ppm = format_in(f"P6\n{w} {h}\n255\n", gpa);
    for y in 0..h {
        for x in 0..w {
            let p = y * stride + x * 4;
            ppm.push(px[p + 2]);
            ppm.push(px[p + 1]);
            ppm.push(px[p]);
        }
    }
    let ok = fs::write("shot.ppm", ppm.as_slice()).is_ok(); // open it, or compare
    println(f"rgb {px[2]} {px[1]} {px[0]}, wrote shot.ppm: {ok}");
    Ok(())
}
```
```out
rgb 255 128 0, wrote shot.ppm: true
```

## Testing input without a display

(0.25.4) A program's own event loop runs with no display when
`VOLE_WINDOW_SCRIPT` is set: `App::new_in` opens no window server and
the events come from the script, in order. Each `Frame` comes as soon as
the program asks for one (`request_frame`), never from a timer, so a
test of keys, the mouse or a frame count takes milliseconds. The
window's `raw_surface()` is null, which std::gpu takes for
`RawSurface::Headless`: the frames are offscreen, at the script's size.
The program needs no code for it; `shot FILE` writes the next frame it
presents as a PPM to compare (`tests/ppmdiff.sh`, a case's
`EXPECT-PPM`).

```vole
use std::gpu;
use std::gpu::{Color, PassDesc, RawSurface};
use std::window::{App, Button, Event, MouseAction, WindowDesc};
use std::window::keys::Logical;

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    var app = match App::new_in(gpa) {
        Ok(a) => a,
        Err(_) => return Ok(()), // no display, no script
    };
    var win = match app.window(WindowDesc::new("paint", 400, 300)) {
        Ok(w) => w,
        Err(_) => return Ok(()),
    };
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    var surf = inst.surface(dev, RawSurface::MetalLayer(win.raw_surface()))?;
    var red = false;
    win.request_frame();
    loop {
        match app.wait() {
            Ok(Event::Resize(_, s)) => surf.configure(dev, s.w, s.h),
            Ok(Event::Frame(_)) => {
                let frame = surf.frame()?;
                let c = if red { Color::rgba(1.0, 0.0, 0.0, 1.0) } else { Color::black() };
                var enc = dev.encoder();
                enc.render_pass(PassDesc::color(frame.texture.view(), clear: c), |_| {});
                queue.submit(enc.finish());
                frame.present(&queue);
                win.request_frame();
            }
            Ok(Event::Mouse(m)) => {
                if m.button == Button::Left && m.action == MouseAction::Press {
                    red = !red;
                }
            }
            Ok(Event::Key(k)) => {
                if k.pressed && k.key == Logical::Char('q' as u32) {
                    break;
                }
            }
            Ok(Event::Close(_)) | Ok(Event::Quit) => break,
            _ => {}
        }
    }
    Ok(())
}
```

```sh
VOLE_WINDOW_SCRIPT='size 64x32; frames 2; click left 10 10; shot red.ppm; frames 1; key q' ./paint
VOLE_WINDOW_SCRIPT=@input.script ./paint      # the script in a file
```

The commands, separated by `;` or newlines (`#` a comment); coordinates
are physical pixels from the content's top-left:

| command | events |
|---|---|
| `size 640x480 [S]` | first: the window's size and scale (default: the WindowDesc's, scale 1) |
| `frames N` | up to N `Frame`s, one for each `request_frame` (none asked for: none sent, the program is idle) |
| `key K`, `keydown K`, `keyup K` | a press and a release, or one; K is a character (`a`, `+`, `A` is shift+a) or a name (`space enter tab backspace escape delete insert home end pageup pagedown left right up down f1`..`f20`), after `shift+ ctrl+ alt+ cmd+`; a printable press is followed by its `Text` |
| `move X Y` | the pointer moves |
| `press [B] X Y`, `release [B] X Y`, `click [B] X Y` | B: `left` (default), `right`, `middle`; then `shift`, `ctrl`, `alt` or `cmd` held |
| `scroll DY [DX]` | a wheel, in lines (positive: up) |
| `resize WxH`, `focus on`/`off` | `Resize`, `Focus` |
| `shot FILE.ppm` | the next frame presented (`frame.present`) is also written to FILE (`gpu::capture_next_frame`) |
| `close`, `quit` | `Close`, `Quit` |

- When the script ends, each open window gets `Close`, then `Quit`; a
  program still waiting after that stops (exit 1) with a line saying so.
  A command that does not parse stops it (exit 2) with its line:
  `window.script: VOLE_WINDOW_SCRIPT line 1: unknown command ...`.
- A UI that reads the mouse in its frame (immediate mode) needs a frame
  between a press and its release: `press 470 345; frames 1; release 470
  345`. `click` sends both before the next frame.
- Time does not pass: a program that moves things by the clock between
  frames moves them by the few microseconds a frame takes. Pause it
  (life's space) or step it (life's `n`) from the script.
- In a test case: `// ENV: VOLE_WINDOW_SCRIPT=...` and `// EXPECT-PPM:
  shot.ppm tests/golden/NAME.ppm region X,Y,W,H` (`tests/examples/
  gpu-life-script.test` paints and steps examples/gpu/life;
  `pathtrace-script.test` clicks a button of pathtrace's panel).
