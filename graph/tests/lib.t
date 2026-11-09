//! Uses the graph as a dependent would: only what it exports. `t test
//! graph/tests/lib.t` runs each test.

use alloc::list::List;
use graph::Graph;

/// The numbers `add_node` gives are nodes, so they're good for `add_edge`,
/// with no check: it says how many nodes there are after, and `add_edge`
/// that it adds none.
fn diamond() -> { g: Graph<char, u64> | g.node_count() == 5 } with alloc {
    //   a → b
    //   ↓   ↓
    //   c → d     and e on its own
    let mut g = Graph::new();
    let a = g.add_node('a');
    let b = g.add_node('b');
    let c = g.add_node('c');
    let d = g.add_node('d');
    let _e = g.add_node('e');
    g.add_edge(a, b, 1);
    g.add_edge(a, c, 4);
    g.add_edge(b, d, 5);
    g.add_edge(c, d, 1);
    g
}

fn list(s: &[usize]) -> List<usize> with alloc {
    let mut l = List::new();
    for v in s.iter() {
        l.push(*v);
    }
    l
}

#[test]
fn nodes_and_edges() {
    let g = diamond();
    assert_eq(&g.node_count(), &5);
    assert_eq(g.node(3), &'d');
    let mut to: List<usize> = List::new();
    for (t, w) in g.edges(0) {
        to.push(*t);
        assert(*w > 0);
    }
    assert_eq(&to, &list([1usize, 2].as_slice()));
    assert_eq(&g.edges(4).count(), &0);
}

#[test]
fn breadth_first() {
    let g = diamond();
    assert_eq(&g.breadth_first(0), &list([0usize, 1, 2, 3].as_slice()));
    assert_eq(&g.breadth_first(2), &list([2usize, 3].as_slice()));
    assert_eq(&g.breadth_first(4), &list([4usize].as_slice()));
}

#[test]
fn shortest_path() {
    let g = diamond();
    assert_eq(&g.shortest_path(0, 3), &Some(list([0usize, 1, 3].as_slice())));
    assert_eq(&g.shortest_path(0, 0), &Some(list([0usize].as_slice())));
    assert_eq(&g.shortest_path(3, 0), &None);
    assert_eq(&g.shortest_path(0, 4), &None);
}

#[test]
fn cheapest() {
    let g = diamond();
    let d = g.distances(0, |w| *w);
    assert_eq(&d[0], &Some(0));
    assert_eq(&d[1], &Some(1));
    assert_eq(&d[2], &Some(4));
    assert_eq(&d[3], &Some(5));
    assert_eq(&d[4], &None);
    // Through c is cheaper than through b, though both are two edges.
    assert_eq(&g.cheapest_path(0, 3, |w| *w), &Some((5, list([0usize, 2, 3].as_slice()))));
    // Every edge costing the same: the fewest edges.
    let Some((cost, _)) = g.cheapest_path(0, 3, |_| 7) else { panic("d is reached") };
    assert_eq(&cost, &14);
    assert_eq(&g.cheapest_path(0, 4, |w| *w), &None);
}

/// A path that would cost more than a `u64` counts is no path.
#[test]
fn too_costly() {
    let mut g = Graph::new();
    let a = g.add_node(());
    let b = g.add_node(());
    let c = g.add_node(());
    g.add_edge(a, b, core::num::greatest::<u64>());
    g.add_edge(b, c, 1);
    assert_eq(&g.cheapest_path(a, b, |w| *w).is_some(), &true);
    assert_eq(&g.cheapest_path(a, c, |w| *w), &None);
}

#[test]
fn topo_order() {
    let g = diamond();
    let Some(order) = g.topo_order() else { panic("no cycle") };
    assert_eq(&order, &list([0usize, 4, 1, 2, 3].as_slice()));
    let mut cyclic: Graph<(), ()> = Graph::new();
    let a = cyclic.add_node(());
    let b = cyclic.add_node(());
    let c = cyclic.add_node(());
    cyclic.add_edge(a, b, ());
    cyclic.add_edge(b, c, ());
    cyclic.add_edge(c, a, ());
    assert(cyclic.topo_order().is_none());
}

#[test]
fn node_values_change() {
    let mut g: Graph<u32, ()> = Graph::new();
    let a = g.add_node(1);
    *g.node_mut(a) = 2;
    // `node_mut`'s result borrows `g`, so the checker forgets how many
    // nodes `g` has, though a `&mut u32` can't change it (FRICTION.md).
    if a < g.node_count() {
        assert_eq(g.node(a), &2);
    }
}

/// Values that must be used up, not dropped.
struct Token { n: u32 }

fn spend(t: Token) -> u32 {
    let Token { n } = t;
    n
}

#[test]
fn linear_values() {
    let mut g = Graph::new();
    let a = g.add_node(Token { n: 1 });
    let b = g.add_node(Token { n: 2 });
    g.add_edge(a, b, Token { n: 10 });
    g.add_edge(b, b, Token { n: 20 });
    let mut nodes: u32 = 0;
    let mut edges: u32 = 0;
    g.free_with(|t| nodes = nodes + spend(t), |t| edges = edges + spend(t));
    assert_eq(&nodes, &3);
    assert_eq(&edges, &30);
}
