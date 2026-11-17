//! Scene-owned object physics. No global Godot PhysicsServer registration.
#[cfg(feature = "extension")]
mod extension;
mod snapshot_graph;
pub mod world;
