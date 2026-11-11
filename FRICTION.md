# Friction log

What got in the way of writing libraries in T, with the code that hit
it. Each entry is labelled:

- **gap**: T should have it;
- **by design**: T leaves it out on purpose, and the entry says what that
  costs here;
- **unsure**: not clear which.

Positive findings, where something worked better than expected, are
labelled **works**. The log is evidence for t-lang's plans, not a design
for them.

Written against `t` 0.40.0; updated for 0.41.0, 0.42.0 and 0.43.0; the
grid's entries against 0.67.0, updated to 0.70.0; the heap's and the
graph's against 0.74.0, updated to 0.75.0; `rand`'s and `term`'s against
0.77.0.

## Looking up `String` keys by `&str` — unsure

Rust does this with `Borrow<Q>`, and `get<Q: ?Sized>(&self, k: &Q) where
K: Borrow<Q>`. T has neither: a trait can't have type parameters yet
("a trait can't have type parameters (yet); its methods can"), and a type
parameter can't stand for `str` ("`str` can only be behind a shared
reference"). An associated type `type View = str;` fails for the same
reason.

What works is the other way round: a *probe* type that knows which keys
it's for.

```rust,ignore
export trait Probe: Copy {
    type Key;
    fn hash_with(self, h: &mut Hasher);
    fn is(self, key: &Self::Key) -> bool;
}
impl<'a, K: Hash + Eq> Probe for &'a K { type Key = K; .. }
impl<'a> Probe for &'a str { type Key = String; .. }
```

