## 0.26.0: a struct's fields are private to its module unless `pub`
## (tests/refactor/fields026/): a read of one from another module is
## field.private, its help the field with `pub` (fix --only pub writes
## it); a literal is field.literal-private, its help the constructor.
## `#[sealed]` is that rule: attr.obsolete, which fix --only
## obsolete-attr deletes.
$ check
geometry.vl:1:24: warning[attr.obsolete] '#[sealed]' is the default from 0.26: every field not marked 'pub' is private to its module | help: delete it (`volec fix --only obsolete-attr` deletes every one) | try: volec fix --only obsolete-attr main.vl
main.vl:7:15: error[field.literal-private] cannot make a 'Rect' here: its field 'w' is private to module 'geometry' | help: make one with its constructor: 'Rect::new'
main.vl:8:6: error[field.private] field 'w' of 'Rect' is private to module 'geometry' | help: make it public: 'pub w: i64' at geometry.vl:2:19 | try: volec fix --suggested main.vl
[exit 1]
## query context says a field's visibility.
$ query context Rect.w
// crate::geometry::Rect.w	geometry.vl:1-2	private to module geometry
#[derive(Clone, Copy)] #[sealed]
pub struct Rect { w: i64, pub h: i64 }
// used by (4)
geometry::Rect::new	geometry.vl:6:16	Rect { w: w, h: h }
geometry::Rect::area	geometry.vl:10:14	self.w * self.h
main	main.vl:7:22	let lit = Rect { w: 1, h: 2 };
main	main.vl:8:8	(r.w + r.h + lit.area()) as i32
// std::window::objc::Rect.w	<std>:48501-48501	pub field
    pub w: f64,
// used by (5)
std::window::cocoa::view_size	<std>:46616:18	Size { w: (b.w * s + 0.5) as i64, h: (b.h * s + 0.5) as i64, scale: s }
std::window::cocoa::imp_first_rect	<std>:46975:39	return Rect { x: 0.0, y: 0.0, w: 0.0, h: 0.0 };
std::window::cocoa::imp_first_rect	<std>:46983:60	let local = Rect { x: d.ime_x / s, y: d.ime_y / s, w: d.ime_w / s, h: d.ime_h / s };
<std::window::cocoa::Cocoa as Backend>::open_window	<std>:47670:47	let rect = Rect { x: 0.0, y: 0.0, w: desc.w as f64, h: desc.h as f64 };
<std::window::cocoa::Cocoa as Backend>::open_window	<std>:47703:40	Rect { x: 0.0, y: 0.0, w: 0.0, h: 0.0 }, 0x01 | 0x02 | 0x80 | 0x200, view,
warning query.program-errors: 2 errors in the program; results may be incomplete
try: volec --diagnostics=short main.vl -c -o /dev/null
$ query context Rect.h
// crate::geometry::Rect.h	geometry.vl:1-2	pub field
#[derive(Clone, Copy)] #[sealed]
pub struct Rect { w: i64, pub h: i64 }
// used by (3)
geometry::Rect::new	geometry.vl:6:22	Rect { w: w, h: h }
geometry::Rect::area	geometry.vl:10:23	self.w * self.h
main	main.vl:8:14	(r.w + r.h + lit.area()) as i32
// std::window::objc::Rect.h	<std>:48502-48502	pub field
    pub h: f64,
// used by (5)
std::window::cocoa::view_size	<std>:46616:45	Size { w: (b.w * s + 0.5) as i64, h: (b.h * s + 0.5) as i64, scale: s }
std::window::cocoa::imp_first_rect	<std>:46975:47	return Rect { x: 0.0, y: 0.0, w: 0.0, h: 0.0 };
std::window::cocoa::imp_first_rect	<std>:46983:76	let local = Rect { x: d.ime_x / s, y: d.ime_y / s, w: d.ime_w / s, h: d.ime_h / s };
<std::window::cocoa::Cocoa as Backend>::open_window	<std>:47670:65	let rect = Rect { x: 0.0, y: 0.0, w: desc.w as f64, h: desc.h as f64 };
<std::window::cocoa::Cocoa as Backend>::open_window	<std>:47703:48	Rect { x: 0.0, y: 0.0, w: 0.0, h: 0.0 }, 0x01 | 0x02 | 0x80 | 0x200, view,
warning query.program-errors: 2 errors in the program; results may be incomplete
try: volec --diagnostics=short main.vl -c -o /dev/null
$ fix --only pub --dry-run
--- a/geometry.vl
+++ b/geometry.vl
@@ -2 +2 @@
-pub struct Rect { w: i64, pub h: i64 }
+pub struct Rect { pub w: i64, pub h: i64 }
$ fix --only pub
fixed 1 pub	geometry.vl	+1 -1 lines
## Then only the warning is left, and its fix.
$ check
geometry.vl:1:24: warning[attr.obsolete] '#[sealed]' is the default from 0.26: every field not marked 'pub' is private to its module | help: delete it (`volec fix --only obsolete-attr` deletes every one) | try: volec fix --only obsolete-attr main.vl
ok: 0 errors, 1 warning in main.vl (2 files, 0 shaders)
$ fix --only obsolete-attr
fixed 1 obsolete attribute	geometry.vl	+1 -1 lines
% cat geometry.vl
#[derive(Clone, Copy)]
pub struct Rect { pub w: i64, pub h: i64 }

impl Rect {
    pub fn new(w: i64, h: i64) -> Rect {
        Rect { w: w, h: h }
    }

    pub fn area(self) -> i64 {
        self.w * self.h
    }
}
$ check
ok: 0 errors in main.vl (2 files, 0 shaders)
$ explain field.private
field.private: error
(0.26.0) A field not marked `pub` is read, written or borrowed outside the module that declares its struct (and the modules inside it), Rust's E0616. A field marked `pub` is visible wherever its struct is; until 0.26 every field was.
fix: Call the struct's method when it has one of that name (`.len()`; the try: line writes the `()`); in your own program, mark the field `pub` where it is declared (`volec fix --only pub`). Std's fields change only through its methods. (0.26.2: a field marked `pub(crate)`, `pub(super)` or `pub(in path)` is visible up to that module; the message says where, and `fix --only pub` widens it to `pub(crate)`.)
example:
    error[field.private] field 'w' of 'Rect' is private to module 'geometry' | help: make it public: 'pub w: i64' at geometry.vl:1:19
$ explain field.literal-private
field.literal-private: error
(0.26.0) A struct literal outside the struct's module (and the modules inside it) names a field not marked `pub` (Rust's E0451): a struct with a private field is made by its module's functions, which keep what its fields mean. A struct with no fields has its literal anywhere.
fix: Call a function of the struct's module that returns one (the help names its constructors: `Rect::new`); or, in your own program, mark the fields `pub` (`volec fix --only pub`).
example:
    error[field.literal-private] cannot make a 'Rect' here: its field 'w' is private to module 'geometry' | help: make one with its constructor: 'Rect::new'
$ explain attr.obsolete
attr.obsolete: warning
(0.26.0) `#[sealed]` before a struct: from 0.26 every struct's fields not marked `pub` are private to its module (and the modules inside it), and its literals need every field visible, which is what `#[sealed]` asked for. The attribute is accepted and changes nothing.
fix: Delete it: `volec fix --only obsolete-attr` deletes every one.
example:
    warning[attr.obsolete] '#[sealed]' is the default from 0.26: every field not marked 'pub' is private to its module
