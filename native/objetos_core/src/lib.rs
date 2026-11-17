//! Scene-owned object physics. No global Godot PhysicsServer registration.
#[cfg(feature = "extension")]
mod extension;
pub mod world;