and `get<P: Probe<Key = K>>(&self, p: P)`. The two impls don't overlap (the
checker accepts them: `str` can't be a `K`), `ages.get("ada")` and
`m.get(&777)` both infer, the literal's type included. It's arguably
clearer than `Borrow` (one trait, says what it's for), but every library
that wants this will invent its own `Probe`.

**Half way in 0.73.0** (t-lang step 57, unsized parameters): a type
parameter declared `unsized Q` may stand for `str`, so `get<unsized Q>(&self,
k: &Q)` can be written. `K: Borrow<Q>` still can't: a trait can't have type
parameters yet. `Probe` stays until it can.

## `x % n < n` isn't proved for a variable `n` — fixed in 0.41.0

The bucket of a hash is `h % n`, and indexing needs `i < n`:

```rust,ignore
fn slot(h: u64, n: { n: usize | n > 0 }) -> { i: usize | i < n } {
    ((h & 0xffff_ffff) as usize) % n
}
// error: can't prove `i < n` for the result of `slot`
```

`%` by a variable isn't linear, so the solver knows nothing of it. But `0 <=
x % n < n` for `n > 0` (unsigned) is a fact the checker could add whenever
it sees `%`, as it does for `&`: the mask version, `& (n - 1)`, is proved,
and that's what the map uses, with a power of two of buckets.

Since 0.41.0 the checker knows what `%` by any divisor gives (t-lang step
28), so `h % n` proves `i < n`. The map keeps the mask, now with a comment
saying why: one `&` instead of a division, and `n` is always a power of
two (`grow` doubles it). What's still missing is saying so: `n & (n - 1)
== 0` isn't a fact T can state of a field, so the mask's correctness
rests on the comment.

## The map's invariant can't be stated — gap

`len` is the number of entries in all the buckets. T can't say so: a
field refinement can't sum over a list, and facts don't survive `&mut`
borrows anyway (step 21 deferred invariants across `&mut`). So taking a key
out can't prove `len > 0`:

```rust,ignore
// It has this key, so `len` is at least 1; but that's the map's
// invariant, which T can't state yet.
if self.len > 0 {
    self.len = self.len - 1;
}
```

The guard is dead code that hides a bug if the invariant ever breaks.

## Facts are forgotten at every `&mut` call — unsure

`insert` checks `len` can still count one more, then puts the entry in,
then adds one: the call in between forgets the check.

```rust,ignore
if self.len == greatest() { out_of_memory(); }
self.put(Entry { key, value });
self.len = self.len + 1;
// error: `+` may panic ... mutable lending invalidated facts about `(*self)`
```

Moving the check after `put` fixes it. `put` can't change `len`, but its
signature doesn't say so: knowing which fields a `&mut self` method writes
would need effects on places, or `put` taking `&mut self.buckets` instead
(which it can't, being a method).

Since 0.43.0 (t-lang step 30) it can say so: `put` is `ensures self.len()
== old(self.len())`, and `len` is a `#[measure]`, so the check can sit
before `put`. Not before `grow`, though, which can't say the same: it
moves the entries over with `old.free_with(|b| b.free_with(|e|
self.put(e)))`, and a closure that captures `self` makes `*self` a value
nothing's known of after each call, so `grow`'s body can't prove what it
would ensure. The check sits between them. Similar in `remove_entry`: `m ==
bucket.len()` is lost in a loop that lends `bucket`, so the loop compares
with `bucket.len()` each time instead.

## No `if let` — fixed in 0.41.0

Four places want "return early if it's there":

```rust,ignore
match self.get_mut(&key) {
    Option::Some(v) => return Option::Some(replace(v, value)),
    Option::None => {},
}
```

(tcalc's findings noted it too.)

Since 0.41.0 (t-lang step 28) they're `if let`, and the iterators'
"next bucket or stop" is a `let .. else`:

```rust,ignore
if let Option::Some(e) = self.bucket.next() {
    return Option::Some(e);
}
let Option::Some(b) = self.buckets.next() else { return Option::None };
self.bucket = b.iter();
```

Nothing surprising in porting: the borrow of `self.bucket` in the
`if let` ends where the arm does, as it did in the `match`.

## `insert` needs `K: Discard` — by design

When the key is there, the new key is thrown away (the old one stays, as
in Rust), so `insert` is in an `impl<K: Hash + Eq + Discard, V>`. A map of
linear keys can be built and used, but not inserted into. A linear-key
`insert` would have to give the key back: `Result<Option<V>, K>`, or an
`Entry`-returning `replace`. Linear values are fine: `insert` gives the
old value back, and the caller must use it up, which the demo's `Token`s
show.

## One `Hash` impl per integer type — fixed in 0.42.0

`impl<T: Int> Hash for T` would overlap with `impl Hash for String` (no
negative reasoning, so `String: Int` can't be ruled out), so it's ten
impls. And a signed integer's bits need a trick, as `as` doesn't
reinterpret and there's no `to_bits`:

```rust,ignore
fn bits(x: i64) -> u64 {
    if x < 0 { (-(x + 1)) as u64 | 0x8000_0000_0000_0000 } else { x as u64 }
}
```

Since 0.42.0 (t-lang step 29), `Int` is a `sealed` trait, which the
overlap check uses: no impl of `Int` is for `String`, and none can be
added, so the two impls don't overlap. And `core::num::wrap::<T, u64>`
gives any integer's two's complement bits. So it's one impl:

```rust,ignore
impl<T: Int> Hash for T {
    fn hash(&self, h: &mut Hasher) { h.u64(wrap(*self)) }
}
```

## No tuples — unsure (fixed in t 0.74.0)

Iterating gives `&Entry<K, V>` (`e.key`, `e.value`) and `iter_mut` an
`EntryMut { key: &K, value: &mut V }`, where Rust gives `(&K, &V)`. Named
fields read fine; it's two more exported types.

With tuples (t 0.74.0, step 58) the map gives what Rust's does: `iter`
gives `(&K, &V)`, `iter_mut` `(&K, &mut V)`, `remove_entry` an
`Option<(K, V)>` and `free_with` each `(K, V)`; `Entry` is private storage
and `EntryMut` is gone. `for (k, v) in m.iter()` and `|(k, v)| ..` take
them apart.

## The hash can't be keyed — by design

A keyed hash (SipHash with a random key, as Rust's `HashMap`) needs
randomness, which is I/O, which needs the `Os` (docs/19). A map could take
a key from its creator (`Map::with_key(k)`), and `std` could give one out
from `Os`. Until then keys from an adversary can be made to collide.

## No `t test` — fixed in 0.44.0

The tests are a dependent program in `tests/demo` (by path: `hashmap = {
path = "../.." }`), its output compared with `tests/expected.txt` by a
shell script, as tcalc does. Each check is a printed line and a `//`
comment saying what it should be, which nothing checks but the diff.

Since t 0.44.0 they're `#[test]`s in `tests/lib.t`, with `assert_eq`, and
`t test tests/lib.t` runs them; `t check --deny-warnings` replaced looking
at what `t check` printed.

## Named constants — fixed in 0.50.0

FNV-1a's offset basis and prime, and the first bucket count, were
literals in the code, with comments saying what they were. Since t 0.50.0
they're `const` items (`OFFSET`, `PRIME`, `FIRST`), worked out while
compiling.

## The grid: products of unknowns — fixed in 0.67.0

A grid stored row by row has the cell in column `x` of row `y` at `y *
width + x`, and its invariant is `cells.len() == width * height`: before
t 0.67.0 neither could be proved or even stated (t-nonograms' FRICTION.md,
"Two-dimensional indexing"). t-lang step 51 made products of two unknowns
part of the logic, and the grid is written the obvious way:

```rust,ignore
export struct Grid<T> {
    width: usize,
    height: usize,
    cells: { c: List<T> | c.len() == width * height },
}

export fn get(&self, x: { x: usize | x < self.width() }, y: { y: usize | y < self.height() }) -> &T {
    &self.cells[y * self.width + x]
}
```

`x_of(i)` and `y_of(i)`, `i % width` and `i / width`, are proved inside
the grid from `i < width * height` too, from what division now says.

## Writing a list that's a refined field — fixed in 0.67.0

`self.cells[i] = v` lends the list for as long as the `&mut T` lives,
which a refined field can't be. t 0.67.0 added `List::replace` and
`List::set`, which lend it for the call and say its length stays.

## A sub-slice can't be proved — fixed in 0.72.0

`row(y)` would be `&cells[y * width .. y * width + width]`, as a slice.
T had no range indexing, and `split_at` gave an `Option`, which said
nothing of how long the halves are. So the grid had no `row`; a
dependent copied a row out cell by cell.

t 0.72.0 added `s.slice(a..b)`, for a range proved in the slice, which
says how long what it gives is, and `split_at`'s halves say theirs. So
`Grid::row(y)` is `self.cells.slice(start..start + self.width)`, proved
from `y < height` and the grid's invariant, and `row(y)[x]` for `x <
width()` needs no check.

## Nested loops that write forget the size — fixed in 0.68.0

```rust,ignore
while y < g.height() {
    let mut x: usize = 0;
    while x < g.width() {
        g.set(x, y, v);
        x = x + 1;
    }
    y = y + 1;
}
```

The inner loop lends `g` to `set`, and up to 0.67.0 the checker forgot
at its head what it knew of `g`, the outer `y < g.height()` included, so
the inner condition had to say `&& y < g.height()` again. t 0.68.0's loop
frames keep a measure that every lend in the loop ensures unchanged, and
`set` ensures the width and height stay.

## `for x in 0..n` says nothing of `x` — fixed in 0.69.0

`Range`'s `next` gave an `Option<T>`, which couldn't say `x < n`, so in
`for x in 0..g.width()` the checker didn't know `x < g.width()` and
`g.get(x, y)` wasn't proved. Every proved loop over a grid was a
`while`. t 0.69.0's `next` gives an `Option<{ v: T | v < self.end() }>`
and keeps the end, so the tests' loops over a grid are `for`s.

## A grid of values that aren't `Copy` — fixed in 0.70.0

`Grid::new(width, height, fill)` copies `fill` into each cell, so `T:
Copy`. A `from_fn(width, height, |x, y| ..)` would make the rest, but
filling a list in a loop couldn't prove its length either (the loop
forgot), so it'd have needed the trick `List::filled` used: the list in a
struct whose refinement says how long it may grow.

t 0.70.0's loop invariants (t-lang step 54) say it, one loop per row:

```rust,ignore
while y < height invariant cells.len() == y * width && y <= height {
    let mut x: usize = 0;
    while x < width invariant cells.len() == y * width + x && x <= width {
        cells.push(f(x, y));
        x = x + 1;
    }
    y = y + 1;
}
```

and `from_fn` makes a grid of anything. (`List::filled` lost its trick
too.)

## `new` gives an `Option` that can't say how big — fixed in 0.69.0

```rust,ignore
let Some(mut g) = Grid::new(3, 2, 0u8) else { .. };
if g.width() == 3 && g.height() == 2 {   // to call get/set with literals
```

A refinement couldn't be inside an `Option`, so what `new` made had no
known size and the caller asked again. t 0.69.0 lets an enum's type
argument be a refinement: `new` gives an `Option<{ g: Grid<T> |
g.width() == width && g.height() == height }>`, and the tests no longer
ask.

## What's in a list can't be refined — fixed in 0.76.0

The graph's invariant is that every edge goes to a node: each edge's
target is less than `node_count()`. `add_edge` asks for that, so it's
proved when the edge goes in:

```rust,ignore
export fn add_edge(
    &mut self,
    from: { v: usize | v < self.node_count() },
    to: { v: usize | v < self.node_count() },
    value: E,
)
```

But the edges are a `List<(usize, E)>`, and a refinement can't be a
type argument of a `List` (t 0.69.0 allows one only in an enum's), so
what comes out is a `usize` nothing's known of. Every search reads
targets, and the BFS queue and Dijkstra's heap hold nodes, so each is
checked again where it's used, by a check that never fails:

```rust,ignore
fn node_id(&self, i: usize) -> Option<{ v: usize | v < self.node_count() }> {
    if i < self.nodes.len() { Some(i) } else { None }
}

for (to, _) in self.nodes[v].out.iter() {
    let Some(t) = self.node_id(*to) else { continue };   // never `continue`s
    if !seen[t] { .. }
}
```

Nine of those in `graph/lib.t`, and `walk_back` reads a parent with
`get`, and `topo_order` checks a count it knows is positive. A dependent
has it too: `for (t, _) in g.edges(v)` gives targets it can't pass to
`g.node(*t)` without a check. What's wanted is `List<({ t: usize | t <
n }, E)>`, a `Heap<(u64, { v: usize | v < n })>`, a queue of `List<{ v:
usize | v < n }>`, where `n` is the node count; and for the graph's own
field, a refinement that names the list it's in: every target in
`nodes` is less than `nodes.len()`.

t 0.76.0 lets any type argument be a refinement, kept by parametricity:
generic code can only keep and give back the values it's given, so
`List<{ t: usize | t < n }>`'s `push` takes, and its `index`, `pop` and
iterator give, numbers below `n`. The graph says so of its own field:

```rust,ignore
export struct Graph<N, E> { nodes: List<Node<N, E, { t: usize | t < nodes.len() }>> }
```

which `add_node` keeps (what was below the old count is below the new
one) and `add_edge` proves. `node_id` is gone; the queues are `List<{ v:
usize | v < n }>`, Dijkstra's heap a `Heap<(u64, { v: usize | v < n })>`
(`Ord` makes no values, so a refined type can be what it bounds), the
parents `List<Option<{ p: usize | p < n }>>`, and `walk_back` indexes
them. `edges`, `breadth_first` and `topo_order` give refined node numbers,
so a dependent can pass them back with no check. `topo_order` still checks
a count it knows is positive: that's a fact about how many edges are in
the lists, which no element's refinement says.

## Writing through `l[i]` forgets how long `l` is — fixed in 0.75.0

```rust,ignore
let mut l: List<u8> = List::filled(3, 0);
l[0] = 3;
l[1] = 4;
// error: can't prove `i < self.len()` for argument `i` of `index_mut`
// note: mutable lending invalidated facts about the previous value of `l`
```

`l[i] = v` is `*l.index_mut(i) = v`, and `index_mut`'s result borrows
the list, so the checker forgot everything about it, its length
included, though a `&mut u8` into the list can't change how long it is.
`List::set` lends the list only for the call and says the length stays,
so the graph's searches used it, `dist.set(t, ..)` for `dist[t] = ..`.

It was worse for a list of structs. `self.nodes[from].out.push(e)` had
the same problem (and the checker picked `index`, not `index_mut`, for a
method call's receiver: "cannot borrow `*a temporary` as mutable"), so
`add_edge` took the node out and put it back, each step lending the list
only for a call, with an `else { loop {} }` that never ran. A
dependent's `*g.node_mut(a) = x` forgot `node_count()` in the same way.

t 0.75.0 (t-lang step 59): a method whose result can write nothing but
values of its type parameters can say what stays, as `index_mut`,
`get_mut`, `iter_mut` and `as_mut_slice` now say the length does; and
`l[i].push(x)` is `index_mut`'s. So `add_edge` is one line,
`self.nodes[from].out.push((to, value))`, and `node_mut` says the node
count stays, which `node_values_change` in the tests uses.

## A postcondition can't say which variant — fixed in 0.75.0

`pop` gives `Some` exactly when there was something to pop, but neither
`List::pop` nor `Heap::pop` could say so: a refinement can call only
measures, and `is_some` wasn't one. So `while let Some(v) = h.pop()`
didn't know `h` got shorter.

Since t 0.75.0 `is_some` is a measure, and both `pop`s say `r.is_some()
== (old(self.len()) > 0)`. `into_sorted` still doesn't say how long its
list is, for another reason: what's left of the heap is used up by
`h.free_with(|v| sorted.push(v))` (a heap of linear values must be,
even when it's empty), and a closure that captures `sorted` makes the
checker forget its length everywhere in the function, not only after.

## `swap` takes indices it checks — fixed in 0.75.0

`List::swap(i, j)` and `<[T]>::swap` gave a `bool`, whether both were in
range, for any indices. The heap's are always proved, so it was `let _ =
self.items.swap(i, parent)`, three times in the heap and three in the
graph. Since t 0.75.0 `swap` asks for proved indices, as `l[i]` does, and
gives nothing.

## A variant's field can't be refined — fixed in t 0.81.0

`term`'s decoder, part way through a character in UTF-8, holds the
number so far, which has at most 15 bits before the next byte's 6 are
shifted in. The variant can't say so:

```rust,ignore
enum State { .., Utf8(u8, { c: u32 | c < 0x8000 }, u32) }
// a refinement can only be the whole type of a parameter, a result, a
// `let` or a struct's field
```

so `code << 6` isn't proved, and the shift masks first, to tell the
checker what it can't be told: `((code & 0x7FFF) << 6) | (b & 0x3F) as
u32`. docs/08.1 leaves refinements on variants out because "positional
fields have no names to name", but this one names nothing but itself, as
a type argument's refinement does (`Option<{ c: u32 | c < 0x8000 }>`
works since 0.76.0). A struct as the payload would do, at the cost of a
type for one field.

(Fixed in t 0.81.0: a variant's field can be refined, naming the fields
before it by their binders. Only the number's own bound wasn't enough:
`Utf8(left - 1, code, ..)` needs it in terms of `left`, `(left == 1 && c <
0x8000) || (left == 2 && c < 0x200) || (left == 3 && c < 8)`. The mask is
gone.)

## `read` and `Screen` can't be tested here — unsure

They take `std::io::Raw` and `Stdout`, which only `Os` gives, and a test
has no terminal. So `term`'s tests are the decoder's, from bytes, and the
games' `tests/terminal.py` play them on a pseudo-terminal. Taking a trait
instead would let a test fake a terminal, but `core::io` has `Read` and no
way to wait for input with a deadline, which escape alone needs.

## Random numbers and keys — works

- `below(n: { n | n > 0 }) -> { r | r < n }` with a rejection loop
  proves as the plain remainder did, and for small `n` gives the same
  numbers, so neither game's transcript changed.
- `chance` takes `{ p: u64 | p <= 100 }`; t-maze's `LOOPS`, a `const`, is
  proved to be.
- Char patterns and renamed imports make a game's key map one `match`:
  `use term::Key::{self as Pressed, Char, Ctrl}`, then
  `Pressed::Up | Char('k') => ..`, `Char('q') | Ctrl('c') | Pressed::Escape
  => Quit`.
- `#![warn(implicit_panics)]` in each library's root, with
  `--deny-warnings`, checks the README's "nothing in it panics"; only the
  shift above needed help.

## The heap — works

The heap is proved through and through: moving a value up the tree
(`(i - 1) / 2 < i`) and down it (`i < n / 2`, so the children `2 * i +
1` and `2 * i + 2` don't pass `n`), with loop invariants that the length
stays, and step 51's division facts. Tuples' derived `Ord` (t 0.74.0)
makes Dijkstra's `(cost, node)` entries one line, and a heap of linear
values works, as `free_with` uses them up.

## What worked — works

- Nested closures capturing `&mut self`, through effect-polymorphic
  `free_with`, to move every entry into the new buckets when growing:
  `old.free_with(|b| b.free_with(|e| self.put(e)))`.
- Linear values in a generic container with no `unsafe`: `free_with` is
  how a map of them is used up, as for `List`.
- Separate checking: `t check lib.t` checks the library alone, with no
  `main`, and what it exports is what's live.
- The library needed no `unsafe` and no `with panic`: overflow of `len` is
  `out_of_memory()`, as in `List::push`. The graph's in-degree count in
  `topo_order` is the same: there can't be more edges than memory holds.
- `add_node`'s result says it's a node, and its `ensures` that there's
  one more: a dependent builds a graph with no checks, and `add_edge`
  takes the numbers `add_node` gave.
