//! Uses the keys as a dependent would: only what it exports. `t test
//! term/tests/lib.t` runs each test. Reading from a terminal and its other
//! screen need a terminal, so the games that use them test them.

use alloc::list::List;
use term::{Decoder, Key};

/// The keys `bytes` are, as they'd come from a terminal: if they end part
/// way through one, nothing more comes.
fn keys(bytes: &[u8]) -> List<Key> {
    let mut d = Decoder::new();
    let mut out: List<Key> = List::new();
    for b in bytes.iter() {
        if let Some(k) = d.feed(*b) {
            out.push(k);
        }
    }
    if let Some(k) = d.pause() {
        out.push(k);
    }
    out
}

/// What `bytes` are, as one key.
fn key(bytes: &[u8]) -> Key {
    let ks = keys(bytes);
    assert_eq(&ks.len(), &1);
    match ks.first() {
        Some(k) => *k,
        None => Key::Other,
    }
}

#[test]
fn letters() {
    assert_eq(&key("q".as_bytes()), &Key::Char('q'));
    assert_eq(&key("Q".as_bytes()), &Key::Char('Q'));
    assert_eq(&key(" ".as_bytes()), &Key::Char(' '));
    assert_eq(&key("~".as_bytes()), &Key::Char('~'));
}

/// A character of two, three or four bytes in UTF-8.
#[test]
fn characters() {
    assert_eq(&key("é".as_bytes()), &Key::Char('é'));
    assert_eq(&key("€".as_bytes()), &Key::Char('€'));
    assert_eq(&key("😀".as_bytes()), &Key::Char('😀'));
    let ks = keys("añ€😀z".as_bytes());
    let want: [Key; 5] = [
        Key::Char('a'),
        Key::Char('ñ'),
        Key::Char('€'),
        Key::Char('😀'),
        Key::Char('z'),
    ];
    assert_eq(&ks.as_slice(), &want.as_slice());
}

/// Bytes that aren't UTF-8 are keys it doesn't know.
#[test]
fn not_utf8() {
    // A byte that only continues a character.
    assert_eq(&key([0x80u8].as_slice()), &Key::Other);
    // Too long a way to write `/`, and a surrogate.
    assert_eq(&key([0xC0u8].as_slice()), &Key::Other);
    let ks = keys([0xC0u8, 0xAF].as_slice());
    assert_eq(&ks.len(), &2);
    assert_eq(&key([0xE0u8, 0x80, 0xAF].as_slice()), &Key::Other);
    assert_eq(&key([0xEDu8, 0xA0, 0x80].as_slice()), &Key::Other);
    // Past the last character, 10FFFF.
    assert_eq(&key([0xF4u8, 0x90, 0x80, 0x80].as_slice()), &Key::Other);
    // Cut short by a letter: the letter goes with it.
    assert_eq(&key([0xC3u8, 0x61].as_slice()), &Key::Other);
    // Cut short by nothing more.
    assert_eq(&key([0xE2u8, 0x82].as_slice()), &Key::Other);
}

#[test]
fn control_keys() {
    assert_eq(&key([3u8].as_slice()), &Key::Ctrl('c'));
    assert_eq(&key([1u8].as_slice()), &Key::Ctrl('a'));
    assert_eq(&key([26u8].as_slice()), &Key::Ctrl('z'));
    assert_eq(&key([13u8].as_slice()), &Key::Enter);
    assert_eq(&key([10u8].as_slice()), &Key::Enter);
    assert_eq(&key([9u8].as_slice()), &Key::Tab);
    assert_eq(&key([127u8].as_slice()), &Key::Backspace);
    assert_eq(&key([8u8].as_slice()), &Key::Backspace);
    assert_eq(&key([0u8].as_slice()), &Key::Other);
}

