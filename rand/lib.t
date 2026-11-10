//! Numbers that look random: SplitMix64, from a seed, so the same seed
//! gives the same numbers.
//!
//! ```text
//! let mut rng = Rng::new(os.entropy.u64()?);   // or a seed of your own
//! rng.below(6)                                 // 0 to 5, each as likely
//! rng.chance(25)                               // true a quarter of the time
//! rng.shuffle(l.as_mut_slice())                // l in a random order
//! ```
//!
//! SplitMix64 is quick, and good enough for games and tests, but it's not
//! for secrets: from a few numbers anyone can work out the rest. It's
//! wrapping arithmetic, shifts and exclusive or, on one `u64`, so it needs
//! nothing but core.
#![warn(implicit_panics)]

use core::num::{wrapping_add, wrapping_mul, wrapping_sub};

/// Numbers that look random, each from the one before. It isn't `Copy`:
/// a copy would give the same numbers again.
#[derive(Discard, Send, Sync)]
export struct Rng { state: u64 }

impl Rng {
    /// Numbers that start from `seed`.
    export fn new(seed: u64) -> Rng { Rng { state: seed } }

    /// The next number: any `u64`, each as likely.
    export fn u64(&mut self) -> u64 {
        self.state = wrapping_add(self.state, 0x9E3779B97F4A7C15);
        let mut z = self.state;
        z = wrapping_mul(z ^ (z >> 30), 0xBF58476D1CE4E5B9);
        z = wrapping_mul(z ^ (z >> 27), 0x94D049BB133111EB);
        z ^ (z >> 31)
    }

    /// A number less than `n`, each as likely. Taking the next number
    /// modulo `n` would favour the small ones a little, unless `n` divides
    /// 2^64, so the few numbers that make the difference, those less than
    /// 2^64 modulo `n`, are drawn again.
    export fn below(&mut self, n: { n: usize | n > 0 }) -> { r: usize | r < n } {
        let m = n as u64;
        // 2^64 modulo `n`, which is (2^64 - n) modulo `n`.
        let skip = wrapping_sub(0, m) % m;
        loop {
            let x = self.u64();
            if x >= skip {
                return (x % m) as usize;
            }
        }
    }

    /// `true` `percent` times in a hundred.
    export fn chance(&mut self, percent: { p: u64 | p <= 100 }) -> bool {
        self.u64() % 100 < percent
    }

    /// Puts `s`'s values in a random order, each order as likely: the
    /// Fisher-Yates shuffle.
    export fn shuffle<T>(&mut self, s: &mut [T]) {
        let mut i = s.len();
        while i > 1 invariant i <= s.len() {
            let j = self.below(i);
            i = i - 1;
            s.swap(i, j);
        }
    }
}
