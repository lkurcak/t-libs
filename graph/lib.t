//! A directed graph: nodes numbered `0, 1, ..` in the order they're
//! added, each with a value of type `N`, and edges from one node to
//! another, each with a value of type `E`.
//!
//! ```text
//! let mut g = Graph::new();
//! let a = g.add_node("a");
//! let b = g.add_node("b");
//! g.add_edge(a, b, 5);
//! g.distances(a, |w| *w)   // [Some(0), Some(5)]
//! ```
//!
//! A node's number is less than `node_count()`, which the checker proves
//! of each number the graph is given, so nothing takes a node that isn't
//! there. Nodes aren't removed, so a node's number stays good: every
//! edge's target, and every node a search gives, says so in its type.

use alloc::list::List;
use alloc::raw::out_of_memory;
use core::num::checked_add;
use core::slice::Iter;
use heap::Heap;

/// A node's value and the edges that leave it: each the node it goes to,
/// an `I`, and the edge's value.
#[derive(
    Discard where N: Discard, E: Discard, I: Discard,
    Send where N: Send, E: Send, I: Send,
    Sync where N: Sync, E: Sync, I: Sync,
)]
struct Node<N, E, I> { value: N, out: List<(I, E)> }

/// Nodes with values of type `N`, and edges between them with values of
/// type `E`. Each edge goes to a node: its target is less than how many
/// there are, which `add_edge` proves, and which stays so, as nodes aren't
/// removed (t 0.76.0 says so of what's in the list, and of the list itself).
#[derive(
    Discard where N: Discard, E: Discard,
    Send where N: Send, E: Send,
    Sync where N: Sync, E: Sync,
)]
export struct Graph<N, E> { nodes: List<Node<N, E, { t: usize | t < nodes.len() }>> }

impl<N, E> Graph<N, E> {
    /// A graph with no nodes.
    export fn new() -> { g: Graph<N, E> | g.node_count() == 0 } { Graph { nodes: List::new() } }

    /// How many nodes it has: they're numbered from 0 up to one less.
    #[measure]
    export fn node_count(&self) -> usize { self.nodes.len() }

    /// Adds a node with `value`, and gives its number.
    export fn add_node(&mut self, value: N) -> { id: usize | id < self.node_count() }
    with alloc
    ensures
        self.node_count() == old(self.node_count()) + 1,
    {
        let id = self.nodes.len();
        self.nodes.push(Node { value, out: List::new() });
        id
    }

    /// Node `id`'s value.
    export fn node(&self, id: { id: usize | id < self.node_count() }) -> &N {
        &self.nodes[id].value
    }

    /// Adds an edge from node `from` to node `to`, with `value`. There may
    /// be several from one node to another, and from a node to itself.
    export fn add_edge(
        &mut self,
        from: { v: usize | v < self.node_count() },
        to: { v: usize | v < self.node_count() },
        value: E,
    ) with alloc ensures self.node_count() == old(self.node_count()) {
        // `index_mut` keeps the list's length, whatever's written through
        // what it gives (t 0.75.0), so the node count stays.
        self.nodes[from].out.push((to, value));
    }

    /// Node `id`'s value, to change. What's written through it is an `N`,
    /// so the node count stays.
    export fn node_mut(&mut self, id: { id: usize | id < self.node_count() }) -> &mut N
    ensures
        self.node_count() == old(self.node_count()),
    { &mut self.nodes[id].value }

    /// Gives each node's value to `f`, and each edge's to `g`.
    export fn free_with<effect e, F: FnMut(N) with e + Discard, G: FnMut(E) with e + Discard>(
        self,
        mut f: F,
        mut g: G,
    ) with e {
        self.nodes.free_with(|node| {
            let Node { value, out } = node;
            f(value);
            out.free_with(|(_, e)| g(e));
        });
    }

    /// The edges that leave node `from`, each the node it goes to and its
    /// value, in the order they were added.
    export fn edges(
        &self,
        from: { v: usize | v < self.node_count() },
    ) -> Iter<({ t: usize | t < self.node_count() }, E)> { self.nodes[from].out.iter() }

    /// The nodes `start` reaches: `start` first, then those one edge away,
    /// then those two away, and so on.
    export fn breadth_first(
        &self,
        start: { v: usize | v < self.node_count() },
    ) -> List<{ v: usize | v < self.node_count() }> with alloc {
        let mut seen = List::filled(self.nodes.len(), false);
        seen.set(start, true);
        let mut order: List<{ v: usize | v < self.node_count() }> = List::new();
        order.push(start);
        let mut next: usize = 0;
        while next < order.len() {
            let v = order[next];
            next = next + 1;
            for (t, _) in self.nodes[v].out.iter() {
                if !seen[*t] {
                    seen.set(*t, true);
                    order.push(*t);
                }
            }
        }
        order
    }

    /// The nodes on a path from `from` to `to` with the fewest edges,
    /// `from` and `to` included, or `None` if there's no path.
    export fn shortest_path(
        &self,
        from: { v: usize | v < self.node_count() },
        to: { v: usize | v < self.node_count() },
    ) -> Option<List<{ v: usize | v < self.node_count() }>> with alloc {
        let n = self.nodes.len();
        // `parent[v]` is the node `v` was first reached from; `from`'s is
        // itself.
        let mut parent: List<Option<{ p: usize | p < n }>> = List::filled(n, None);
        parent.set(from, Some(from));
        let mut queue: List<{ v: usize | v < n }> = List::new();
        queue.push(from);
        let mut next: usize = 0;
        while next < queue.len() && parent[to].is_none() {
            let v = queue[next];
            next = next + 1;
            for (t, _) in self.nodes[v].out.iter() {
                if parent[*t].is_none() {
                    parent.set(*t, Some(v));
                    queue.push(*t);
                }
            }
        }
        walk_back(n, &parent, from, to)
    }

