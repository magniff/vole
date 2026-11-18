## 0.30.2, RT-466 and RT-47: a limit is an error, never a yes. A stack
## frame's size grows through one checked function (frame_grow): three
## locals of 2^62 bytes, whose sum wrapped, are refused at the first that
## reaches the limit, at every level.
% VOLE_CACHE=off volec wrap.vl -O0 -o w 2>&1 | cut -c1-100
wrap.vl:5:13: error[frame.too_big] the stack frame of 'three' reaches 2^62 bytes with this value of 
% VOLE_CACHE=off volec wrap.vl -O2 -o w 2>&1 | cut -c1-100
wrap.vl:5:13: error[frame.too_big] the stack frame of 'three' reaches 2^62 bytes with this value of 
## A frame under the limit is built:
% VOLE_CACHE=off volec fits.vl -o f && ./f
ok
ok: built f
## VOLE_PLANT_LIMIT (tests only) plants a fault for each check, which the
## cases must catch. frame: frame_grow adds unchecked, as before; the
## frame wraps and the program is built, its slots above sp.
% VOLE_PLANT_LIMIT=frame VOLE_CACHE=off volec wrap.vl -O2 -o w 2>&1 | cut -c1-100
ok: built w
## main's signature is checked against its forms: a Vec parameter, which
## read argc and argv as its header, is main.signature (rustc E0580).
% VOLE_CACHE=off volec check vecmain.vl 2>&1 | cut -c1-100
vecmain.vl:2:9: error[main.signature] 'main' takes no parameter, 'gpa: Gpa', or 'argc: i32, argv: *m
## C's form, argc an i32, argv's pointers `*const`, the allocator last:
% VOLE_CACHE=off volec forms.vl -o m && ./m one two
3
ok: built m
## main: the check planted away, the Vec parameter is accepted again.
% VOLE_PLANT_LIMIT=main VOLE_CACHE=off volec check vecmain.vl 2>&1 | cut -c1-100
ok: 0 errors in vecmain.vl (1 file, 0 shaders)
## Any other value is refused.
% VOLE_PLANT_LIMIT=x VOLE_CACHE=off volec check forms.vl 2>&1
error: VOLE_PLANT_LIMIT is frame or main
[exit 1]
