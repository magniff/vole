## 0.30: an internal failure of the checker names the item it was
## checking, with its position, under the message (0.29's only blocker
## was `error: IntVec::get: index out of range` and nothing else: it
## cost a bisect of the tree). VOLE_PLANT_CHECK_DIE=NAME is the tests'
## switch: the check of the function shown as NAME dies.
% VOLE_PLANT_CHECK_DIE=helper volec check
error: internal: a planted failure of the checker (VOLE_PLANT_CHECK_DIE)
  while checking helper (main.vl:1)
[exit 1]
% VOLE_PLANT_CHECK_DIE=P::twice volec check
error: internal: a planted failure of the checker (VOLE_PLANT_CHECK_DIE)
  while checking P::twice (main.vl:10)
[exit 1]
## The queries die the same way, and say where.
% VOLE_PLANT_CHECK_DIE=helper volec query refs helper --count
error: internal: a planted failure of the checker (VOLE_PLANT_CHECK_DIE)
  while checking helper (main.vl:1)
[exit 1]
## Without it nothing is said.
$ check
ok: 0 errors in main.vl (1 file, 0 shaders)
