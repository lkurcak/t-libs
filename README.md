# t-libs

Libraries for [T](https://github.com/lkurcak/t-lang). Each is a package in
a directory of its own, which a dependent names as its `subdirectory`.
There's a hash map in `hashmap/`, a grid in `grid/`, a binary heap in
`heap/` and a directed graph in `graph/`. It's also an experiment: what writing a library's
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

- `Grid<T>`: `new` (for `T: Copy`), `from_fn` (any `T`, from `|x, y|
  ..`), `width`, `height`, `get`, `at`, `replace`, `set`, `cells` (row by
  row), `iter`, `x_of`, `y_of`, `copy`.
  It's `Discard`, `Send` and `Sync` when `T` is.

The cells are one list, row by row, and its invariant, `cells.len() ==
width * height`, is a refinement the checker proves every method keeps
(t 0.67.0+: products of two unknowns). So `get` and `set` take
coordinates the caller has proved inside the grid, `x < g.width()` and
`y < g.height()`, and never panic; `at` is the one that checks. Nothing in
it is `unsafe`, and nothing panics.

## The heap

```toml
heap = { git = "https://github.com/lkurcak/t-libs", rev = "<full commit hash>", subdirectory = "heap" }
```

```text
use heap::Heap;

let mut h = Heap::new();
h.push(3);
h.push(1);
h.pop()                                     // Some(1): least first
```

- `Heap<T>`: `new`, `from_list` (in linear time), `len`, `is_empty`,
  `peek`, `push`, `pop`, `into_sorted`, `as_slice`, `free_with`. Pushing
  and popping need `T: Ord`; tuples order by their first element, then
  the next, so `(cost, node)` pops the cheapest.

A binary heap in a list. The checker proves every index in moving a
value up or down the tree inside the list, so nothing in it panics, and
nothing is `unsafe`.

## The graph

```toml
graph = { git = "https://github.com/lkurcak/t-libs", rev = "<full commit hash>", subdirectory = "graph" }
```

```text
use graph::Graph;

let mut g = Graph::new();
let a = g.add_node("a");                    // nodes are 0, 1, ..
let b = g.add_node("b");
g.add_edge(a, b, 5);                        // a to b, costing 5
g.cheapest_path(a, b, |w| *w)               // Some((5, [0, 1]))
```

- `Graph<N, E>`: a directed graph with a value of type `N` on each node
  and of type `E` on each edge. `new`, `node_count`, `add_node`,
  `add_edge`, `node`, `node_mut`, `edges`, `free_with`.
- Searches: `breadth_first` (the nodes a node reaches, nearest first),
  `shortest_path` (fewest edges), `topo_order` (`None` if there's a
  cycle), and Dijkstra's `distances` and `cheapest_path`, with the cost
  of an edge from a closure.

A node is a number less than `node_count()`, and `add_node` says so of
the number it gives and that there's one more node after, so a graph is
built with no checks. Nodes aren't removed. It depends on `heap` (by
path, inside this repository). Nothing in it is `unsafe`, and nothing
panics. What T can't prove yet, that each edge goes to a node, is
checked again where it's used: FRICTION.md says where.

## Developing

`tests/run.sh` checks every package as CI does: `t check
--deny-warnings`, `t fmt --check`, and `t test` of its `tests/lib.t`, a
dependent by path whose `#[test]`s use the package as any dependent
would. CI installs a pinned `t`
release.
