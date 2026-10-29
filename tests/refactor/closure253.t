## (0.25.3) A closure's by-value parameter is dropped at the end of its
## body (a leak before): called once, many times, stored, through an
## FnMut(sink T) bound, and given owned items by map, filter, for_each,
## fold and Option::map; #[test]s run with --check-alloc, a leak fails.
$ test --timeout 20
test main.vl: 6 passed (6 #[test]; -O0 and -O2 agree)
