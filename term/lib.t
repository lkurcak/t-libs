//! The terminal, for a program that takes all of it, as a game does: keys
//! as they're pressed, and the other screen to draw on.
//!
//! ```text
//! let mut raw = os.stdin.raw()?;           // keys as they're pressed
//! let mut screen = Screen::enter(&mut os.stdout)?;
//! loop {
//!     screen.clear()?;
//!     screen.out().line("q quits")?;
//!     screen.out().flush()?;
//!     match term::read(&mut raw, os.clock)? {
//!         Key::Char('q') | Key::Ctrl('c') | Key::Escape => break,
//!         Key::Up => ..,
//!         _ => {},
//!     }
//! }
//! ```
//!
//! Dropping the screen goes back to what was on the terminal before, and
//! dropping `raw` puts the terminal back in line mode.
//!
//! A key comes as bytes: a letter as itself, in UTF-8, and a key such as
//! an arrow as a few, starting with escape, 27. Escape on its own, with
//! nothing after it for a moment, is the escape key. A `Decoder` tells
//! keys from bytes; `read` reads bytes from the terminal into one.
#![warn(implicit_panics)]

use core::io::Read;
use core::time::Duration;
use std::io::{Error, ErrorKind, Raw, Stdout};
use std::time::Clock;

/// A key pressed. An arrow, or another key here but a letter, with Shift,
/// Alt or Ctrl held is the key alone: Shift-Up is `Up`.
#[derive(Copy, Discard, Eq, Debug)]
export enum Key {
    /// A character typed: a letter, a digit, a space, an `é`.
    Char(char),
    /// A letter typed with Ctrl held: `Ctrl('c')` is Ctrl-C, which in raw
    /// mode is a key like any other.
    Ctrl(char),
    Up,
    Down,
    Left,
    Right,
    Home,
    End,
    PageUp,
    PageDown,
    Insert,
    Delete,
    Enter,
    Tab,
    Backspace,
    Escape,
    /// A key this doesn't know, such as F1, or a letter typed with Alt
    /// held.
    Other,
}

/// How long to wait for the rest of a key, in milliseconds: after an
/// escape, the rest of an arrow comes at once, and a person can't type
/// another key that quickly.
const REST_MS: u64 = 30;

/// The next key pressed, from `raw`; `clock` times the wait for the rest
/// of one.
export fn read(raw: &mut Raw<'_>, clock: Clock) -> Result<Key, Error> {
    let mut d = Decoder::new();
    loop {
        if d.partway() && !raw.wait(clock.now().add(Duration::from_millis(REST_MS)))? {
            if let Some(k) = d.pause() {
                return Ok(k);
            }
        }
        if let Some(k) = d.feed(byte(raw)?) {
            return Ok(k);
        }
    }
}

/// The next byte of input.
fn byte(raw: &mut Raw<'_>) -> Result<u8, Error> {
    let mut b = [0u8; 1];
    if raw.read(b.as_mut_slice())? == 0 {
        return Err(Error::new(ErrorKind::UnexpectedEnd));
    }
    Ok(b[0])
}

/// Tells keys from the bytes that come for them, a byte at a time.
#[derive(Copy, Discard)]
export struct Decoder { state: State }

/// How far a control sequence is.
#[derive(Copy, Discard, Eq)]
enum Csi {
    /// In its first number, which says which key, as `3` in `3~`, delete.
    First,
    /// After a `;`: numbers that say Shift, Alt or Ctrl was held.
    Rest,
    /// After a `<`, `=`, `>` or `?`: not a key at all, but such as the
    /// mouse.
    Private,
}

/// How far a decoder is into a key.
#[derive(Copy, Discard, Eq)]
enum State {
    /// At the start of one.
    Start,
    /// After an escape.
    Escape,
    /// After an escape and `[`: a control sequence, with its first number
    /// so far, and what's come since.
    Csi(u32, Csi),
    /// After an escape and `O`.
    Ss3,
    /// Part way through a character in UTF-8: how many bytes are still to
    /// come, its number so far, and the least number it can be with as
    /// many bytes as it has. A character has at most 21 bits, and each byte
    /// to come brings 6, so the number so far has at most `21 - 6 * left`.
    Utf8(
        { left: u8 | left >= 1 && left <= 3 },
        { c: u32 | (left == 1 && c < 0x8000) || (left == 2 && c < 0x200) || (left == 3 && c < 8) },
        u32,
    ),
}

impl Decoder {
    /// A decoder at the start of a key.
    export fn new() -> Decoder { Decoder { state: State::Start } }

    /// Is it part way through a key?
    export fn partway(&self) -> bool { self.state != State::Start }

    /// Takes the next byte: the key, if that's the last of one.
    export fn feed(&mut self, b: u8) -> Option<Key> {
        let (next, key) = step(self.state, b);
        self.state = next;
        key
    }

    /// Nothing more has come for a moment: the key so far, if it's part
    /// way through one. An escape on its own is the escape key; anything
    /// else cut short is a key it doesn't know.
    export fn pause(&mut self) -> Option<Key> {
        let key = match self.state {
            State::Start => None,
            State::Escape => Some(Key::Escape),
            _ => Some(Key::Other),
        };
        self.state = State::Start;
        key
    }
}

