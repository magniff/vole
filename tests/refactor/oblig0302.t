## 0.30.2, the obligation engine (docs/design/obligations.md §11): a
## limit or an ambiguity is an error that says so, never a yes and never
## "not implemented". A chain of 140 impls is past the depth limit: the
## front says so, trait.overflow (rustc E0275).
% VOLE_CACHE=off volec check overflow.vl 2>&1 | cut -c1-120
overflow.vl:11:9: error[trait.overflow] 'W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W<W
## The places' two guards are behind the front's checks: no program
## reaches them. VOLE_PLANT_OBLIG (tests only) plants a fault for each,
## which each must catch. A three-impl chain the front proves builds:
% VOLE_CACHE=off volec depth.vl -o d && ./d
10
ok: built d
## depth: the places' limit lowered to 2; the same chain is trait.overflow
## there:
% VOLE_PLANT_OBLIG=depth VOLE_CACHE=off volec check depth.vl 2>&1 | cut -c1-120
depth.vl:14:19: error[trait.overflow] 'R: Tr' is not proved: the impls that would prove it need it again, deeper than 32
## Two impls of Tr for W<'a> are refused by coherence:
% VOLE_CACHE=off volec check overlap.vl 2>&1 | cut -c1-120
overlap.vl:9:1: error[trait.overlap] conflicting impls of trait 'Tr': this impl and an earlier one apply to the same typ
## overlap: coherence's error planted away, the places do not pick one of
## the two impls: trait.ambiguous.
% VOLE_PLANT_OBLIG=overlap VOLE_CACHE=off volec check overlap.vl 2>&1 | cut -c1-120
overlap.vl:14:19: error[trait.ambiguous] 'W: Tr' is proved by more than one impl, and which one is meant is not known | 
## The places normalize a projection through the impl select chose, and
## the impl's own projections again (Zip's `type Item = (A::Item,
## B::Item)`): `I: Iterator<Item = (X, Y)>` keeps X and Y apart, so w may
## be dropped while a result of X lives:
% VOLE_CACHE=off volec zip.vl -o z && ./z
Some(1000)
ok: built z
## nonest: the impl's own projections not normalized, every region of
## Zip's one (B_TIED): the same program is refused, more than rustc
## refuses, never less:
% VOLE_PLANT_OBLIG=nonest VOLE_CACHE=off volec check zip.vl 2>&1 | cut -c1-80
zip.vl:14:10: error[borrowck.move_borrowed] cannot move out of 'w' because it is
## A result of `I::Item` keeps what I borrows (rustc E0505):
% VOLE_CACHE=off volec check zipuaf.vl 2>&1 | cut -c1-80
zipuaf.vl:14:10: error[borrowck.move_borrowed] cannot move out of 'v' because it
## nonest: still refused, by the fallback that makes the base's regions
## one:
% VOLE_PLANT_OBLIG=nonest VOLE_CACHE=off volec check zipuaf.vl 2>&1 | cut -c1-80
zipuaf.vl:14:10: error[borrowck.move_borrowed] cannot move out of 'v' because it
## untied: that fallback planted away, the use after free is accepted:
## the fallback is what refuses it.
% VOLE_PLANT_OBLIG=untied VOLE_CACHE=off volec check zipuaf.vl 2>&1 | cut -c1-80
ok: 0 errors in zipuaf.vl (1 file, 0 shaders)
## Any other value is refused.
% VOLE_PLANT_OBLIG=x VOLE_CACHE=off volec check depth.vl 2>&1 | cut -c1-120
error: VOLE_PLANT_OBLIG is depth, overlap, nonest or untied
