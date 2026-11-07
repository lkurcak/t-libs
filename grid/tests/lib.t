//! Uses the grid as a dependent would: only what it exports. `t test
//! grid/tests/lib.t` runs each test.

use core::num::greatest;
use grid::Grid;

/// What `new` makes is an `Option`, which can't say how big the grid is,
/// so a test asks before it uses coordinates.
#[test]
fn get_and_set() {
    let Some(mut g) = Grid::new(3, 2, 0u8) else { panic("3 by 2 fits") };
    assert_eq(&g.width(), &3);
    assert_eq(&g.height(), &2);
    if g.width() == 3 && g.height() == 2 {
        g.set(2, 1, 7);
        g.set(0, 0, 1);
        assert_eq(g.get(2, 1), &7);
        assert_eq(g.get(0, 0), &1);
        assert_eq(g.get(1, 0), &0);
        assert_eq(&g.replace(2, 1, 8), &7);
        assert_eq(g.get(2, 1), &8);
    }
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
    let mut y: usize = 0;
    while y < g.height() {
        let mut x: usize = 0;
        // `&& y < g.height()`: the loop lends `g`, so at its head the
        // checker forgets what it knew of `g`, the outer condition too,
        // though `set` ensures the height stays (FRICTION.md).
        while x < g.width() && y < g.height() {
            g.set(x, y, (y * 10 + x) as u32);
            x = x + 1;
        }
        y = y + 1;
    }
    let cells = g.cells();
    assert_eq(&cells.len(), &6);
    let mut i: usize = 0;
    while i < cells.len() {
        let x = g.x_of(i);
        let y = g.y_of(i);
        assert_eq(&cells[i], g.get(x, y));
        assert_eq(&cells[i], &((y * 10 + x) as u32));
        i = i + 1;
    }
}

#[test]
fn copies() {
    let Some(mut g) = Grid::new(2, 1, 1u8) else { panic("2 by 1 fits") };
    if g.width() == 2 && g.height() == 1 {
        let h = g.copy();
        g.set(1, 0, 9);
        assert_eq(&h.cells()[1], &1);
        assert_eq(&g.cells()[1], &9);
    }
}

#[test]
fn iterates() {
    let Some(g) = Grid::new(2, 3, 4u8) else { panic("2 by 3 fits") };
    assert_eq(&g.iter().count(), &6);
    assert_eq(&g.iter().filter(|v| **v == 4).count(), &6);
}
