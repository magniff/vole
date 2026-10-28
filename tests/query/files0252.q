## (0.25.2.2) `FILE.vl::item`: the item of that file's module, or one
## written in that file (an impl of another module's type); the 0.25.2.1
## eval's `show sim.vl::Sim::snapshot_in` found nothing.
$ show shapes.vl::Square::area
// crate::shapes::Square::area	files0252/shapes.vl:6-8	effects: none
    pub fn area(self) -> i64 {
        self.side * self.side
    }
$ show draw.vl::Square::outline
// crate::shapes::Square::outline	files0252/draw.vl:14-16	effects: none
    pub fn outline(self) -> i64 {
        4 * self.side
    }
$ show nofile.vl::Square::area
error query.no-match: no definition 'nofile.vl::Square::area'
try: volec query show crate::shapes::Square::area
[exit 1]
## A name through a module's `use`: draw imports Square.
$ show draw::Square::outline
// crate::shapes::Square::outline	files0252/draw.vl:14-16	effects: none
    pub fn outline(self) -> i64 {
        4 * self.side
    }
note query.reexport: draw::Square::outline is crate::shapes::Square::outline, which crate::draw imports (`use`)
## A trait impl's function by its type's path (`impl Render<Square> for
## Square`, a generic trait: its type was `Square`, not its path).
$ show crate::shapes::Square::render
// <crate::shapes::Square as crate::draw::Render>::render	files0252/draw.vl:8-10	effects: none
    fn render(self) -> i64 {
        self.area()
    }
