use crate::world::{self, BoxSpec, Error, Key, ObjectWorld, Sample};
use godot::classes::{IRefCounted, RefCounted};
use godot::prelude::*;

struct ObjectWorldExtension;
#[gdextension]
unsafe impl ExtensionLibrary for ObjectWorldExtension {}

/// One mutable Rapier world per instance, owned by its scene/controller.
/// Does not register a global physics backend and does not hold Godot RIDs.
#[derive(GodotClass)]
#[class(base=RefCounted)]
struct SahurObjectWorld {
    base: Base<RefCounted>,
    core: ObjectWorld,
    last_error: GString,
}

#[godot_api]
impl IRefCounted for SahurObjectWorld {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            base,
            core: ObjectWorld::default(),
            last_error: GString::new(),
        }
    }
}

fn key(uid: i64, epoch: i64) -> world::Result<Key> {
    let uid = u32::try_from(uid).map_err(|_| Error("invalid_identity"))?;
    let epoch = u32::try_from(epoch).map_err(|_| Error("invalid_identity"))?;
    Key::new(uid, epoch)
}
fn vector(v: Vector3) -> [f32; 3] {
    [v.x, v.y, v.z]
}
fn v3(v: [f32; 3]) -> Vector3 {
    Vector3::new(v[0], v[1], v[2])
}
fn native_pose(t: Transform3D) -> world::Result<rapier3d::prelude::Pose> {
    let b = t.basis;
    if !b.is_finite() || (b.determinant() - 1.0).abs() > 0.00001 {
        return Err(Error("invalid_pose"));
    }
    for i in 0..3 {
        if (b.rows[i].length_squared() - 1.0).abs() > 0.00001 {
            return Err(Error("invalid_pose"));
        }
        for j in (i + 1)..3 {
            if b.rows[i].dot(b.rows[j]).abs() > 0.00001 {
                return Err(Error("invalid_pose"));
            }
        }
    }
    let q = b.get_quaternion();
    world::pose(vector(t.origin), [q.x, q.y, q.z, q.w])
}
fn dictionary(sample: Sample) -> VarDictionary {
    let mut out = VarDictionary::new();
    out.set("uid", sample.key.uid as i64);
    out.set("epoch", sample.key.epoch as i64);
    out.set("tick", sample.tick as i64);
    let p = sample.pose;
    let rotation = Quaternion::new(p[3], p[4], p[5], p[6]);
    out.set(
        "pose",
        Transform3D::new(
            Basis::from_quaternion(rotation),
            Vector3::new(p[0], p[1], p[2]),
        ),
    );
    out.set("lv", v3(sample.linear));
    out.set("av", v3(sample.angular));
    out.set("sleeping", sample.sleeping);
    out.set("held", sample.held);
    let mut contacts = Array::<VarDictionary>::new();
    for k in sample.contacts {
        let mut item = VarDictionary::new();
        item.set("uid", k.uid as i64);
        item.set("epoch", k.epoch as i64);
        contacts.push(&item);
    }
    out.set("contacts", &contacts);
    out
}

impl SahurObjectWorld {
    fn run<T>(
        &mut self,
        operation: impl FnOnce(&mut ObjectWorld) -> world::Result<T>,
    ) -> Option<T> {
        match operation(&mut self.core) {
            Ok(value) => {
                self.last_error = GString::new();
                Some(value)
            }
            Err(error) => {
                self.last_error = GString::from(error.0);
                None
            }
        }
    }
}

