//! A hash map: keys, each with a value, found by the keys' hashes.
//!
//! ```text
//! let mut ages: Map<String, u8> = Map::new();
//! ages.insert(String::from("ada"), 36);
//! ages.get("ada") // Some(&36)
//! ```
//!
//! A map is a list of buckets, a power of two of them, and each key is in
//! the bucket its hash picks. When there are as many keys as buckets, it
//! has twice as many buckets, and puts each key in its new one.

mod hash;

export use hash::{Hash, Hasher, Probe};

use alloc::list::List;
use alloc::raw::out_of_memory;
use core::mem::replace;
use core::num::greatest;

/// A key and its value.
#[derive(Discard, Send, Sync)]
export struct Entry<K, V> { export key: K, export value: V }

/// A key and its value, as iterating with `iter_mut` gives them: the value
/// can be changed, the key can't.
#[derive(Discard, Send, Sync)]
export struct EntryMut<'a, K, V> { export key: &'a K, export value: &'a mut V }

/// Keys of type `K`, each with a value of type `V`.
#[derive(
    Discard where K: Discard, V: Discard,
    Send where K: Send, V: Send,
    Sync where K: Sync, V: Sync,
)]
export struct Map<K, V> { buckets: List<List<Entry<K, V>>>, len: usize }

/// How many buckets a map has once it has any.
const FIRST: usize = 8;

impl<K, V> Map<K, V> {
    /// A map with no keys, which has allocated nothing.
    export fn new() -> { m: Map<K, V> | m.len() == 0 } { Map { buckets: List::new(), len: 0 } }

    /// How many keys it has. It's a measure, so refinements can say it.
    #[measure]
    export fn len(&self) -> usize { self.len }

    /// Does it have no keys?
    #[measure]
    export fn is_empty(&self) -> bool { self.len() == 0 }

    /// Its keys and values, in no order that means anything.
    export fn iter(&self) -> Iter<K, V> {
        Iter { buckets: self.buckets.iter(), bucket: core::slice::empty().iter() }
    }

    /// Its keys and values, with the values to change.
    export fn iter_mut(&mut self) -> IterMut<K, V> {
        IterMut { buckets: self.buckets.iter_mut(), bucket: core::slice::empty_mut().iter_mut() }
    }

    /// Gives each key and its value to `f`, and then the buckets back: how a
    /// map of values that can't be thrown away is used up.
    export fn free_with<effect e, F: FnMut(Entry<K, V>) with e + Discard>(self, mut f: F) with e {
        let Map { buckets, len: _ } = self;
        buckets.free_with(|bucket: List<Entry<K, V>>| bucket.free_with(|e: Entry<K, V>| f(e)));
    }
}

impl<K: Hash + Eq, V> Map<K, V> {
    /// The value of the key `p` is, if it's there.
    export fn get<P: Probe<Key = K>>(&self, p: P) -> Option<&V> {
        let n = self.buckets.len();
        if n == 0 {
            return None;
        }
        for e in self.buckets.index(slot(hash_of(p), n)).iter() {
            if p.is(&e.key) {
                return Some(&e.value);
            }
        }
        None
    }

    /// The value of the key `p` is, to change, if it's there.
    export fn get_mut<P: Probe<Key = K>>(&mut self, p: P) -> Option<&mut V> {
        let n = self.buckets.len();
        if n == 0 {
            return None;
        }
        for e in self.buckets.index_mut(slot(hash_of(p), n)).iter_mut() {
            if p.is(&e.key) {
                return Some(&mut e.value);
            }
        }
        None
    }

    /// Is the key `p` is there?
    export fn contains_key<P: Probe<Key = K>>(&self, p: P) -> bool { self.get(p).is_some() }

    /// Takes the key `p` is out, with its value, if it's there.
    export fn remove_entry<P: Probe<Key = K>>(&mut self, p: P) -> Option<Entry<K, V>> {
        let n = self.buckets.len();
        if n == 0 {
            return None;
        }
        let bucket = self.buckets.index_mut(slot(hash_of(p), n));
        let mut i: usize = 0;
        while i < bucket.len() {
            if p.is(&bucket.index(i).key) {
                let last = bucket.len() - 1;
                bucket.swap(i, last);
                // It has this key, so `len` is at least 1; but that's the
                // map's invariant, which T can't state yet (FRICTION.md).
                if self.len > 0 {
                    self.len = self.len - 1;
                }
                return bucket.pop();
            }
            i = i + 1;
        }
        None
    }