/// From `state`, after byte `b`: the state next, and the key, if that's
/// the last byte of one. Once there's a key, the state is the start.
fn step(state: State, b: u8) -> (State, Option<Key>) {
    match state {
        State::Start => start(b),
        State::Escape => match b {
            // `[`: a control sequence.
            91 => (State::Csi(0, Csi::First), None),
            // `O`: one more letter.
            79 => (State::Ss3, None),
            // Alt held, with another key.
            _ => done(Key::Other),
        },
        State::Csi(n, at) => match b {
            // A digit; the first number is the key's, which no key needs
            // past 9999.
            48..=57 => {
                let d = (b - 48) as u32;
                let n = if at == Csi::First && n < 1000 { n * 10 + d } else { n };
                (State::Csi(n, at), None)
            },
            // `;`: what was held, which a key here is the same without.
            59 => (State::Csi(n, if at == Csi::Private { at } else { Csi::Rest }), None),
            // `:`, `<`, `=`, `>` or `?`.
            58..=63 => (State::Csi(n, if b == 58 { at } else { Csi::Private }), None),
            // Bytes that go between the numbers and the last.
            32..=47 => (State::Csi(n, at), None),
            // The last byte.
            64..=126 => done(if at == Csi::Private { Key::Other } else { csi(n, b) }),
            _ => done(Key::Other),
        },
        State::Ss3 => done(letter(b)),
        State::Utf8(left, code, least) => {
            if b & 0xC0 != 0x80 {
                return done(Key::Other);
            }
            let code = (code << 6) | (b & 0x3F) as u32;
            if left > 1 {
                return (State::Utf8(left - 1, code, least), None);
            }
            done(match char::from_u32(code) {
                Some(c) => if code >= least { Key::Char(c) } else { Key::Other },
                None => Key::Other,
            })
        },
    }
}

/// A key and back to the start.
fn done(k: Key) -> (State, Option<Key>) { (State::Start, Some(k)) }

/// The first byte of a key.
fn start(b: u8) -> (State, Option<Key>) {
    match b {
        27 => (State::Escape, None),
        13 | 10 => done(Key::Enter),
        9 => done(Key::Tab),
        127 | 8 => done(Key::Backspace),
        // Ctrl with a letter: Ctrl-A is 1.
        1..=26 => done(Key::Ctrl((b + 96) as char)),
        0..=31 => done(Key::Other),
        32..=126 => done(Key::Char(b as char)),
        // The first byte of a character in UTF-8 says how many follow,
        // and its low bits are the number's high ones.
        0xC2..=0xDF => (State::Utf8(1, (b & 0x1F) as u32, 0x80), None),
        0xE0..=0xEF => (State::Utf8(2, (b & 0x0F) as u32, 0x800), None),
        0xF0..=0xF4 => (State::Utf8(3, (b & 0x07) as u32, 0x10000), None),
        _ => done(Key::Other),
    }
}

/// A control sequence's key, from its first number `n` and last byte `b`.
fn csi(n: u32, b: u8) -> Key {
    if b != 126 {
        return letter(b);
    }
    // `~`: the number says which key.
    match n {
        1 | 7 => Key::Home,
        2 => Key::Insert,
        3 => Key::Delete,
        4 | 8 => Key::End,
        5 => Key::PageUp,
        6 => Key::PageDown,
        _ => Key::Other,
    }
}

/// The key a letter ends a sequence with: `A` is up.
fn letter(b: u8) -> Key {
    match b {
        65 => Key::Up,
        66 => Key::Down,
        67 => Key::Right,
        68 => Key::Left,
        72 => Key::Home,
        70 => Key::End,
        _ => Key::Other,
    }
}

/// The terminal's other screen, which a program that draws on the whole
/// terminal uses, so that what was there before is there again after;
/// with the cursor hidden. Dropping it goes back to the first screen, and
/// shows the cursor again.
export struct Screen<'a> { out: &'a mut Stdout }

impl<'a> Screen<'a> {
    /// Goes to the other screen, and clears it.
    export fn enter(out: &'a mut Stdout) -> Result<Screen<'a>, Error> {
        out.put("\u{1b}[?1049h\u{1b}[?25l\u{1b}[H\u{1b}[2J")?;
        Ok(Screen { out })
    }

    /// What's drawn on it is written to.
    export fn out(&mut self) -> &mut Stdout { &mut *self.out }

    /// Clears it, and puts the cursor at the top left.
    export fn clear(&mut self) -> Result<(), Error> { self.out.put("\u{1b}[H\u{1b}[2J") }
}

/// Shows the cursor again, with the colours as they were, and goes back to
/// the first screen. If that fails, the terminal's gone, and there's
/// nothing to go back to.
impl<'a> Discard for Screen<'a> {
    fn discard(self) {
        let _ = self.out.put("\u{1b}[0m\u{1b}[?25h\u{1b}[?1049l");
        let _ = self.out.flush();
    }
}