#[godot_api]
impl SahurObjectWorld {
    #[func]
    fn get_last_error(&self) -> GString {
        self.last_error.clone()
    }
    #[func]
    fn get_tick(&self) -> i64 {
        self.core.tick() as i64
    }
    #[func]
    fn get_body_count(&self) -> i64 {
        self.core.body_count() as i64
    }
    #[func]
    fn get_cache_stats(&self) -> VarDictionary {
        let (count, bytes) = self.core.cache_stats();
        let mut out = VarDictionary::new();
        out.set("count", count as i64);
        out.set("bytes", bytes as i64);
        out
    }
    #[func]
    fn get_build_info(&self) -> VarDictionary {
        let mut out = VarDictionary::new();
        out.set("schema", 1);
        out.set("rapier", "0.36.0");
        out.set("godot_api", "4.7");
        out.set("max_bodies", world::MAX_BODIES as i64);
        out.set("max_snapshot_bytes", world::MAX_SNAPSHOT_BYTES as i64);
        out.set("global_physics_server", false);
        out.set("single_thread", true);
        out
    }
    #[func]
    fn add_box(
        &mut self,
        uid: i64,
        epoch: i64,
        size: Vector3,
        mass: f64,
        initial: Transform3D,
    ) -> bool {
        self.run(|w| {
            if !mass.is_finite() || (mass != 0.0 && !(0.001..=1_000_000.0).contains(&mass)) {
                return Err(Error("invalid_box"));
            }
            w.add_box(
                key(uid, epoch)?,
                BoxSpec::new(vector(size), mass as f32),
                native_pose(initial)?,
            )
        })
        .is_some()
    }
    #[func]
    fn remove_body(&mut self, uid: i64, epoch: i64) -> bool {
        self.run(|w| w.remove(key(uid, epoch)?)).is_some()
    }
    #[func]
    fn seal_topology(&mut self, context_revision: i64) -> bool {
        self.run(|w| w.seal(u64::try_from(context_revision).map_err(|_| Error("invalid_context"))?))
            .is_some()
    }
    #[func]
    fn begin_hold(&mut self, uid: i64, epoch: i64, anchor: Vector3, goal: Transform3D) -> bool {
        self.run(|w| w.begin_hold(key(uid, epoch)?, vector(anchor), native_pose(goal)?))
            .is_some()
    }
    #[func]
    fn set_goal(&mut self, uid: i64, epoch: i64, goal: Transform3D) -> bool {
        self.run(|w| w.set_goal(key(uid, epoch)?, native_pose(goal)?))
            .is_some()
    }
    #[func]
    fn release_body(&mut self, uid: i64, epoch: i64, impulse: Vector3) -> bool {
        self.run(|w| w.release(key(uid, epoch)?, vector(impulse)))
            .is_some()
    }
    #[func]
    fn apply_impulse(&mut self, uid: i64, epoch: i64, impulse: Vector3) -> bool {
        self.run(|w| w.impulse(key(uid, epoch)?, vector(impulse)))
            .is_some()
    }
    #[func]
    fn step(&mut self, dt: f64) -> bool {
        self.run(|w| w.step(dt as f32)).is_some()
    }
    #[func]
    fn sample(&mut self, uid: i64, epoch: i64) -> VarDictionary {
        self.run(|w| w.sample(key(uid, epoch)?))
            .map(dictionary)
            .unwrap_or_default()
    }
    #[func]
    fn samples(&self) -> Array<VarDictionary> {
        let mut out = Array::new();
        for s in self.core.samples() {
            out.push(&dictionary(s));
        }
        out
    }
    #[func]
    fn cast_ray(&mut self, origin: Vector3, direction: Vector3, distance: f64) -> VarDictionary {
        let hit = self.run(|w| w.ray(vector(origin), vector(direction), distance as f32));
        let mut out = VarDictionary::new();
        if let Some(Some((key, toi))) = hit {
            out.set("uid", key.uid as i64);
            out.set("epoch", key.epoch as i64);
            out.set("distance", toi as f64);
        }
        out
    }
    #[func]
    fn snapshot_trusted(&mut self) -> PackedByteArray {
        self.run(|w| w.snapshot())
            .map(PackedByteArray::from)
            .unwrap_or_default()
    }
    #[func]
    fn restore_trusted(&mut self, snapshot: PackedByteArray) -> bool {
        self.run(|w| w.restore_trusted(snapshot.as_slice()))
            .is_some()
    }
    #[func]
    fn cache_checkpoint(&mut self) -> i64 {
        self.run(|w| w.cache_checkpoint())
            .map(|tick| tick as i64)
            .unwrap_or(-1)
    }
    #[func]
    fn restore_cached(&mut self, tick: i64) -> bool {
        self.run(|w| w.restore_cached(u64::try_from(tick).map_err(|_| Error("invalid_tick"))?))
            .is_some()
    }
}