    /// Puts `e` in its bucket, with no other key like it there. It leaves
    /// `len` to its caller.
    #[blame_caller]
    fn put(&mut self, e: Entry<K, V>) with alloc ensures self.len() == old(self.len()) {
        let n = self.buckets.len();
        if n == 0 {
            let mut bucket = List::new();
            bucket.push(e);
            self.buckets.push(bucket);
            return;
        }
        self.buckets.index_mut(slot(hash_of(&e.key), n)).push(e);
    }

    /// Doubles the buckets, from `FIRST` at first, and puts each key in its
    /// new one.
    #[blame_caller]
    fn grow(&mut self) with alloc {
        let n = self.buckets.len();
        let more = if n == 0 {
            FIRST
        } else if n > greatest::<usize>() / 2 {
            out_of_memory()
        } else {
            n * 2
        };
        let mut buckets = List::with_capacity(more);
        let mut i: usize = 0;
        while i < more {
            buckets.push(List::new());
            i = i + 1;
        }
        let old = replace(&mut self.buckets, buckets);
        old.free_with(|bucket: List<Entry<K, V>>| bucket.free_with(|e: Entry<K, V>| self.put(e)));
    }
}

impl<K: Hash + Eq + Discard, V> Map<K, V> {
    /// Gives the key `key` the value `value`, and returns the value it had,
    /// if it had one. The key that was there stays, and `key` is thrown
    /// away.
    #[blame_caller]
    export fn insert(&mut self, key: K, value: V) -> Option<V> with alloc {
        if let Some(v) = self.get_mut(&key) {
            return Some(replace(v, value));
        }
        if self.len >= self.buckets.len() {
            self.grow();
        }
        // A map as big as a `usize` can count can't count one more key.
        // The check is after `grow`, which can't say it keeps `len`: its
        // closure captures `self` (FRICTION.md); `put` says so.
        if self.len == greatest() {
            out_of_memory();
        }
        self.put(Entry { key, value });
        self.len = self.len + 1;
        None
    }

    /// Takes the key `p` is out, and returns its value, if it's there.
    export fn remove<P: Probe<Key = K>>(&mut self, p: P) -> Option<V> {
        match self.remove_entry(p) {
            Some(Entry { key: _, value }) => Some(value),
            None => None,
        }
    }
}

/// The hash of what `p` is a probe for.
fn hash_of<P: Probe>(p: P) -> u64 {
    let mut h = Hasher::new();
    p.hash_with(&mut h);
    h.finish()
}

/// Which of `n` buckets a hash picks: its low bits, as `n` is a power of
/// two. `h % n` would be right for any `n`, and the checker proves it less
/// than `n` too, but it's a division where this is one `&`; the price is
/// that `n` must be a power of two, which T can't say of it yet: `grow`
/// keeps it one, by doubling.
fn slot(h: u64, n: { n: usize | n > 0 }) -> { i: usize | i < n } {
    (h & 0xffff_ffff) as usize & (n - 1)
}

/// A map's keys and values, as `Map::iter` gives them.
#[derive(Discard, Send where K: Sync, V: Sync, Sync where K: Sync, V: Sync)]
export struct Iter<'a, K, V> {
    buckets: core::slice::Iter<'a, List<Entry<K, V>>>,
    bucket: core::slice::Iter<'a, Entry<K, V>>,
}

impl<'a, K, V> Iterator for Iter<'a, K, V> {
    type Item = &'a Entry<K, V>;
    effect e = {};

    fn next(&mut self) -> Option<&'a Entry<K, V>> {
        loop {
            if let Some(e) = self.bucket.next() {
                return Some(e);
            }
            let Some(b) = self.buckets.next() else { return None };
            self.bucket = b.iter();
        }
    }
}

/// A map's keys and values, as `Map::iter_mut` gives them.
#[derive(Discard, Send where K: Send, V: Send, Sync where K: Sync, V: Sync)]
export struct IterMut<'a, K, V> {
    buckets: core::slice::IterMut<'a, List<Entry<K, V>>>,
    bucket: core::slice::IterMut<'a, Entry<K, V>>,
}

impl<'a, K, V> Iterator for IterMut<'a, K, V> {
    type Item = EntryMut<'a, K, V>;
    effect e = {};

    fn next(&mut self) -> Option<EntryMut<'a, K, V>> {
        loop {
            if let Some(e) = self.bucket.next() {
                return Some(EntryMut { key: &e.key, value: &mut e.value });
            }
            let Some(b) = self.buckets.next() else { return None };
            self.bucket = b.iter_mut();
        }
    }
}
