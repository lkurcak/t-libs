# Friction log

What got in the way of writing a hash map library in T, with the code that
hit it. Each entry is labelled:

- **gap**: T should have it;
- **by design**: T leaves it out on purpose, and the entry says what that
  costs here;
- **unsure**: not clear which.

Positive findings, where something worked better than expected, are
labelled **works**. The log is evidence for t-lang's plans, not a design
for them.

Written against `t` 0.40.0; updated for 0.41.0, 0.42.0 and 0.43.0; the
grid's entries against 0.67.0, updated to 0.70.0.

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

## No tuples — unsure

Iterating gives `&Entry<K, V>` (`e.key`, `e.value`) and `iter_mut` an
`EntryMut { key: &K, value: &mut V }`, where Rust gives `(&K, &V)`. Named
fields read fine; it's two more exported types.

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

## What worked — works

- Nested closures capturing `&mut self`, through effect-polymorphic
  `free_with`, to move every entry into the new buckets when growing:
  `old.free_with(|b| b.free_with(|e| self.put(e)))`.
- Linear values in a generic container with no `unsafe`: `free_with` is
  how a map of them is used up, as for `List`.
- Separate checking: `t check lib.t` checks the library alone, with no
  `main`, and what it exports is what's live.
- The library needed no `unsafe` and no `with panic`: overflow of `len` is
  `out_of_memory()`, as in `List::push`.
