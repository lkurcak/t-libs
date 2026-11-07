//! A grid: a value in each cell of a rectangle `width` cells wide and
//! `height` high, stored row by row.
//!
//! ```text
//! let Some(mut g) = Grid::new(3, 2, 0) else { .. };   // 3 wide, 2 high
//! g.set(2, 1, 7);                                   // column 2 of row 1
//! g.get(2, 1)                                       // &7
//! ```
//!
//! The cell in column `x` of row `y` is at `y * width + x`. The checker
//! proves that's in range from `x < width`, `y < height` and the grid's
//! invariant, `cells.len() == width * height`: so `get` and `set` ask for
//! coordinates inside the grid and never panic, and `at` is the one that
//! checks, for coordinates that may be outside.

use alloc::list::List;
use core::num::greatest;
use core::slice::Iter;

/// Values of type `T`, one in each cell of a `width` by `height` grid.
#[derive(Discard where T: Discard, Send where T: Send, Sync where T: Sync)]
export struct Grid<T> {
    width: usize,
    height: usize,
    cells: { c: List<T> | c.len() == width * height },
}

impl<T> Grid<T> {
    /// How many cells wide it is.
    #[measure]
    export fn width(&self) -> usize { self.width }

    /// How many cells high it is.
    #[measure]
    export fn height(&self) -> usize { self.height }

    /// The value in column `x` of row `y`.
    export fn get(
        &self,
        x: { x: usize | x < self.width() },
        y: { y: usize | y < self.height() },
    ) -> &T { &self.cells[y * self.width + x] }

    /// The value in column `x` of row `y`, or `None` if that's outside the
    /// grid.
    export fn at(&self, x: usize, y: usize) -> Option<&T> {
        if x < self.width && y < self.height { Some(self.get(x, y)) } else { None }
    }

    /// Puts `v` in column `x` of row `y`, and gives back what was there.
    export fn replace(
        &mut self,
        x: { x: usize | x < self.width() },
        y: { y: usize | y < self.height() },
        v: T,
    ) -> T ensures self.width() == old(self.width()) && self.height() == old(self.height()) {
        let i = y * self.width + x;
        self.cells.replace(i, v)
    }

    /// Every cell's value, row by row: the cell in column `x` of row `y`
    /// is at `y * width() + x`.
    export fn cells(&self) -> { s: &[T] | s.len() == self.width() * self.height() } {
        self.cells.as_slice()
    }

    /// Each cell's value, row by row.
    export fn iter(&self) -> Iter<T> { self.cells.iter() }

    /// The column of the cell at `i` in `cells()`.
    export fn x_of(
        &self,
        i: { i: usize | i < self.width() * self.height() },
    ) -> { x: usize | x < self.width() } { i % self.width }

    /// The row of the cell at `i` in `cells()`.
    export fn y_of(
        &self,
        i: { i: usize | i < self.width() * self.height() },
    ) -> { y: usize | y < self.height() } { i / self.width }
}

impl<T: Discard> Grid<T> {
    /// Puts `v` in column `x` of row `y`, dropping what was there.
    export fn set(
        &mut self,
        x: { x: usize | x < self.width() },
        y: { y: usize | y < self.height() },
        v: T,
    ) ensures self.width() == old(self.width()) && self.height() == old(self.height()) {
        let _ = self.replace(x, y, v);
    }
}

impl<T: Copy> Grid<T> {
    /// A grid `width` wide and `height` high with `fill` in every cell, or
    /// `None` if it would have more cells than a `usize` can count.
    export fn new(
        width: usize,
        height: usize,
        fill: T,
    ) -> Option<{ g: Grid<T> | g.width() == width && g.height() == height }> with alloc {
        if height == 0 {
            return Some(Grid { width, height, cells: List::new() });
        }
        if width > greatest::<usize>() / height {
            return None;
        }
        Some(Grid { width, height, cells: List::filled(width * height, fill) })
    }

    /// The same grid, again.
    export fn copy(
        &self,
    ) -> { g: Grid<T> | g.width() == self.width() && g.height() == self.height() } with alloc {
        let n = self.cells.len();
        if n == 0 {
            return Grid { width: self.width, height: self.height, cells: List::new() };
        }
        let mut g = Grid {
            width: self.width,
            height: self.height,
            cells: List::filled(n, self.cells[0]),
        };
        let mut i: usize = 1;
        while i < n {
            let _ = g.cells.replace(i, self.cells[i]);
            i = i + 1;
        }
        g
    }
}
