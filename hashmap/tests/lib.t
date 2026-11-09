//! Uses the map as a dependent would: only what it exports. `t test
//! tests/lib.t` runs each test.

use alloc::string::String;
use hashmap::Map;

/// `String` keys, asked about by `&str` and by `&String`.
#[test]
fn strings() {
    let mut ages: Map<String, u8> = Map::new();
    assert(ages.is_empty());
    assert(ages.insert(String::from("ada"), 36).is_none());
    ages.insert(String::from("alan"), 41);
    assert_eq(&ages.len(), &2);
    assert_eq(ages.get("ada").unwrap(), &36);
    assert_eq(ages.get(&String::from("alan")).unwrap(), &41);
    assert(ages.get("grace").is_none());
    // A new value for a key that's there: the old one comes back.
    assert_eq(&ages.insert(String::from("ada"), 37).unwrap(), &36);
    assert_eq(&ages.len(), &2);
    if let Some(v) = ages.get_mut("alan") {
        *v = *v + 1;
    }
    assert_eq(ages.get("alan").unwrap(), &42);
    assert(ages.contains_key("ada"));
    assert_eq(&ages.remove("ada").unwrap(), &37);
    assert(!ages.contains_key("ada"));
    assert(ages.remove("ada").is_none());
    assert_eq(&ages.len(), &1);
}

/// Keys of each integer type, `bool` and `char`, negative ones too.
#[test]
fn integers() {
    let mut m: Map<i64, i64> = Map::new();
    let keys: [i64; 5] = [-1, 0, 1, -9223372036854775807 - 1, 9223372036854775807];
    for k in keys.iter() {
        m.insert(*k, *k / 2);
    }
    assert_eq(&m.len(), &5);
    for k in keys.iter() {
        assert_eq(m.get(k).unwrap(), &(*k / 2));
    }
    let mut c: Map<char, bool> = Map::new();
    c.insert('a', true);
    c.insert('é', false);
    assert_eq(c.get(&'é').unwrap(), &false);
    let mut b: Map<bool, u64> = Map::new();
    b.insert(true, 1);
    b.insert(false, 0);
    b.insert(true, 2);
    assert_eq(&b.len(), &2);
    assert_eq(b.get(&true).unwrap(), &2);
}

/// Enough keys to grow many times, then half of them taken out again.
#[test]
fn many() {
    let mut m: Map<u32, u32> = Map::new();
    let mut i: u32 = 0;
    while i < 1000 {
        m.insert(i, i * 2);
        i = i + 1;
    }
    assert_eq(&m.len(), &1000);
    let mut sum: u64 = 0;
    for (_, v) in m.iter() {
        sum = sum + *v as u64;
    }
    assert_eq(&sum, &999000);
    for (k, v) in m.iter_mut() {
        *v = *k;
    }
    assert_eq(m.get(&777).unwrap(), &777);
    let mut j: u32 = 0;
    while j < 1000 {
        if j % 2 == 0 {
            m.remove(&j);
        }
        j = j + 1;
    }
    assert_eq(&m.len(), &500);
    assert(m.contains_key(&777));
    assert(!m.contains_key(&778));
}

/// A value that can't be thrown away: the map is used up by `free_with`.
struct Token { n: u32 }

#[test]
fn linear() {
    let mut m: Map<u32, Token> = Map::new();
    let mut total: u32 = 0;
    // What `insert` gives back has to be used up as well.
    total = total + put(&mut m, 1, 10);
    total = total + put(&mut m, 2, 20);
    total = total + put(&mut m, 1, 5);
    m.free_with(|(_, Token { n }): (u32, Token)| {
        total = total + n;
    });
    assert_eq(&total, &35);
}

/// Gives `k` a token of `n`, and returns what the token it had held.
#[blame_caller]
fn put(m: &mut Map<u32, Token>, k: u32, n: u32) -> u32 with alloc {
    match m.insert(k, Token { n }) {
        Some(Token { n }) => n,
        None => 0,
    }
}

fn shareable<T: Send + Sync>(_t: &T) {}

/// A map, its entries and its iterators can go to another thread, or be
/// shared by threads, when its keys and values can.
#[test]
fn send_and_sync() {
    let mut m: Map<String, u8> = Map::new();
    m.insert(String::from("ada"), 36);
    shareable(&m);
    shareable(&m.iter());
    shareable(&m.iter_mut());
}
