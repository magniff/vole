## (0.25.2.1) A name a module re-exports (`pub use types::{Color, Brush
## as Pen};`) is found through it, as a program writes it; `items` lists
## the re-exported names.
$ show paint::Color
// crate::paint::types::Color	reexport0252/paint/types.vl:1-5
/// A color, components in 0..1.
pub struct Color {
    pub r: f64,
    pub g: f64,
}
// 1 method (with their lines and whole contracts: query items crate::paint::types::Color)
pub fn grey(v: f64) -> Color
note query.reexport: paint::Color is crate::paint::types::Color, which crate::paint re-exports (`pub use`)
$ show paint::Color::grey
// crate::paint::types::Color::grey	reexport0252/paint/types.vl:8-10	effects: none
    pub fn grey(v: f64) -> Color {
        Color { r: v, g: v }
    }
note query.reexport: paint::Color::grey is crate::paint::types::Color::grey, which crate::paint re-exports (`pub use`)
$ def paint::Pen
crate::paint::types::Brush	reexport0252/paint/types.vl:13:12	struct	pub struct Brush
note query.alias: 'Pen' is an import alias in crate::paint, for crate::paint::types::Brush
$ items paint
# crate::paint	reexport0252/paint/mod.vl
1	mod	pub mod types
3	use	pub use Color = crate::paint::types::Color (struct)
3	use	pub use Pen = crate::paint::types::Brush (struct)