    /// The nodes, in an order in which each edge goes forward, or `None`
    /// if there's a cycle, so there's no such order.
    export fn topo_order(&self) -> Option<List<{ v: usize | v < self.node_count() }>> with alloc {
        let n = self.nodes.len();
        // How many edges go into each node that's not yet in the order.
        let mut into = List::filled(n, 0usize);
        for node in self.nodes.iter() {
            for (t, _) in node.out.iter() {
                let k = into[*t];
                // Each edge is in memory, so there can't be more of them
                // than a `usize` counts.
                if k == core::num::greatest::<usize>() {
                    out_of_memory();
                }
                into.set(*t, k + 1);
            }
        }
        let mut order: List<{ v: usize | v < self.node_count() }> = List::new();
        for v in 0..n {
            if into[v] == 0 {
                order.push(v);
            }
        }
        let mut next: usize = 0;
        while next < order.len() {
            let v = order[next];
            next = next + 1;
            for (t, _) in self.nodes[v].out.iter() {
                let k = into[*t];
                // `k > 0`: this edge is one of those counted. T can't say
                // so: it's a count of what's in the lists, not of one.
                if k == 0 {
                    continue;
                }
                into.set(*t, k - 1);
                if k == 1 {
                    order.push(*t);
                }
            }
        }
        if order.len() == n { Some(order) } else { None }
    }

    /// The cost of the cheapest path from `start` to each node, the sum of
    /// `weight` of each of its edges, or `None` for a node `start` doesn't
    /// reach. A path that would cost more than a `u64` counts is taken to
    /// be no path.
    export fn distances<effect e, F: FnMut(&E) -> u64 with e + Discard>(
        &self,
        start: { v: usize | v < self.node_count() },
        weight: F,
    ) -> { d: List<Option<u64>> | d.len() == self.node_count() } with {alloc, e} {
        let Tree { cost, parent: _ } = self.dijkstra(start, weight);
        cost
    }

    /// The cheapest path from `from` to `to`, the sum of `weight` of each
    /// of its edges, and the nodes on it, `from` and `to` included; or
    /// `None` if there's no path.
    export fn cheapest_path<effect e, F: FnMut(&E) -> u64 with e + Discard>(
        &self,
        from: { v: usize | v < self.node_count() },
        to: { v: usize | v < self.node_count() },
        weight: F,
    ) -> Option<(u64, List<{ v: usize | v < self.node_count() }>)> with {alloc, e} {
        let tree = self.dijkstra(from, weight);
        let Some(cost) = tree.cost[to] else { return None };
        let path = walk_back(tree.cost.len(), &tree.parent, from, to)?;
        Some((cost, path))
    }

    /// Dijkstra's algorithm: for each node `start` reaches, the cost of the
    /// cheapest path to it and the node before it on that path.
    fn dijkstra<effect e, F: FnMut(&E) -> u64 with e + Discard>(
        &self,
        start: { v: usize | v < self.node_count() },
        mut weight: F,
    ) -> { t: Tree | t.cost.len() == self.node_count() } with {alloc, e} {
        let n = self.nodes.len();
        let mut cost: List<Option<u64>> = List::filled(n, None);
        let mut parent: List<Option<{ p: usize | p < n }>> = List::filled(n, None);
        let mut done = List::filled(n, false);
        cost.set(start, Some(0));
        parent.set(start, Some(start));
        // Entries `(cost, node)`, cheapest first: each node is one.
        let mut todo: Heap<(u64, { v: usize | v < n })> = Heap::new();
        todo.push((0, start));
        while let Some((d, v)) = todo.pop() {
            if done[v] {
                continue;
            }
            done.set(v, true);
            for (t, w) in self.nodes[v].out.iter() {
                let Some(c) = checked_add(d, weight(w)) else { continue };
                let better = match cost[*t] {
                    Some(old) => c < old,
                    None => true,
                };
                if better {
                    cost.set(*t, Some(c));
                    parent.set(*t, Some(v));
                    todo.push((c, *t));
                }
            }
        }
        Tree { cost, parent }
    }
}

/// What Dijkstra's algorithm finds: for each node, the cost of the
/// cheapest path to it and the node before it on that path, or `None` if
/// it isn't reached.
#[derive(Discard)]
struct Tree {
    cost: List<Option<u64>>,
    parent: { p: List<Option<{ q: usize | q < cost.len() }>> | p.len() == cost.len() },
}

/// The path from `from` to `to`, following from `to` the node before each
/// in `parent` back to `from`; or `None` if `to` wasn't reached. Each node
/// is one of the `n`.
fn walk_back(
    n: usize,
    parent: &{ p: List<Option<{ q: usize | q < n }>> | p.len() == n },
    from: usize,
    to: { t: usize | t < n },
) -> Option<List<{ v: usize | v < n }>> with alloc {
    let mut path: List<{ v: usize | v < n }> = List::new();
    let mut v: { v: usize | v < n } = to;
    loop {
        path.push(v);
        if v == from {
            break;
        }
        let Some(p) = parent[v] else { return None };
        v = p;
    }
    // It was made from `to` back: turn it round.
    let len = path.len();
    let mut i: usize = 0;
    while i < len / 2 invariant len == path.len() {
        path.swap(i, len - 1 - i);
        i = i + 1;
    }
    Some(path)
}
