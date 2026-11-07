# t-libs

Libraries for [T](https://github.com/lkurcak/t-lang). Each is a package in
a directory of its own, which a dependent names as its `subdirectory`.
There's a hash map in `hashmap/` and a grid in `grid/`; a graph is to
come. It's also an experiment: what writing a library's
interface in T is like. What got in the way is in
[FRICTION.md](FRICTION.md).

```toml
# t.toml
[dependencies]
hashmap = { git = "https://github.com/lkurcak/t-libs", rev = "<full commit hash>", subdirectory = "hashmap" }
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

## The grid

```toml
grid = { git = "https://github.com/lkurcak/t-libs", rev = "<full commit hash>", subdirectory = "grid" }
```

```text
use grid::Grid;

let mut g = Grid::new(3, 2, 0u8).unwrap();   // 3 wide, 2 high; None if too big
if g.width() == 3 && g.height() == 2 {
    g.set(2, 1, 7);                          // column 2 of row 1
    g.get(2, 1)                              // &7
}
g.at(5, 5)                                   // None: outside
```

- `Grid<T>`: `new` (for `T: Copy`), `width`, `height`, `get`, `at`,
  `replace`, `set`, `cells` (row by row), `iter`, `x_of`, `y_of`, `copy`.
  It's `Discard`, `Send` and `Sync` when `T` is.

The cells are one list, row by row, and its invariant, `cells.len() ==
width * height`, is a refinement the checker proves every method keeps
(t 0.67.0+: products of two unknowns). So `get` and `set` take
coordinates the caller has proved inside the grid, `x < g.width()` and
`y < g.height()`, and never panic; `at` is the one that checks. Nothing in
it is `unsafe`, and nothing panics.

## Developing

`tests/run.sh` checks every package as CI does: `t check
--deny-warnings`, `t fmt --check`, and `t test` of its `tests/lib.t`, a
dependent by path whose `#[test]`s use the package as any dependent
would. CI installs a pinned `t`
release.