/// Escape with nothing after it is the escape key; with a letter after, it
/// was Alt and the letter.
#[test]
fn escape() {
    assert_eq(&key([27u8].as_slice()), &Key::Escape);
    assert_eq(&key("\u{1b}x".as_bytes()), &Key::Other);
    // An escape cut short.
    assert_eq(&key("\u{1b}[".as_bytes()), &Key::Other);
    assert_eq(&key("\u{1b}O".as_bytes()), &Key::Other);
}

#[test]
fn arrows() {
    assert_eq(&key("\u{1b}[A".as_bytes()), &Key::Up);
    assert_eq(&key("\u{1b}[B".as_bytes()), &Key::Down);
    assert_eq(&key("\u{1b}[C".as_bytes()), &Key::Right);
    assert_eq(&key("\u{1b}[D".as_bytes()), &Key::Left);
    // As some terminals send them.
    assert_eq(&key("\u{1b}OA".as_bytes()), &Key::Up);
    assert_eq(&key("\u{1b}OD".as_bytes()), &Key::Left);
    // With Shift, and with Ctrl, held.
    assert_eq(&key("\u{1b}[1;2A".as_bytes()), &Key::Up);
    assert_eq(&key("\u{1b}[1;5C".as_bytes()), &Key::Right);
}

/// The keys that come as a number and `~`, and home and end, which come
/// either way.
#[test]
fn numbered() {
    assert_eq(&key("\u{1b}[H".as_bytes()), &Key::Home);
    assert_eq(&key("\u{1b}[F".as_bytes()), &Key::End);
    assert_eq(&key("\u{1b}OH".as_bytes()), &Key::Home);
    assert_eq(&key("\u{1b}[1~".as_bytes()), &Key::Home);
    assert_eq(&key("\u{1b}[7~".as_bytes()), &Key::Home);
    assert_eq(&key("\u{1b}[4~".as_bytes()), &Key::End);
    assert_eq(&key("\u{1b}[2~".as_bytes()), &Key::Insert);
    assert_eq(&key("\u{1b}[3~".as_bytes()), &Key::Delete);
    assert_eq(&key("\u{1b}[5~".as_bytes()), &Key::PageUp);
    assert_eq(&key("\u{1b}[6~".as_bytes()), &Key::PageDown);
    assert_eq(&key("\u{1b}[3;5~".as_bytes()), &Key::Delete);
    // F5, and a number no key has.
    assert_eq(&key("\u{1b}[15~".as_bytes()), &Key::Other);
    assert_eq(&key("\u{1b}[99999999~".as_bytes()), &Key::Other);
    // F1, as some terminals send it.
    assert_eq(&key("\u{1b}OP".as_bytes()), &Key::Other);
}

/// A sequence that isn't a key, such as the mouse's, is taken whole, as
/// one key it doesn't know: none of it is left to be read as letters.
#[test]
fn not_keys() {
    assert_eq(&key("\u{1b}[<0;12;7M".as_bytes()), &Key::Other);
    assert_eq(&key("\u{1b}[?1;2c".as_bytes()), &Key::Other);
    assert_eq(&key("\u{1b}[1;2;3x".as_bytes()), &Key::Other);
}

/// Keys one after another, as when typed quickly.
#[test]
fn in_a_row() {
    let ks = keys("ab\u{1b}[Cq\u{1b}[3~\u{1b}".as_bytes());
    let want: [Key; 6] = [
        Key::Char('a'),
        Key::Char('b'),
        Key::Right,
        Key::Char('q'),
        Key::Delete,
        Key::Escape,
    ];
    assert_eq(&ks.as_slice(), &want.as_slice());
}

/// `partway` says whether to wait for more.
#[test]
fn partway() {
    let mut d = Decoder::new();
    assert(!d.partway());
    assert(d.feed(27).is_none());
    assert(d.partway());
    assert(d.feed(91).is_none());
    assert(d.partway());
    assert_eq(&d.feed(65), &Some(Key::Up));
    assert(!d.partway());
    assert_eq(&d.pause(), &None);
}
