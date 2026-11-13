//! Uses the grid as a dependent would: only what it exports. `t test
//! grid/tests/lib.t` runs each test.

use core::num::greatest;
use grid::Grid;

/// What `new` makes is as big as it was asked for, so coordinates inside
/// that are proved (t 0.69.0's refinements of `Option`'s type argument).
#[test]
fn get_and_set() {
    let Some(mut g) = Grid::new(3, 2, 0u8) else { panic("3 by 2 fits") };
    assert_eq(&g.width(), &3);
    assert_eq(&g.height(), &2);
    g.set(2, 1, 7);
    g.set(0, 0, 1);
    assert_eq(g.get(2, 1), &7);
    assert_eq(g.get(0, 0), &1);
    assert_eq(g.get(1, 0), &0);
    assert_eq(&g.replace(2, 1, 8), &7);
    assert_eq(g.get(2, 1), &8);
}

#[test]
fn at_checks() {
    let Some(g) = Grid::new(2, 2, 5u8) else { panic("2 by 2 fits") };
    assert_eq(&g.at(1, 1), &Some(&5));
    assert(g.at(2, 0).is_none());
    assert(g.at(0, 2).is_none());
}

#[test]
fn too_big() {
    assert(Grid::new(greatest::<usize>(), 2, 0u8).is_none());
    assert(Grid::new(2, greatest::<usize>(), 0u8).is_none());
    // No rows: no cells, however wide.
    let Some(g) = Grid::new(greatest::<usize>(), 0, 0u8) else { panic("no cells fit") };
    assert_eq(&g.cells().len(), &0);
}

/// `cells` is row by row, and `x_of`/`y_of` say where each is.
#[test]
fn row_by_row() {
    let Some(mut g) = Grid::new(3, 2, 0u32) else { panic("3 by 2 fits") };
    // `x < g.width()` in each `for`, as a range's `next` says what it gives
    // is less than its end; and `set` keeps the width and height, so the
    // ranges' ends stay them (t 0.69.0).
    for y in 0..g.height() {
        for x in 0..g.width() {
            g.set(x, y, (y * 10 + x) as u32);
        }
    }
    let cells = g.cells();
    assert_eq(&cells.len(), &6);
    for i in 0..cells.len() {
        let x = g.x_of(i);
        let y = g.y_of(i);
        assert_eq(&cells[i], g.get(x, y));
        assert_eq(&cells[i], &((y * 10 + x) as u32));
    }
}

#[test]
fn copies() {
    let Some(mut g) = Grid::new(2, 1, 1u8) else { panic("2 by 1 fits") };
    let h = g.copy();
    g.set(1, 0, 9);
    assert_eq(&h.cells()[1], &1);
    assert_eq(&g.cells()[1], &9);
}

#[test]
fn iterates() {
    let Some(g) = Grid::new(2, 3, 4u8) else { panic("2 by 3 fits") };
    assert_eq(&g.iter().count(), &6);
    assert_eq(&g.iter().filter(|v| **v == 4).count(), &6);
}

/// A value that isn't `Copy`.
#[derive(Discard)]
struct Tile { n: usize }

/// Cells that aren't `Copy`, which `new` can't fill: each made by `from_fn`
/// (t 0.70.0's loop invariants say how many it made).
#[test]
fn from_fn_fills_each_cell() {
    let Some(g) = Grid::from_fn(3, 2, |x, y| Tile { n: x + 3 * y }) else { panic("3 by 2 fits") };
    assert_eq(&g.width(), &3);
    assert_eq(&g.height(), &2);
    assert_eq(&g.get(0, 0).n, &0);
    assert_eq(&g.get(2, 0).n, &2);
    assert_eq(&g.get(1, 1).n, &4);
    assert(Grid::from_fn(greatest::<usize>(), 2, |_x, _y| 0u8).is_none());
}

/// A row is a slice as wide as the grid, proved in range (t 0.72.0's
/// sub-slices), so its indexes below the width need no check.
#[test]
fn rows() {
    let Some(g) = Grid::from_fn(3, 2, |x, y| x + 3 * y) else { panic("3 by 2 fits") };
    let r = g.row(1);
    assert_eq(&r.len(), &3);
    assert_eq(&r[0], &3);
    assert_eq(&r[2], &5);
    assert_eq(&g.row(0)[1], &1);
}

/// Rows lent to change keep the grid as big: `get` after `row_mut` needs
/// no check (t-life's bands write rows of the next generation this way).
#[test]
fn rows_to_change() {
    let Some(mut g) = Grid::new(3, 2, 0u8) else { panic("3 by 2 fits") };
    let r = g.row_mut(1);
    r[0] = 4;
    r[2] = 6;
    assert_eq(g.get(0, 1), &4);
    assert_eq(g.get(2, 1), &6);
    assert_eq(g.get(0, 0), &0);
    let cells = g.cells_mut();
    cells[1] = 9;
    assert_eq(g.get(1, 0), &9);
    assert_eq(&g.width(), &3);
}

/// A grid made of a list's cells, row by row, gives them back.
#[test]
fn from_and_into_cells() {
    let mut l = alloc::list::List::new();
    l.push(1u8);
    l.push(2);
    l.push(3);
    l.push(4);
    let g = Grid::from_cells(2, 2, l);
    assert_eq(g.get(1, 0), &2);
    assert_eq(g.get(0, 1), &3);
    let back = g.into_cells();
    assert_eq(&back.len(), &4);
    assert_eq(&back[3], &4);
}
