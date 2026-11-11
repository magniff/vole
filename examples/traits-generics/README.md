# traits-generics

A small geometry and units library and a program that uses it: traits
with default methods, generic functions with bounds, a trait with an
associated type, an iterator of the library's own, `#[derive]`d and
hand-written impls, operator overloading (`+ - * ==` and `<`), and
`From`/`Into` between units of length. The library is two modules,
`geometry.vl` and `units.vl`, loaded by `mod` lines in `main.vl`.

## Build and run

From this folder (with `volec` on your `PATH`, or `../../target/volec`):

```sh
volec main.vl -o traits-generics && ./traits-generics
```

Only `main.vl` is named: `mod geometry;` and `mod units;` load
`geometry.vl` and `units.vl` next to it.

## Expected output

```text
== vectors (operators, derive)
a + b = (2, 6), a - b = (4, 2), -a = (-3, -4)
a.dot(b) = 5, |a| = 5, a == b: false, a > b: true
debug: Vec2 { x: 3, y: 4 }
rotate a by 90: (-4, 3), by 180: (-3, -4)
rotating twice is a half turn: true, Mat2 { a: -1, b: 0, c: 0, d: -1 }
== sorting and hashing (derive(Ord, Hash))
sorted: (-3, 3) (0, 5) (0, 5) (2, 0) (2, 1)
distinct: 4, (0, 5) seen 2 times
largest point: Some(Vec2 { x: 2, y: 1 }), of nothing: None
== shapes (a trait, defaults, generics)
circle   area   12.57  perimeter  12.57
rect     area   12.00  perimeter  14.00
shape    area    6.00  perimeter  12.00
total area of the rects: 14.00
total area of everything: 30.57
stretched clone: area 12.0, the original: 6.0
Polygon { points: [Vec2 { x: 0, y: 0 }, Vec2 { x: 8, y: 0 }, Vec2 { x: 0, y: 3 }] }
== units (From, Into, an associated type)
5000.00 m is 16404.20 ft; 1063.00 ft is 324.00 m
taller than 300.00 m? true
difference: 4676.00 m, negated: -4676.00 m
two laps: 600.00 m, in metres already: 5324.00 m
diagonal   5.00 m
rect       12.00 m2
```

## How it works

**derive writes the routine impls.** One line gives `Vec2` structural
`==` (`PartialEq`, `Eq`), an order field by field (`PartialOrd`, `Ord`:
by `x`, then `y`, which is what `sort` and `<` use), a hash (so it can
be a `HashMap` key), Rust's Debug text, `.clone()`, and `Copy` (a plain
value: passing it leaves the original usable):

```tach
#[derive(PartialEq, Eq, PartialOrd, Ord, Hash, Debug, Clone, Copy)]
pub struct Vec2 { pub x: i64, pub y: i64 }
```

**Operators are traits.** `a + b` calls `Add::add`, `-a` calls
`Neg::neg`, `<` calls `PartialOrd::partial_cmp`. An impl names its
result type (`type Output`). `Mat2` implements `Mul` as the composition
of two linear maps, so `ROTATE_90 * ROTATE_90` is a half turn:

```tach
impl Add for Vec2 {
    type Output = Vec2;
    fn add(self, o: Vec2) -> Vec2 { Vec2 { x: self.x + o.x, y: self.y + o.y } }
}

impl Mul for Mat2 {
    type Output = Mat2;
    fn mul(self, o: Mat2) -> Mat2 { ... }
}
```

`Meters` has floating-point contents, and floats have no total order
(NaN compares with nothing), so it has `PartialEq` and `PartialOrd`
written by hand, not `Ord`: `partial_cmp` returns an
`Option<Ordering>`, and `==`, `<`, `<=`, `>`, `>=` follow from the two.

**A trait with default methods.** `Shape` requires `area` and
`perimeter`; `name` and `describe` have bodies that an impl may keep or
replace. `Circle` and `Rect` write their own `name`; `Polygon` keeps the
default, which is why the triangle prints as `shape`:

```tach
pub trait Shape {
    fn area(&self) -> f64;
    fn perimeter(&self) -> f64;
    fn name(&self) -> &'static str { "shape" }
    fn describe(&self) {
        println("{:<8} area {:>7.2}  perimeter {:>6.2}", self.name(), self.area(),
            self.perimeter());
    }
}
```

**Generic functions with bounds.** A bound says what the body may call;
each use with a new type compiles a copy for that type
(monomorphization), so there is no dynamic dispatch:

```tach
fn total_area<T: Shape>(shapes: &[T]) -> f64 {
    let mut total = 0.0;
    for s in shapes { total += s.area(); } // s: a reference to each element
    total
}

fn largest<T: Ord + Copy>(xs: &[T]) -> Option<T> { ... }
```

