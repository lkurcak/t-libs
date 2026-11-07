# t-libs

Libraries for [T](https://github.com/lkurcak/t-lang). For now there's one,
a hash map, as a package other T programs depend on; a grid and a graph
library are to come, each a package of its own here. It's also an experiment: what writing a library's
interface in T is like. What got in the way is in
[FRICTION.md](FRICTION.md).

```toml
# t.toml
[dependencies]
hashmap = { git = "https://github.com/lkurcak/t-libs", rev = "<full commit hash>" }
```

```text
use alloc::string::String;
use hashmap::Map;

let mut ages: Map<String, u8> = Map::new();
ages.insert(String::from("ada"), 36);   // with alloc
ages.get("ada")                         // Some(&36)
ages.remove("ada")                      // Some(36)
```

## What's in it

- `Map<K, V>`: `new`, `len`, `is_empty`, `get`, `get_mut`,
  `contains_key`, `insert`, `remove`, `remove_entry`, `iter`, `iter_mut`,
  `free_with`. A map is `Discard` when its keys and values are; a map of
  values that aren't is used up with `free_with`.
- `Hash` and `Hasher`: what keys are hashed by, FNV-1a over their bytes.
  The integers, `bool`, `char` and `String` have it; a type of your own
  needs an `impl Hash`, consistent with its `Eq`.
- `Probe`: what a map can be asked about. `&K` is a probe for keys of type
  `K`, and `&str` for `String` keys, so `ages.get("ada")` makes no
  `String`.

It's separate chaining over a power of two of buckets, which double when
there are as many keys as buckets. The hash isn't keyed, so keys chosen
by an adversary can share a bucket and make lookups slow.

Nothing in it is `unsafe`, and nothing panics: running out of memory is
`alloc`'s, as for any allocation.

## Developing

`tests/run.sh` checks it as CI does: `t check --deny-warnings`, `t fmt
--check`, and `t test` of `tests/lib.t`, a dependent by path whose
`#[test]`s use the map as any dependent would. CI installs a pinned `t`
release.
