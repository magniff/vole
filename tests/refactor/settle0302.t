## 0.30.2: `f(2)` of `f<T: Tr>(t: T) -> T::Out` is a variable standing for
## `<{integer} as Tr>::Out`, settled when the integer's type is known
## (infer::settle_deps). A use that gave it a type first is checked
## against the impl's then: rustc's E0271 at the call.
% VOLE_CACHE=off volec check let.vl 2>&1 | cut -c1-100
let.vl:27:13: error[type error] type mismatch resolving '<i32 as Tr>::Out == i32': the impl's type i
% VOLE_CACHE=off volec check strref.vl 2>&1 | cut -c1-100
strref.vl:27:19: error[type error] type mismatch resolving '<i32 as Tr>::Out == &str': the impl's ty
## settle: that check planted away (VOLE_PLANT_OBLIG, tests only), the
## rule before the fix: the i64 is read as an i32, and a u64 as a &str.
% VOLE_PLANT_OBLIG=settle VOLE_CACHE=off volec let.vl -o l && ./l
1705032704
ok: built l
% VOLE_PLANT_OBLIG=settle VOLE_CACHE=off volec check strref.vl 2>&1 | cut -c1-100
ok: 0 errors in strref.vl (1 file, 0 shaders)
## A value of such a variable whose type is needed before it is known
## (`f(2) == 1i32`) is rustc's E0282 at the call:
% VOLE_CACHE=off volec check cmp.vl 2>&1 | cut -c1-100
cmp.vl:28:13: error[type.infer] type annotations needed: this value's type is not known where it is 
## unknown: that error planted away, the statement is left out of the
## program with nothing said (only `a` is printed):
% VOLE_PLANT_OBLIG=unknown VOLE_CACHE=off volec cmp.vl -o c && ./c
a
ok: built c
