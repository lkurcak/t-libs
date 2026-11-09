//! A binary heap: a priority queue that gives back its least value first.
//!
//! ```text
//! let mut h = Heap::new();
//! h.push(3);
//! h.push(1);
//! h.push(2);
//! h.pop()   // Some(1)
//! ```
//!
//! The values are a list in which each one's parent, the value at `(i - 1)
//! / 2`, is no greater than it, so the least is at the front. `push` and
//! `pop` restore that by moving one value up or down the tree, so each
//! takes time logarithmic in how many there are.

use alloc::list::List;

/// Values of type `T`, the least of them first.
#[derive(Discard where T: Discard, Send where T: Send, Sync where T: Sync)]
export struct Heap<T> { items: List<T> }

impl<T> Heap<T> {
    /// An empty heap.
    export fn new() -> { h: Heap<T> | h.len() == 0 } { Heap { items: List::new() } }

    /// How many values it holds.
    #[measure]
    export fn len(&self) -> usize { self.items.len() }

    /// Is it empty?
    export fn is_empty(&self) -> bool { self.items.len() == 0 }

    /// The least value, or `None` if it's empty.
    export fn peek(&self) -> Option<&T> { self.items.first() }

    /// Each value, in no particular order.
    export fn as_slice(&self) -> { s: &[T] | s.len() == self.len() } { self.items.as_slice() }

    /// Gives each value, in no particular order, to `f`.
    export fn free_with<effect e, F: FnMut(T) with e + Discard>(self, f: F) with e {
        self.items.free_with(f)
    }
}

impl<T: Ord> Heap<T> {
    /// A heap of the values in `items`, in time linear in how many there
    /// are.
    export fn from_list(items: List<T>) -> { h: Heap<T> | h.len() == items.len() } {
        let mut h = Heap { items };
        let mut i = h.items.len() / 2;
        while i > 0 invariant i <= h.items.len() {
            i = i - 1;
            h.down(i);
        }
        h
    }

    /// Adds `v`.
    export fn push(&mut self, v: T) with alloc ensures self.len() == old(self.len()) + 1 {
        self.items.push(v);
        self.up(self.items.len() - 1);
    }

    /// Takes the least value out, or gives `None` if it's empty.
    export fn pop(&mut self) -> { r: Option<T> | r.is_some() == (old(self.len()) > 0) }
    ensures
        self.len() + 1 == old(self.len()) || (self.len() == 0 && old(self.len()) == 0),
    {
        let n = self.items.len();
        if n == 0 {
            return None;
        }
        self.items.swap(0, n - 1);
        let least = self.items.pop();
        self.down(0);
        least
    }

    /// Each value, least first.
    export fn into_sorted(self) -> List<T> with alloc {
        let mut h = self;
        let mut sorted = List::with_capacity(h.items.len());
        while let Some(v) = h.pop() {
            sorted.push(v);
        }
        // `h` is empty now, and the checker knows it (t 0.75.0), but a heap
        // of values that may be linear is used up all the same: with
        // nothing. The closure captures `sorted`, so the checker forgets
        // its length everywhere here, which is why the result isn't
        // refined (FRICTION.md).
        h.free_with(|v| sorted.push(v));
        sorted
    }

    /// Moves the value at `i` towards the front, past each parent greater
    /// than it.
    fn up(&mut self, i: { i: usize | i < self.len() }) ensures self.len() == old(self.len()) {
        let mut i = i;
        while i > 0 invariant i < self.items.len() {
            let parent = (i - 1) / 2;
            if self.items[i] < self.items[parent] {
                self.items.swap(i, parent);
                i = parent;
            } else {
                break;
            }
        }
    }

    /// Moves the value at `i` towards the back, past each child less than
    /// it.
    fn down(&mut self, i: usize) ensures self.len() == old(self.len()) {
        let n = self.items.len();
        let mut i = i;
        // The children of `i` are at `2 * i + 1` and `2 * i + 2`: `i < n /
        // 2` says the first is there.
        while i < n / 2 invariant n == self.items.len() {
            let left = 2 * i + 1;
            let right = left + 1;
            let child = if right < n && self.items[right] < self.items[left] {
                right
            } else {
                left
            };
            if self.items[child] < self.items[i] {
                self.items.swap(i, child);
                i = child;
            } else {
                break;
            }
        }
    }
}
