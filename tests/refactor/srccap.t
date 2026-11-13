## (0.27.6) A source set that reaches the region reserved for it stops
## the compiler with an error (docs/design/src-buffer.md): never a null
## SRC, never a write past the reservation. VOLE_SRC_CAP sets the
## reservation for a run; std's sources pass 4,096 bytes.
% VOLE_SRC_CAP=4096 volec check main.vl
error: the sources pass the 4096 bytes reserved for them (VOLE_SRC_CAP)
[exit 1]
% volec check main.vl
ok: 0 errors in main.vl (1 file, 0 shaders)
