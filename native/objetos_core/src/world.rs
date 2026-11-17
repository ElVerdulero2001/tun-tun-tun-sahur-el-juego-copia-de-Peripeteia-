use bincode::Options;
use rapier3d::prelude::*;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};

pub const MAX_BODIES: usize = 128;
pub const MAX_SNAPSHOT_BYTES: usize = 1_048_576;
pub const MAX_CACHED_TICKS: usize = 120;
const MAX_CACHE_BYTES: usize = 16 * MAX_SNAPSHOT_BYTES;
const MAGIC: &[u8; 8] = b"SOBJW001";
const HEADER: usize = 44;
const MODEL: &str =
    "rapier-0.36.0:f32:single-thread:enhanced-determinism:box-center:hand-v1:codec-v1";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Error(pub &'static str);
pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub struct Key {
    pub uid: u32,
    pub epoch: u32,
}
impl Key {
    pub fn new(uid: u32, epoch: u32) -> Result<Self> {
        if uid == 0 || epoch == 0 || uid > i32::MAX as u32 || epoch > i32::MAX as u32 {
            return Err(Error("invalid_identity"));
        }
        Ok(Self { uid, epoch })
    }
    fn tag(self) -> u128 {
        ((self.uid as u128) << 32) | self.epoch as u128
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct BoxSpec {
    pub size: [f32; 3],
    /// Zero mass denotes a fixed body. Dynamic masses must be positive.
    pub mass: f32,
    pub friction: f32,
    pub restitution: f32,
    pub linear_damping: f32,
    pub angular_damping: f32,
}
impl BoxSpec {
    pub fn new(size: [f32; 3], mass: f32) -> Self {
        Self {
            size,
            mass,
            friction: 0.8,
            restitution: 0.05,
            linear_damping: 0.1,
            angular_damping: 2.0,
        }
    }
    fn valid(&self) -> bool {
        self.size
            .iter()
            .all(|v| v.is_finite() && *v >= 0.0001 && *v <= 1000.0)
            && self.mass.is_finite()
            && (self.mass == 0.0 || (0.001..=1_000_000.0).contains(&self.mass))
            && self.friction.is_finite()
            && (0.0..=10.0).contains(&self.friction)
            && self.restitution.is_finite()
            && (0.0..=1.0).contains(&self.restitution)
            && [self.linear_damping, self.angular_damping]
                .iter()
                .all(|x| x.is_finite() && (0.0..=100.0).contains(x))
    }
}

#[derive(Clone, Serialize, Deserialize)]
struct Hold {
    anchor: [f32; 3],
    goal: [f32; 7],
}
#[derive(Clone, Serialize, Deserialize)]
struct Entry {
    spec: BoxSpec,
    fixed_pose: Option<[f32; 7]>,
    body: RigidBodyHandle,
    collider: ColliderHandle,
    hold: Option<Hold>,
}
#[derive(Serialize, Deserialize)]
struct State {
    model: [u8; 32],
    world: PhysicsWorld,
    objects: BTreeMap<Key, Entry>,
    retired: BTreeMap<u32, u32>,
    tick: u64,
    context_revision: Option<u64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Sample {
    pub key: Key,
    pub tick: u64,
    pub pose: [f32; 7],
    pub linear: [f32; 3],
    pub angular: [f32; 3],
    pub sleeping: bool,
    pub held: bool,
    pub contacts: Vec<Key>,
}

pub struct ObjectWorld {
    state: State,
    cache: BTreeMap<u64, Vec<u8>>,
    cache_bytes: usize,
}
impl Default for ObjectWorld {
    fn default() -> Self {
        let mut world = PhysicsWorld::new();
        world.gravity = Vector::new(0.0, -9.8, 0.0);
        world.integration_parameters.dt = 1.0 / 60.0;
        Self {
            state: State {
                model: Sha256::digest(MODEL.as_bytes()).into(),
                world,
                objects: BTreeMap::new(),
                retired: BTreeMap::new(),
                tick: 0,
                context_revision: None,
            },
            cache: BTreeMap::new(),
            cache_bytes: 0,
        }
    }
}

pub fn pose(position: [f32; 3], rotation: [f32; 4]) -> Result<Pose> {
    let p = Vector::from_array(position);
    let q = Rotation::from_array(rotation);
    if !p.is_finite()
        || p.abs().max_element() > 1_000_000.0
        || !q.is_finite()
        || (q.length_squared() - 1.0).abs() > 0.00001
    {
        return Err(Error("invalid_pose"));
    }
    Ok(Pose::from_parts(p, q.normalize()))
}
pub fn pack_pose(p: &Pose) -> [f32; 7] {
    let q = p.rotation.to_array();
    [
        p.translation.x,
        p.translation.y,
        p.translation.z,
        q[0],
        q[1],
        q[2],
        q[3],
    ]
}
fn unpack_pose(v: [f32; 7]) -> Result<Pose> {
    pose([v[0], v[1], v[2]], [v[3], v[4], v[5], v[6]])
}
fn codec() -> impl Options {
    bincode::DefaultOptions::new()
        .with_fixint_encoding()
        .with_limit(MAX_SNAPSHOT_BYTES as u64)
        .reject_trailing_bytes()
}

impl ObjectWorld {
    pub fn tick(&self) -> u64 {
        self.state.tick
    }
    pub fn body_count(&self) -> usize {
        self.state.objects.len()
    }
    pub fn cache_stats(&self) -> (usize, usize) {
        (self.cache.len(), self.cache_bytes)
    }

    pub fn add_box(&mut self, key: Key, spec: BoxSpec, initial: Pose) -> Result<()> {
        Key::new(key.uid, key.epoch)?;
        unpack_pose(pack_pose(&initial))?;
        if !spec.valid() {
            return Err(Error("invalid_box"));
        }
        if self.state.context_revision.is_some() {
            return Err(Error("sealed_topology"));
        }
        if self.body_count() >= MAX_BODIES {
            return Err(Error("body_capacity"));
        }
        if self.state.objects.keys().any(|k| k.uid == key.uid) {
            return Err(Error("identity_in_use"));
        }
        if self
            .state
            .retired
            .get(&key.uid)
            .is_some_and(|epoch| key.epoch <= *epoch)
        {
            return Err(Error("retired_identity"));
        }
        let fixed = spec.mass == 0.0;
        let builder = if fixed {
            RigidBodyBuilder::fixed()
        } else {
            RigidBodyBuilder::dynamic()
        };
        let builder = builder
            .pose(initial)
            .user_data(key.tag())
            .ccd_enabled(!fixed)
            .linear_damping(spec.linear_damping)
            .angular_damping(spec.angular_damping);
        let collider =
            ColliderBuilder::cuboid(spec.size[0] * 0.5, spec.size[1] * 0.5, spec.size[2] * 0.5)
                .mass(if fixed { 1.0 } else { spec.mass })
                .friction(spec.friction)
                .restitution(spec.restitution)
                .user_data(key.tag());
        let (body, collider) = self.state.world.insert(builder, collider);
        self.state.objects.insert(
            key,
            Entry {
                spec,
                fixed_pose: fixed.then(|| pack_pose(&initial)),
                body,
                collider,
                hold: None,
            },
        );
        Ok(())
    }

    pub fn remove(&mut self, key: Key) -> Result<()> {
        if self.state.context_revision.is_some() {
            return Err(Error("sealed_topology"));
        }
        if !self.state.objects.contains_key(&key) {
            return Err(Error("unknown_identity"));
        }
        if !self.state.retired.contains_key(&key.uid) && self.state.retired.len() >= 512 {
            return Err(Error("retired_capacity"));
        }
        let entry = self.state.objects.remove(&key).unwrap();
        self.state
            .retired
            .entry(key.uid)
            .and_modify(|epoch| *epoch = (*epoch).max(key.epoch))
            .or_insert(key.epoch);
        self.state.world.remove_body(entry.body);
        Ok(())
    }

    pub fn seal(&mut self, context_revision: u64) -> Result<()> {
        if context_revision == 0 || context_revision > i64::MAX as u64 {
            return Err(Error("invalid_context"));
        }
        if self
            .state
            .context_revision
            .is_some_and(|r| r != context_revision)
        {
            return Err(Error("sealed_topology"));
        }
        self.state.context_revision = Some(context_revision);
        Ok(())
    }

    pub fn begin_hold(&mut self, key: Key, anchor: [f32; 3], goal: Pose) -> Result<()> {
        unpack_pose(pack_pose(&goal))?;
        if !Vector::from_array(anchor).is_finite()
            || Vector::from_array(anchor).abs().max_element() > 1000.0
        {
            return Err(Error("invalid_anchor"));
        }
        let entry = self
            .state
            .objects
            .get_mut(&key)
            .ok_or(Error("unknown_identity"))?;
        if entry.spec.mass == 0.0 || entry.hold.is_some() {
            return Err(Error("invalid_hold_transition"));
        }
        entry.hold = Some(Hold {
            anchor,
            goal: pack_pose(&goal),
        });
        let body = &mut self.state.world.bodies[entry.body];
        body.set_gravity_scale(0.0, true);
        body.set_linear_damping(0.0);
        body.set_angular_damping(0.0);
        body.activation_mut().normalized_linear_threshold = -1.0;
        body.activation_mut().angular_threshold = -1.0;
        body.wake_up(true);
        Ok(())
    }

    pub fn set_goal(&mut self, key: Key, goal: Pose) -> Result<()> {
        unpack_pose(pack_pose(&goal))?;
        self.state
            .objects
            .get_mut(&key)
            .and_then(|e| e.hold.as_mut())
            .ok_or(Error("not_held"))?
            .goal = pack_pose(&goal);
        Ok(())
    }

    pub fn release(&mut self, key: Key, impulse: [f32; 3]) -> Result<()> {
        let impulse = Vector::from_array(impulse);
        if !impulse.is_finite() || impulse.abs().max_element() > 100_000.0 {
            return Err(Error("invalid_impulse"));
        }
        let entry = self
            .state
            .objects
            .get_mut(&key)
            .ok_or(Error("unknown_identity"))?;
        if entry.hold.is_none() {
            return Err(Error("not_held"));
        }
        entry.hold = None;
        let body = &mut self.state.world.bodies[entry.body];
        body.set_gravity_scale(1.0, true);
        body.set_linear_damping(entry.spec.linear_damping);
        body.set_angular_damping(entry.spec.angular_damping);
        *body.activation_mut() = RigidBodyActivation::active();
        body.apply_impulse(impulse, true);
        Ok(())
    }

    pub fn impulse(&mut self, key: Key, impulse: [f32; 3]) -> Result<()> {
        let v = Vector::from_array(impulse);
        if !v.is_finite() || v.abs().max_element() > 100_000.0 {
            return Err(Error("invalid_impulse"));
        }
        let entry = self
            .state
            .objects
            .get(&key)
            .ok_or(Error("unknown_identity"))?;
        if entry.spec.mass == 0.0 {
            return Err(Error("fixed_body"));
        }
        self.state.world.bodies[entry.body].apply_impulse(v, true);
        Ok(())
    }

    pub fn step(&mut self, dt: f32) -> Result<()> {
        if !dt.is_finite() || dt <= 0.0 || dt > 1.0 / 30.0 {
            return Err(Error("invalid_dt"));
        }
        if self.tick() >= i64::MAX as u64 {
            return Err(Error("tick_limit"));
        }
        for entry in self.state.objects.values() {
            if let Some(hold) = &entry.hold {
                let goal = unpack_pose(hold.goal)?;
                let body = &mut self.state.world.bodies[entry.body];
                // Center-origin boxes: local COM = zero. No render offset is used.
                let wanted = goal.translation - goal.rotation * Vector::from_array(hold.anchor);
                let desired = ((wanted - body.center_of_mass()) / 0.08).clamp_length_max(12.0);
                body.set_linvel(
                    body.linvel() + (desired - body.linvel()).clamp_length_max(80.0 * dt),
                    true,
                );
                let mut error = goal.rotation * body.rotation().inverse();
                if error.w < 0.0 {
                    error = -error;
                }
                let (axis, angle) = error.to_axis_angle();
                let wanted_spin = if angle > 0.0001 {
                    (axis * (angle / 0.08)).clamp_length_max(4.0 * std::f32::consts::PI)
                } else {
                    Vector::ZERO
                };
                let angular = body.angvel()
                    + (wanted_spin - body.angvel())
                        .clamp_length_max(40.0 * std::f32::consts::PI * dt);
                body.set_angvel(angular, true);
            }
        }
        self.state.world.integration_parameters.dt = dt;
        self.state.world.step();
        self.state.tick += 1;
        Ok(())
    }

    pub fn sample(&self, key: Key) -> Result<Sample> {
        let entry = self
            .state
            .objects
            .get(&key)
            .ok_or(Error("unknown_identity"))?;
        let body = &self.state.world.bodies[entry.body];
        let contacts: BTreeSet<_> = self
            .state
            .world
            .contact_pairs_with(entry.collider)
            .filter(|pair| pair.has_any_active_contact())
            .filter_map(|pair| {
                let other = if pair.collider1 == entry.collider {
                    pair.collider2
                } else {
                    pair.collider1
                };
                self.state
                    .objects
                    .iter()
                    .find(|(_, e)| e.collider == other)
                    .map(|(key, _)| *key)
            })
            .collect();
        Ok(Sample {
            key,
            tick: self.tick(),
            pose: pack_pose(body.position()),
            linear: body.linvel().to_array(),
            angular: body.angvel().to_array(),
            sleeping: body.is_sleeping(),
            held: entry.hold.is_some(),
            contacts: contacts.into_iter().collect(),
        })
    }

    pub fn samples(&self) -> Vec<Sample> {
        self.state
            .objects
            .keys()
            .map(|k| self.sample(*k).expect("owned handle"))
            .collect()
    }

    pub fn ray(
        &self,
        from: [f32; 3],
        direction: [f32; 3],
        distance: f32,
    ) -> Result<Option<(Key, f32)>> {
        let origin = Vector::from_array(from);
        let dir = Vector::from_array(direction);
        if !origin.is_finite()
            || !dir.is_finite()
            || dir.length_squared() < 0.000001
            || !distance.is_finite()
            || distance <= 0.0
            || distance > 100_000.0
        {
            return Err(Error("invalid_ray"));
        }
        // Query owned native shapes directly, including newly created bodies.
        // Collision-only updates before the first full step can consume body
        // change flags needed by the dynamics pipeline (notably mass setup).
        let ray = Ray::new(origin, dir.normalize());
        let mut best: Option<(Key, f32)> = None;
        for (key, entry) in &self.state.objects {
            let body = &self.state.world.bodies[entry.body];
            let collider = &self.state.world.colliders[entry.collider];
            if let Some(toi) = collider
                .shape()
                .cast_ray(body.position(), &ray, distance, true)
            {
                if best.is_none_or(|(_, old)| toi < old) {
                    best = Some((*key, toi));
                }
            }
        }
        Ok(best)
    }

    pub fn snapshot(&self) -> Result<Vec<u8>> {
        if self.state.context_revision.is_none() {
            return Err(Error("unsealed_topology"));
        }
        let payload = codec()
            .serialize(&self.state)
            .map_err(|_| Error("snapshot_too_large"))?;
        if payload.len() > MAX_SNAPSHOT_BYTES {
            return Err(Error("snapshot_too_large"));
        }
        let mut bytes = Vec::with_capacity(payload.len() + HEADER);
        bytes.extend_from_slice(MAGIC);
        bytes.extend_from_slice(&(payload.len() as u32).to_le_bytes());
        bytes.extend_from_slice(&Sha256::digest(&payload));
        bytes.extend_from_slice(&payload);
        Ok(bytes)
    }

    /// Trusted local/authority data only. Not a decoder for arbitrary client packets.
    /// Construct and validate a candidate before replacing any live state.
    pub fn restore_trusted(&mut self, bytes: &[u8]) -> Result<()> {
        self.restore_impl(bytes, false)
    }

    fn restore_impl(&mut self, bytes: &[u8], keep_past_cache: bool) -> Result<()> {
        if bytes.len() < HEADER || bytes.len() > MAX_SNAPSHOT_BYTES + HEADER || &bytes[..8] != MAGIC
        {
            return Err(Error("invalid_snapshot_envelope"));
        }
        let len = u32::from_le_bytes(bytes[8..12].try_into().unwrap()) as usize;
        let payload = &bytes[HEADER..];
        if len != payload.len() || &Sha256::digest(payload)[..] != &bytes[12..HEADER] {
            return Err(Error("snapshot_checksum"));
        }
        let candidate: State = codec()
            .deserialize(payload)
            .map_err(|_| Error("snapshot_decode"))?;
        self.validate_candidate(&candidate)?;
        self.state = candidate;
        if keep_past_cache {
            let future: Vec<_> = self
                .cache
                .range((self.tick() + 1)..)
                .map(|(k, _)| *k)
                .collect();
            for tick in future {
                self.cache_bytes -= self.cache.remove(&tick).unwrap().len();
            }
        } else {
            // An authoritative branch must not keep checkpoints from the old prediction.
            self.cache.clear();
            self.cache_bytes = 0;
        }
        Ok(())
    }

    fn validate_candidate(&self, candidate: &State) -> Result<()> {
        if candidate.model != self.state.model
            || self.state.context_revision.is_none()
            || candidate.context_revision != self.state.context_revision
            || candidate.tick > i64::MAX as u64
        {
            return Err(Error("snapshot_model_or_context"));
        }
        if candidate.retired.len() > 512
            || candidate
                .retired
                .iter()
                .any(|(uid, epoch)| Key::new(*uid, *epoch).is_err())
            || candidate.objects.keys().any(|key| {
                candidate
                    .retired
                    .get(&key.uid)
                    .is_some_and(|epoch| key.epoch <= *epoch)
            })
        {
            return Err(Error("snapshot_retired_identity"));
        }
        if candidate.objects.len() != self.body_count()
            || candidate.objects.len() > MAX_BODIES
            || candidate.world.bodies.len() != candidate.objects.len()
            || candidate.world.colliders.len() != candidate.objects.len()
            || !candidate.world.impulse_joints.is_empty()
            || candidate.world.multibody_joints.iter().next().is_some()
            || !candidate.world.soft_bodies.is_empty()
            || candidate.world.gravity != Vector::new(0.0, -9.8, 0.0)
        {
            return Err(Error("snapshot_topology"));
        }
        let mut bodies = BTreeSet::new();
        let mut colliders = BTreeSet::new();
        for (key, entry) in &candidate.objects {
            let local = self
                .state
                .objects
                .get(key)
                .ok_or(Error("snapshot_identity"))?;
            if !entry.spec.valid()
                || entry.spec != local.spec
                || entry.fixed_pose != local.fixed_pose
            {
                return Err(Error("snapshot_manifest"));
            }
            let body = candidate
                .world
                .bodies
                .get(entry.body)
                .ok_or(Error("snapshot_body_handle"))?;
            let collider = candidate
                .world
                .colliders
                .get(entry.collider)
                .ok_or(Error("snapshot_collider_handle"))?;
            if !bodies.insert(entry.body.into_raw_parts())
                || !colliders.insert(entry.collider.into_raw_parts())
                || body.user_data != key.tag()
                || collider.user_data != key.tag()
                || collider.parent() != Some(entry.body)
                || body.is_dynamic() != (entry.spec.mass > 0.0)
                || !body.linvel().is_finite()
                || !body.angvel().is_finite()
            {
                return Err(Error("snapshot_association"));
            }
            unpack_pose(pack_pose(body.position()))?;
            let cuboid = collider
                .shape()
                .as_cuboid()
                .ok_or(Error("snapshot_shape"))?;
            if cuboid.half_extents != Vector::from_array(entry.spec.size) * 0.5 {
                return Err(Error("snapshot_shape"));
            }
            if let Some(hold) = &entry.hold {
                if entry.spec.mass == 0.0 || !Vector::from_array(hold.anchor).is_finite() {
                    return Err(Error("snapshot_hold"));
                }
                unpack_pose(hold.goal)?;
            }
        }
        let dt = candidate.world.integration_parameters.dt;
        if !dt.is_finite() || dt <= 0.0 || dt > 1.0 / 30.0 {
            return Err(Error("snapshot_dt"));
        }
        Ok(())
    }

    pub fn cache_checkpoint(&mut self) -> Result<u64> {
        let bytes = self.snapshot()?;
        let tick = self.tick();
        if let Some(old) = self.cache.remove(&tick) {
            self.cache_bytes -= old.len();
        }
        self.cache_bytes += bytes.len();
        self.cache.insert(tick, bytes);
        while self.cache.len() > MAX_CACHED_TICKS || self.cache_bytes > MAX_CACHE_BYTES {
            let (_, old) = self.cache.pop_first().unwrap();
            self.cache_bytes -= old.len();
        }
        Ok(tick)
    }
    pub fn restore_cached(&mut self, tick: u64) -> Result<()> {
        let bytes = self
            .cache
            .get(&tick)
            .ok_or(Error("checkpoint_expired"))?
            .clone();
        self.restore_impl(&bytes, true)
    }
}
