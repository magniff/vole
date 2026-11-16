## XFAIL: RT-63: rewrite moves or drops holes whose expressions have effects: their order and their effects change (0.30.2)
## `rewrite 'order($a, $b)' 'order2($b, $a)'` writes $b before $a at
## `order(bump(&mut d), bump(&mut d))` and `order({ d += 1; d }, { d += 2; d })`:
## the arguments now run in the other order, and the program checks and
## prints `21 54 5 5` instead of `12 35 5 6`. `rewrite 'first($a, $b)' '$a'`
## leaves $b out and drops its effect (d
## is not bumped). RT-TL-10 is the hole used twice; this is the hole moved
## or left out. A replacement must keep the holes with effects in their
## order, once each (or bind them: `{ let a = ..; let b = ..; .. }`), or
## the site is refused, as for RT-TL-10.
$ run
12 35 5 6
$ rewrite 'order($a, $b)' 'order2($b, $a)'
error rewrite.effects: main.vl:20:13: the replacement puts $b before $a and they matched `bump(&mut d)` and `bump(&mut d)`, which have effects; nothing written
[exit 1]
$ rewrite 'first($a, $b)' '$a'
error rewrite.effects: main.vl:22:13: the replacement leaves out $b and it matched `bump(&mut d)`, which has effects; nothing written
[exit 1]
$ run
12 35 5 6
