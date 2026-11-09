//! Uses the heap as a dependent would: only what it exports. `t test
//! heap/tests/lib.t` runs each test.

use alloc::list::List;
use heap::Heap;

/// Least first, whatever order they went in.
#[test]
fn least_first() {
    let mut h = Heap::new();
    for v in [5u32, 1, 4, 1, 3, 9, 2, 6].iter() {
        h.push(*v);
    }
    assert_eq(&h.len(), &8);
    assert_eq(&h.peek(), &Some(&1));
    let mut out: List<u32> = List::new();
    while let Some(v) = h.pop() {
        out.push(v);
    }
    let want: [u32; 8] = [1, 1, 2, 3, 4, 5, 6, 9];
    assert_eq(&out.as_slice(), &want.as_slice());
    assert(h.is_empty());
    assert_eq(&h.pop(), &None);
}

/// `from_list` makes a heap of a list's values, in linear time.
#[test]
fn from_list() {
    let mut l: List<i64> = List::new();
    let mut x: i64 = 7;
    for _ in 0..100u32 {
        // A sequence that jumps about: 7, -18, ...
        x = (x * 37 + 11) % 101 - 50;
        l.push(x);
    }
    let h = Heap::from_list(l);
    assert_eq(&h.len(), &100);
    let sorted = h.into_sorted();
    assert_eq(&sorted.len(), &100);
    for i in 1..sorted.len() {
        assert(sorted[i - 1] <= sorted[i]);
    }
}

/// Pairs order by their first element, then their second: what Dijkstra's
/// algorithm keeps, the distance first.
#[test]
fn pairs() {
    let mut h = Heap::new();
    h.push((3u64, 'c'));
    h.push((1u64, 'b'));
    h.push((1u64, 'a'));
    h.push((2u64, 'z'));
    assert_eq(&h.pop(), &Some((1, 'a')));
    assert_eq(&h.pop(), &Some((1, 'b')));
    assert_eq(&h.pop(), &Some((2, 'z')));
    assert_eq(&h.pop(), &Some((3, 'c')));
    assert_eq(&h.pop(), &None);
}

/// A value that must be used up, not dropped.
#[derive(Eq, Ord, Debug)]
struct Job { priority: u8 }

fn finish(j: Job) -> u8 {
    let Job { priority } = j;
    priority
}

/// A heap of linear values: each popped value must be used up, and so must
/// what's left.
#[test]
fn linear_values() {
    let mut h = Heap::new();
    h.push(Job { priority: 2 });
    h.push(Job { priority: 0 });
    h.push(Job { priority: 1 });
    let Some(first) = h.pop() else { panic("three jobs") };
    assert_eq(&finish(first), &0);
    let mut rest: u32 = 0;
    h.free_with(|j| rest = rest + finish(j) as u32);
    assert_eq(&rest, &3);
}
