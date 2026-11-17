//! Structural checks for the serialized interaction graphs of pinned Rapier 0.36.0.
//! Rapier exposes endpoints but keeps adjacency links private. Read its serde layout
//! into a bounded inspection view; never repair or rebuild the candidate's contacts.
use crate::world::{Error, MAX_BODIES, Result};
use bincode::Options;
use rapier3d::{geometry::InteractionGraph, prelude::*};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use std::collections::BTreeSet;

#[derive(Serialize, Deserialize)]
struct GraphNode {
    weight: ColliderHandle,
    next: [u32; 2],
}
#[derive(Serialize, Deserialize)]
struct GraphEdge<E> {
    weight: E,
    next: [u32; 2],
    prev: [u32; 2],
    node: [u32; 2],
}
#[derive(Serialize, Deserialize)]
struct GraphView<E> {
    nodes: Vec<GraphNode>,
    edges: Vec<GraphEdge<E>>,
}

pub(crate) fn validate<E: Serialize + DeserializeOwned>(
    graph: &InteractionGraph<ColliderHandle, E>,
    world: &PhysicsWorld,
    check_pair: impl Fn(ColliderHandle, ColliderHandle, &E) -> bool,
) -> Result<()> {
    let codec = || {
        bincode::DefaultOptions::new()
            .with_fixint_encoding()
            .with_limit(crate::world::MAX_SNAPSHOT_BYTES as u64)
            .reject_trailing_bytes()
    };
    let bytes = codec()
        .serialize(graph.raw_graph())
        .map_err(|_| Error("snapshot_contact_graph"))?;
    let view: GraphView<E> = codec()
        .deserialize(&bytes)
        .map_err(|_| Error("snapshot_contact_graph"))?;
    validate_view(&view, world, check_pair)
}

fn validate_view<E>(
    view: &GraphView<E>,
    world: &PhysicsWorld,
    check_pair: impl Fn(ColliderHandle, ColliderHandle, &E) -> bool,
) -> Result<()> {
    let invalid = || Error("snapshot_contact_graph");
    if view.nodes.len() > MAX_BODIES || view.edges.len() > MAX_BODIES * (MAX_BODIES - 1) / 2 {
        return Err(invalid());
    }
    let mut handles = BTreeSet::new();
    for node in &view.nodes {
        if world.colliders.get(node.weight).is_none()
            || !handles.insert(node.weight.into_raw_parts())
        {
            return Err(invalid());
        }
    }
    let mut pairs = BTreeSet::new();
    for edge in &view.edges {
        let a = view.nodes.get(edge.node[0] as usize).ok_or_else(invalid)?;
        let b = view.nodes.get(edge.node[1] as usize).ok_or_else(invalid)?;
        if edge.node[0] == edge.node[1]
            || !pairs.insert((
                edge.node[0].min(edge.node[1]),
                edge.node[0].max(edge.node[1]),
            ))
            || !check_pair(a.weight, b.weight, &edge.weight)
        {
            return Err(invalid());
        }
    }
    // Each edge must occur exactly once in each directed adjacency list.
    // Check bounds before following a link, and reject cycles instead of iterating them.
    let mut seen = vec![[false; 2]; view.edges.len()];
    for (index, node) in view.nodes.iter().enumerate() {
        for side in 0..2 {
            let mut previous = u32::MAX;
            let mut next = node.next[side];
            while next != u32::MAX {
                let edge = view.edges.get(next as usize).ok_or_else(invalid)?;
                if seen[next as usize][side]
                    || edge.node[side] as usize != index
                    || edge.prev[side] != previous
                {
                    return Err(invalid());
                }
                seen[next as usize][side] = true;
                previous = next;
                next = edge.next[side];
            }
        }
    }
    if seen.iter().any(|s| *s != [true; 2]) {
        return Err(invalid());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn graph_rejects_bad_endpoints_links_cycles_and_handles() {
        let mut world = PhysicsWorld::new();
        let (_, a) = world.insert(
            RigidBodyBuilder::dynamic(),
            ColliderBuilder::cuboid(1.0, 1.0, 1.0),
        );
        let (_, b) = world.insert(
            RigidBodyBuilder::dynamic(),
            ColliderBuilder::cuboid(1.0, 1.0, 1.0),
        );
        let make = || GraphView {
            nodes: vec![
                GraphNode {
                    weight: a,
                    next: [0, u32::MAX],
                },
                GraphNode {
                    weight: b,
                    next: [u32::MAX, 0],
                },
            ],
            edges: vec![GraphEdge {
                weight: (),
                next: [u32::MAX; 2],
                prev: [u32::MAX; 2],
                node: [0, 1],
            }],
        };
        assert!(validate_view(&make(), &world, |_, _, _| true).is_ok());
        // Exercise the actual serde view against Rapier's pinned layout too.
        let bytes = bincode::DefaultOptions::new()
            .with_fixint_encoding()
            .serialize(&make())
            .unwrap();
        let native: InteractionGraph<ColliderHandle, ()> = bincode::DefaultOptions::new()
            .with_fixint_encoding()
            .deserialize(&bytes)
            .unwrap();
        assert!(validate(&native, &world, |_, _, _| true).is_ok());
        for case in 0..8 {
            let mut v = make();
            match case {
                0 => v.edges[0].node[1] = u32::MAX,
                1 => v.edges[0].node[1] = 0,
                2 => v.nodes[0].next[0] = 99,
                3 => v.edges[0].next[0] = 0,
                4 => v.edges[0].prev[1] = 0,
                5 => v.nodes[1].next[1] = u32::MAX,
                6 => v.nodes[1].weight = a,
                _ => v.nodes[1].weight = ColliderHandle::invalid(),
            }
            assert_eq!(
                validate_view(&v, &world, |_, _, _| true),
                Err(Error("snapshot_contact_graph")),
                "case {case}"
            );
        }
    }
}