**No trait objects: an enum of the cases.** Vole has no `dyn Shape`.
A list of different shapes is an enum, and the enum implements the
trait by dispatching with `match`; `total_area(&shapes)` then works
on the mixed list as on the list of rectangles. (`A` is the allocator of
the polygon's `Vec`: a type that holds one names it.)

```tach
pub enum AnyShape<A: Allocator> { C(Circle), R(Rect), P(Polygon<A>) }

impl<A: Allocator> Shape for AnyShape<A> {
    fn area(&self) -> f64 {
        match self {
            AnyShape::C(c) => c.area(),
            AnyShape::R(r) => r.area(),
            AnyShape::P(p) => p.area(),
        }
    }
    ...
}
```

**An iterator in the library.** `Polygon::edges` returns an `Edges`,
whose `Item` is a pair of points; the area (the shoelace formula) and
the perimeter are then one chain each:

```tach
impl<'a> Iterator for Edges<'a> {
    type Item = (Vec2, Vec2);
    fn next(&mut self) -> Option<(Vec2, Vec2)> { ... }
}

fn perimeter(&self) -> f64 {
    self.edges().fold(0.0, |acc, (a, b)| acc + (b - a).length())
}
```

**A trait with an associated type.** What `measure` returns depends on
the type: a `Segment` measures to `Meters`, a `Rect` to `SquareMeters`.
A generic function names the result `T::Output`, and its `where` clause
says what the body needs of it: `{m}` needs `Display`.

```tach
pub trait Measured {
    type Output;
    fn measure(&self) -> Self::Output;
}

impl Measured for Segment {
    type Output = Meters;
    fn measure(&self) -> Meters { Meters { m: (self.b - self.a).length() } }
}

fn show<T: Measured>(label: &str, x: &T)
    where
        T::Output: Display,
{
    let m: T::Output = x.measure();
    println("{label:<10} {m}");
}
```

**Units with From and Into.** `Meters` and `Feet` are different types,
so they cannot be mixed by mistake; `From` converts between them, and
`Into` comes for free (`x.into()` is `Meters::from(x)` when a `Meters`
is expected). A bound `T: Into<Meters>` accepts any unit that converts,
`Meters` itself included:

```tach
impl From<Feet> for Meters {
    fn from(f: Feet) -> Meters { Meters { m: f.ft / FEET_PER_METER } }
}

pub fn total<T: Into<Meters> + Copy>(lengths: &[T]) -> Meters {
    let mut sum = Meters { m: 0.0 };
    for x in lengths {
        let m: Meters = (*x).into(); // Into needs the target type: here, the let's
        sum = sum + m;
    }
    sum
}
```

**Clone copies deeply.** `Polygon` holds a `Vec`, which owns its points:
assigning or passing the struct by value moves it (the old name cannot be used
again). The derived `clone` copies the vector's contents, so changing
the clone leaves the original as it was; each is freed when it goes out
of scope. `main` puts a clone of the triangle into the `shapes` array,
because it uses the triangle afterwards.

**Modules.** `main.vl` loads the library with `mod geometry;` and
`mod units;` and imports by name (`use geometry::{Shape, Vec2, ...}`);
items and a struct's fields are private unless `pub`. `geometry.vl` reaches its
sibling with `use crate::units::{Meters, SquareMeters};`.

**A little C.** The square root comes from C's `sqrt`, declared in an
`extern "C"` block. Calling C is `unsafe`, so the library wraps it in a
safe function once: `pub fn square_root(x: f64) -> f64 { unsafe { sqrt(x) } }`.

## Language features

- traits, default methods, operator traits, `impl PartialOrd` by hand: `volec guide traits`
- generic functions and bounds, monomorphization: `volec guide generics`
- associated types (`type Output;`, `T::Output`), `impl Iterator`: `volec guide traits`, `volec guide iterators`
- `#[derive(PartialEq, Eq, PartialOrd, Ord, Hash, Debug, Clone, Copy)]`, `impl Display`: `volec guide formatting`
- `From`/`Into` and `T: Into<U>` bounds: `volec guide conversions`
- modules, `mod`, `pub`, `use crate::...`: `volec guide modules`
- `const` values of struct type, `extern "C"`: `volec guide syntax`, `volec guide c-interop`

## Going further

- No `dyn Trait`: use generics, or an enum of the cases as `AnyShape`.
- Supertraits (`trait Shape: Display`), associated constants and
  `where` clauses are there, as in Rust.
- `impl Mul<f64> for Vec2` (an operator with another right-hand type)
  does not work yet: write a method (`scale(k)`).
