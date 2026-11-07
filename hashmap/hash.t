//! Hashing: what a key gives a map to find its bucket by.

use alloc::string::String;
use core::num::{wrap, wrapping_mul};

/// A value that can be hashed: equal values must write the same bytes
/// to a `Hasher`, or a map won't find what's in it. Nothing checks this,
/// and nothing relies on it to be sound: an impl that breaks it only gives
/// wrong answers.
export trait Hash {
    /// Writes `self` to `h`.
    fn hash(&self, h: &mut Hasher);
}

/// FNV-1a, 64 bits: simple, quick on short keys, and the same in every
/// build. It isn't keyed, so whoever chooses the keys can choose ones that
/// share a bucket; a map of keys from an adversary wants a keyed hash.
#[derive(Discard, Copy, Send, Sync)]
export struct Hasher { state: u64 }

/// FNV-1a's offset basis: what a hasher starts from.
const OFFSET: u64 = 0xcbf2_9ce4_8422_2325;

/// FNV-1a's prime, which each byte is multiplied in by.
const PRIME: u64 = 0x0100_0000_01b3;

impl Hasher {
    /// A hasher that has been written nothing.
    export fn new() -> Hasher { Hasher { state: OFFSET } }

    /// Writes one byte.
    export fn byte(&mut self, b: u8) {
        self.state = wrapping_mul(self.state ^ b as u64, PRIME);
    }

    /// Writes `bytes`, one by one.
    export fn write(&mut self, bytes: &[u8]) {
        for b in bytes.iter() {
            self.byte(*b);
        }
    }

    /// Writes `n`'s eight bytes, the low one first.
    export fn u64(&mut self, n: u64) {
        let mut n = n;
        let mut i: u8 = 0;
        while i < 8 {
            self.byte((n & 0xff) as u8);
            n = n >> 8;
            i = i + 1;
        }
    }

    /// Writes `s`'s bytes and then one no UTF-8 text has, `0xff`: so two
    /// strings written one after the other are told apart from two others
    /// with the same bytes in all, as "ab" "c" from "a" "bc".
    export fn str(&mut self, s: &str) {
        self.write(s.as_bytes());
        self.byte(0xff);
    }

    /// The hash of what's been written.
    export fn finish(&self) -> u64 { self.state }
}

/// An integer as the 64 bits of its two's complement, which tells any two
/// of one type apart: one impl for all ten integer types, beside the
/// others, as `Int` is sealed, so `String` is known not to be one.
impl<T: Int> Hash for T {
    fn hash(&self, h: &mut Hasher) { h.u64(wrap(*self)) }
}

impl Hash for bool {
    fn hash(&self, h: &mut Hasher) { h.byte(if *self { 1 } else { 0 }) }
}

impl Hash for char {
    fn hash(&self, h: &mut Hasher) { h.u64(*self as u32 as u64) }
}

impl Hash for String {
    fn hash(&self, h: &mut Hasher) { h.str(self.as_str()) }
}

/// What a map can be asked about: something that hashes as a key of type
/// `Key` does, and says whether it's that key. `&K` is a probe for keys of
/// type `K`, and `&str` for `String` keys, so a map of `String`s can be
/// asked about a `&str` without making a `String` of it.
///
/// A probe must hash as the keys it's equal to do. Nothing checks this,
/// and nothing relies on it to be sound.
export trait Probe: Copy {
    /// The keys it's a probe for.
    type Key;

    /// Writes it to `h`, as the key it's equal to would be.
    fn hash_with(self, h: &mut Hasher);

    /// Is it `key`?
    fn is(self, key: &Self::Key) -> bool;
}

impl<'a, K: Hash + Eq> Probe for &'a K {
    type Key = K;

    fn hash_with(self, h: &mut Hasher) { self.hash(h) }

    fn is(self, key: &K) -> bool { self == key }
}

impl<'a> Probe for &'a str {
    type Key = String;

    fn hash_with(self, h: &mut Hasher) { h.str(self) }

    fn is(self, key: &String) -> bool { self == key.as_str() }
}
