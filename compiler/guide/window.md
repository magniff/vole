# Windows: std::window (0.23; guide updated 0.25.2.2)

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
  quarter at scale 2). Divide by `scale` only for logical points (UI
  sizes meant to look the same on every display).
- **Frames when the window is not shown** (0.25.2.1): the display gives
  no frames while it is asleep (the screen locked, the person away), or
  while the window is covered, hidden, minimized or on another Space. A
  request is then answered by a timer, 10 frames a second (60 without a
  display link), so a `--frames N` loop still ends; after 3 s without a
  display frame stderr gets one line, `window: no frame in 3 s: the
  window is occluded or not shown (the display is asleep); ...`. Frame
  times measured then are the timer's (100 ms), not the GPU's: time a
  GPU program headless or with the display awake. A program started
  from a background shell is not made active: its window is ordered
  front regardless.
- **Keys and text**: a key that types something is a `Key` with
  `text_follows`, then a `Text`. Encode keys that do not (arrows, Return,
  Control-letters); send `Text` as it is. `ime` marks keys an input
  method took.
- **Linking**: nothing to add. std::window's extern blocks name what
  they link (`#[link(framework = "AppKit")]`, `guide c-interop`), so
  `volec main.vl -o app` links AppKit, QuartzCore and libobjc.
- **Tests**: `tests/window/run.sh`; the checks that need a display skip
  without one (`VOLE_NO_DISPLAY_TESTS=1` too).
