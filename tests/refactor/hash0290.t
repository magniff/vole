## hash.default (0.29.0; tests/refactor/hash0290/): std's HashMap and
## HashSet have no default hasher, as they have no default allocator; a
## type argument left out for a parameter bounded by BuildHasher (the
## program's own `Cache<K, A, S>` too) is the error, and its fix writes
## `FixedState` (in the prelude, as `Gpa`: no `use` is written), or the
## hasher parameter of the generic item it is in (`same`'s `S`); with
## two hasher parameters (`pick`) there is no fix. When the allocator is
## left out too (`bare`), the hasher's error has no fix of its own (both
## insert at the same place): alloc.default's is written first, and the
## hasher's after it by the same `fix --suggested`. A turbofish names the
## hasher as a type does (`HashSet::<i64, Gpa, FixedState>::new_in`).
$ check
main.vl:5:13: error[hash.default] 'HashMap' names no hasher: its 'S' is written, last | help: the hasher is part of the type: `FixedState` (in the prelude, the one `HashMap::new_in` makes), or a generic `S: BuildHasher` | try: volec fix --suggested main.vl
main.vl:9:13: error[alloc.default] 'HashMap' names no allocator: its 'A' is written, last | help: the allocator is part of the type: `Gpa` (the type of main's `gpa`), or a generic `A: Allocator` | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:9:13: error[hash.default] 'HashMap' names no hasher: its 'S' is written, last | help: the hasher is part of the type: `FixedState` (in the prelude, the one `HashMap::new_in` makes), or a generic `S: BuildHasher`; its fix comes after the allocator's
main.vl:9:36: error[alloc.default] 'HashSet' names no allocator: its 'A' is written, last | help: the allocator is part of the type: `Gpa` (the type of main's `gpa`), or a generic `A: Allocator` | try: volec fix --only alloc main.vl | try: volec fix --suggested main.vl
main.vl:9:36: error[hash.default] 'HashSet' names no hasher: its 'S' is written, last | help: the hasher is part of the type: `FixedState` (in the prelude, the one `HashMap::new_in` makes), or a generic `S: BuildHasher`; its fix comes after the allocator's
main.vl:13:55: error[hash.default] 'HashSet' names no hasher: its 'S' is written, last | help: this item is generic over the hasher 'S': write it (`, S`, the fix), or `FixedState` | try: volec fix --suggested main.vl
main.vl:18:9: error[hash.default] 'HashSet' names no hasher: its 'S' is written, last | help: this item is generic over the hashers 'S' and 'T': write the one this 'HashSet' hashes with as its last type argument (`, S`); no fix chooses between them
main.vl:27:14: error[hash.default] 'Cache' names no hasher: its 'S' is written, last | help: the hasher is part of the type: `FixedState` (in the prelude, the one `HashMap::new_in` makes), or a generic `S: BuildHasher` | try: volec fix --suggested main.vl
main.vl:32:16: error[hash.default] 'HashMap' names no hasher: its 'S' is written, last | help: the hasher is part of the type: `FixedState` (in the prelude, the one `HashMap::new_in` makes), or a generic `S: BuildHasher` | try: volec fix --suggested main.vl
main.vl:34:17: error[hash.default] 'HashSet' names no hasher: its 'S' is written, last | help: the hasher is part of the type: `FixedState` (in the prelude, the one `HashMap::new_in` makes), or a generic `S: BuildHasher` | try: volec fix --suggested main.vl
main.vl:36:12: error[hash.default] 'HashSet' names no hasher: its 'S' is written, last | help: the hasher is part of the type: `FixedState` (in the prelude, the one `HashMap::new_in` makes), or a generic `S: BuildHasher` | try: volec fix --suggested main.vl
main.vl:37:12: error[hash.default] 'Cache' names no hasher: its 'S' is written, last | help: the hasher is part of the type: `FixedState` (in the prelude, the one `HashMap::new_in` makes), or a generic `S: BuildHasher` | try: volec fix --suggested main.vl
[exit 1]
$ fix --suggested
fixed 11 suggested fixes	main.vl	+8 -8 lines
main.vl:18:9: error[hash.default] 'HashSet' names no hasher: its 'S' is written, last | help: this item is generic over the hashers 'S' and 'T': write the one this 'HashSet' hashes with as its last type argument (`, S`); no fix chooses between them
note fix.left: 1 error left (above)
$ fix --suggested
note fix.none: nothing to fix
% cat main.vl
use std::alloc::Allocator;
use std::collections::{HashMap, HashSet};
use std::hash::BuildHasher;

fn keys(m: &HashMap<i64, i64, Gpa, FixedState>) -> usize {
    m.len()
}

fn bare(m: &HashMap<i64, i64, Gpa, FixedState>, s: &HashSet<i64, Gpa, FixedState>) -> usize {
    m.len() + s.len()
}

fn same<S: BuildHasher>(a: &HashSet<i64, Gpa, S>, b: &HashSet<i64, Gpa, S>) -> usize {
    a.len() + b.len()
}

fn pick<S: BuildHasher, T: BuildHasher>(a: &HashSet<i64, Gpa, S>, b: &HashSet<i64, Gpa, T>,
    c: &HashSet<i64, Gpa>) -> usize {
    a.len() + b.len() + c.len()
}

struct Cache<K, A: Allocator, S: BuildHasher> {
    slots: Vec<K, A>,
    hasher: S,
}

fn slots(c: &Cache<i64, Gpa, FixedState>) -> usize {
    c.slots.len()
}

fn main(gpa: Gpa) {
    let mut m: HashMap<i64, i64, Gpa, FixedState> = HashMap::new_in(gpa);
    m.insert(1, 2);
    let mut s = HashSet::<i64, Gpa, FixedState>::new_in(gpa);
    s.insert(3);
    let t: HashSet<i64, Gpa, FixedState> = HashSet::with_capacity_in(4, gpa);
    let c: Cache<i64, Gpa, FixedState> = Cache {
        slots: Vec::new_in(gpa), hasher: std::hash::FixedState::new(),
    };
    println("{} {} {} {}", keys(&m), same(&s, &t), pick(&s, &t, &t), slots(&c));
    println("{}", bare(&m, &s));
}
$ explain hash.default
hash.default: error
(0.29.0) A HashMap or HashSet written without its hasher type, `HashMap<K, V, Gpa>`: the hasher is the type's last parameter and, as the allocator, has no default, so a map's type says how its keys are hashed. So for any type whose last parameters are bounded by std's BuildHasher (`struct Cache<K, A: Allocator, S: BuildHasher>`).
fix: Write the hasher: `HashMap<K, V, Gpa, FixedState>` (in the prelude, as `Gpa`: foldhash with a fixed seed, the default until 0.28.0 and what `HashMap::new_in` and `with_capacity_in` make), another BuildHasher (`SipHashState`, with `HashMap::with_hasher_in(h, gpa)`), or the hasher parameter of a generic item. `volec fix --suggested` writes FixedState; in an item generic over one hasher it writes that parameter, and in one generic over two it writes nothing: the help names them. When the allocator is left out too, its error (alloc.default) is fixed first.
example:
    use std::collections::HashMap;
    
    fn keys(m: &HashMap<i64, i64, Gpa>) -> usize { m.len() }
    
    fn main() {}
    
    main.vl:3:13: error[hash.default] 'HashMap' names no hasher: its 'S' is written, last
      help: the hasher is part of the type: `FixedState` (in the prelude, the one `HashMap::new_in` makes), or a generic `S: BuildHasher`
      try: volec fix --suggested main.vl
