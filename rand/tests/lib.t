//! Uses the numbers as a dependent would: only what it exports. `t test
//! rand/tests/lib.t` runs each test.

use alloc::list::List;
use rand::Rng;

/// SplitMix64's own: the first numbers from seed 1234567 are those its
/// reference implementation gives.
#[test]
fn as_splitmix64_gives() {
    let mut rng = Rng::new(1234567);
    let want: [u64; 5] = [
        6457827717110365317,
        3203168211198807973,
        9817491932198370423,
        4593380528125082431,
        16408922859458223821,
    ];
    for w in want.iter() {
        assert_eq(&rng.u64(), w);
    }
}

/// The same seed, the same numbers.
#[test]
fn same_seed_same_numbers() {
    let mut a = Rng::new(42);
    let mut b = Rng::new(42);
    for _ in 0..100u32 {
        assert_eq(&a.below(1000), &b.below(1000));
    }
}

/// Every number below `n` comes up, and nothing else can (`below`'s result
/// is refined, so no test is needed for that).
#[test]
fn below_covers() {
    let mut rng = Rng::new(7);
    let mut seen: [bool; 6] = [false; 6];
    for _ in 0..200u32 {
        seen[rng.below(6)] = true;
    }
    for s in seen.iter() {
        assert(*s);
    }
    // One choice: always 0.
    for _ in 0..10u32 {
        assert_eq(&rng.below(1), &0);
    }
}

/// Below `n`, the number is the next number modulo `n`, unless that's one
/// of the few drawn again: so for small `n` it's what the modulo gives.
#[test]
fn below_is_modulo_for_small_n() {
    let mut a = Rng::new(42);
    let mut b = Rng::new(42);
    for _ in 0..100u32 {
        assert_eq(&(a.below(6) as u64), &(b.u64() % 6));
    }
}

#[test]
fn chance_never_and_always() {
    let mut rng = Rng::new(3);
    let mut some = 0usize;
    for _ in 0..1000u32 {
        assert(!rng.chance(0));
        assert(rng.chance(100));
        if rng.chance(50) {
            some = some + 1;
        }
    }
    // About half; far from none and from all.
    assert(some > 400 && some < 600);
}

/// A shuffle is a permutation: the same values, each once.
#[test]
fn shuffle_permutes() {
    let mut rng = Rng::new(11);
    let mut l: List<usize> = List::new();
    for i in 0..50usize {
        l.push(i);
    }
    rng.shuffle(l.as_mut_slice());
    let mut seen: [bool; 50] = [false; 50];
    let mut moved = 0usize;
    for (i, v) in l.iter().enumerate() {
        if *v < 50 {
            assert(!seen[*v]);
            seen[*v] = true;
        }
        if *v != i {
            moved = moved + 1;
        }
    }
    for s in seen.iter() {
        assert(*s);
    }
    assert(moved > 0);
    // Nothing to put in order: no change, and no numbers drawn.
    let mut one: [u8; 1] = [9];
    rng.shuffle(one.as_mut_slice());
    assert_eq(&one[0], &9);
}
