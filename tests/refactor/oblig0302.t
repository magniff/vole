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
## Any other value is refused.
% VOLE_PLANT_OBLIG=x VOLE_CACHE=off volec check depth.vl 2>&1 | cut -c1-120
error: VOLE_PLANT_OBLIG is depth or overlap
