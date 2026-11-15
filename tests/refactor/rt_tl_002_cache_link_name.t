## RT-TL-2, fixed in 0.30.1: a C function is named by the symbol it links
## to, in the code cache's hash too (it hashed only that a link name was
## there). user() calls `#[link_name = "fa"] fn ext`. Built with the code cache,
## then the link_name changed to "fb" (x.c: fa adds 1, fb adds 1000) and
## built again from the same cache: the warm build must call fb, as a
## build without the cache does (0.30.0 printed 4: fa's old call).
## (stdout first, then stderr: the program's line, then `ok: built`.)
% VOLE_CACHE=$PWD/cc volec main.vl x.c --cache=on -o p0 && ./p0
4
ok: built p0
% sed -i.bak 's/"fa"/"fb"/' main.vl && VOLE_CACHE=$PWD/cc volec main.vl x.c --cache=on -o p1 && ./p1
1003
ok: built p1
% VOLE_CACHE=off volec main.vl x.c --no-cache -o p2 && ./p2
1003
ok: built p2
