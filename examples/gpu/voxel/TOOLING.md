# Voxel demo tooling log

A short running record of tool failures and API gaps encountered while building
this example. API limitations are separated from compiler/tool errors.

## Tool and diagnostic issues

- `volec guide --find indirect` returned unrelated architecture/optimizer text
  rather than an indirect-drawing answer. `volec guide --find index buffer` had
  no matching paragraph. Workaround: inspected `std::gpu` through compiler
  queries and the indexed/depth GPU test cases.

- During initial rendering, `BufferUsage::STORAGE` and
  `TextureUsage::RENDER_ATTACHMENT` failed to resolve when passed as standalone
  arguments through imported type names, while bitwise usage combinations
  resolved. `volec fix --suggested` provided direct-constant imports, which are
  used for those two cases.

- Metal's shader compiler rejected the WGSL helper name `quad` as a redefinition
  of a reserved Metal type. Renamed it `emit_quad`; the Vole/WGSL frontend had
  accepted the name, so this failure only appeared in the actual GPU build.

- The first compute dispatch stopped at `gpu.layout`: both compute entry
  pipelines reflected all six bindings in the shared WGSL module, including
  bindings unused by that entry. Both bind groups now supply the complete set.

- Adding vegetation initially produced `wgsl.name: unknown name 'plants'` in
  the shared render module: a second logical storage type had been referenced
  without a compatible binding. Terrain, water and vegetation now share the
  same 48-byte vertex record and three-binding render layout.

## Verified API constraints and workarounds

- `std::gpu` has no indirect draw or indirect dispatch API. GPU-generated mesh
  counts will therefore use bounded draws or small count readbacks, with any
  synchronization cost reported honestly.
- `std::window` has absolute mouse events but no relative-mouse/capture API.
  The camera will use drag-to-look with the existing event system.
- There is no polygon fill-mode/wireframe API. Geometry debugging will use a
  separate line-topology pipeline or shader debug view.
