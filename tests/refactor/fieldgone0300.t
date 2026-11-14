## 0.30: a did-you-mean of a field is an exact fix only for a typo. The
## struct lost its field `entry_count` and its three uses stay: the
## nearest field left, `enum_count`, is another field, and `fix
## --suggested` made the program compile and mean something else (0.29:
## offered at six sites, by the check hook, after every edit). A field
## unknown at one site (`widht`) is a typo and is fixed.
$ check
main.vl:7:5: error[type error] struct 'Table' has no field 'entry_count' | help: did you mean 'enum_count'? | try: volec fix --suggested main.vl
main.vl:8:5: error[type error] struct 'Table' has no field 'entry_count' | help: did you mean 'enum_count'? | try: volec fix --suggested main.vl
main.vl:12:5: error[type error] struct 'Table' has no field 'entry_count' | help: did you mean 'enum_count'? | try: volec fix --suggested main.vl
main.vl:16:5: error[type error] struct 'Table' has no field 'widht' | help: did you mean 'width'? | try: volec fix --suggested main.vl
[exit 1]
$ fix --suggested --dry-run
--- a/main.vl
+++ b/main.vl
@@ -16 +16 @@
-    t.widht
+    t.width
note fix.refused: main.vl:7:5: not applied: `enum_count`: the field is unknown at 3 sites: one that was removed or renamed, not mistyped, and the name offered is another field (restore it, or `refactor field STRUCT --rename OLD NEW`)
note fix.refused: main.vl:8:5: not applied: `enum_count`: the field is unknown at 3 sites: one that was removed or renamed, not mistyped, and the name offered is another field (restore it, or `refactor field STRUCT --rename OLD NEW`)
note fix.refused: main.vl:12:5: not applied: `enum_count`: the field is unknown at 3 sites: one that was removed or renamed, not mistyped, and the name offered is another field (restore it, or `refactor field STRUCT --rename OLD NEW`)
$ fix --suggested
fixed 1 suggested fix	main.vl	+1 -1 lines
main.vl:7:5: error[type error] struct 'Table' has no field 'entry_count' | help: did you mean 'enum_count'? | try: volec fix --suggested main.vl
main.vl:8:5: error[type error] struct 'Table' has no field 'entry_count' | help: did you mean 'enum_count'? | try: volec fix --suggested main.vl
main.vl:12:5: error[type error] struct 'Table' has no field 'entry_count' | help: did you mean 'enum_count'? | try: volec fix --suggested main.vl
note fix.refused: main.vl:7:5: not applied: `enum_count`: the field is unknown at 3 sites: one that was removed or renamed, not mistyped, and the name offered is another field (restore it, or `refactor field STRUCT --rename OLD NEW`)
note fix.refused: main.vl:8:5: not applied: `enum_count`: the field is unknown at 3 sites: one that was removed or renamed, not mistyped, and the name offered is another field (restore it, or `refactor field STRUCT --rename OLD NEW`)
note fix.refused: main.vl:12:5: not applied: `enum_count`: the field is unknown at 3 sites: one that was removed or renamed, not mistyped, and the name offered is another field (restore it, or `refactor field STRUCT --rename OLD NEW`)
note fix.left: 3 errors left (above)
% git diff | grep '^[-+] '
-    t.widht
+    t.width
