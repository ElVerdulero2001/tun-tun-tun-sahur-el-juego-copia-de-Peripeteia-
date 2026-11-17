//! Validación independiente (Claude), entrega 8. Utilidades comunes de las pruebas
//! `claude_*.rs`. Criterios: docs/net/validacion_objetos/criterios_entrega_8.md.
//! Cada comprobación imprime una línea `CLAUDE_CHECK\t<id>\t<PASS|FAIL|INFO|NOEVAL>\t<métrica>\t<tolerancia>`.
#![allow(dead_code)]

use rapier3d::prelude::Pose;
use sahur_object_world::world::*;
use sha2::{Digest, Sha256};

pub const DT: f32 = 1.0 / 60.0;
pub const EPS: f32 = 0.00001;
pub const SENS: f32 = 0.001;

pub fn k(uid: u32, epoch: u32) -> Key {
    Key::new(uid, epoch).unwrap()
}
pub const fn key(uid: u32) -> Key {
    Key { uid, epoch: 1 }
}
pub const KF: Key = key(1);
pub const KA: Key = key(10);
pub const KB: Key = key(20);
pub const KC: Key = key(30);

pub fn quat(axis: [f32; 3], angle: f32) -> [f32; 4] {
    let n = (axis[0] * axis[0] + axis[1] * axis[1] + axis[2] * axis[2]).sqrt();
    let s = (angle * 0.5).sin() / n;
    [axis[0] * s, axis[1] * s, axis[2] * s, (angle * 0.5).cos()]
}
pub fn at(pos: [f32; 3], rot: [f32; 4]) -> Pose {
    pose(pos, rot).unwrap()
}
pub const ID: [f32; 4] = [0.0, 0.0, 0.0, 1.0];

#[derive(Clone)]
pub struct Body {
    pub key: Key,
    pub size: [f32; 3],
    pub mass: f32,
    pub pos: [f32; 3],
    pub rot: [f32; 4],
}

/// Fixture F (criterios §3.1): piso, A, B, C.
pub fn fixture_f() -> Vec<Body> {
    vec![
        Body { key: KF, size: [8.0, 0.2, 8.0], mass: 0.0, pos: [0.0, -0.1, 0.0], rot: ID },
        Body { key: KA, size: [0.5, 0.3, 0.7], mass: 1.5, pos: [0.05, 0.15, -0.1], rot: quat([0.0, 1.0, 0.0], 0.3) },
        Body { key: KB, size: [0.4, 0.4, 0.4], mass: 1.0, pos: [0.1, 0.9, 0.05], rot: quat([1.0, 0.0, 1.0], 0.35) },
        Body { key: KC, size: [0.3, 0.3, 0.3], mass: 0.5, pos: [-0.7, 0.15, 0.2], rot: ID },
    ]
}

pub fn add(w: &mut ObjectWorld, b: &Body) -> Result<()> {
    let mut spec = BoxSpec::new(b.size, b.mass);
    spec.mass = b.mass;
    w.add_box(b.key, spec, at(b.pos, b.rot))
}

/// Crea y retira `removed` (cubos chicos lejos) y después agrega `bodies` en el orden `order`.
pub fn build_from(bodies: &[Body], order: &[usize], removed: &[u32], seal: bool) -> ObjectWorld {
    let mut w = ObjectWorld::default();
    for (i, uid) in removed.iter().enumerate() {
        let kk = key(*uid);
        w.add_box(kk, BoxSpec::new([0.2; 3], 0.3), at([3.0 + i as f32, 0.1, 3.0], ID)).unwrap();
        w.remove(kk).unwrap();
    }
    for &i in order {
        add(&mut w, &bodies[i]).unwrap();
    }
    if seal {
        w.seal(1).unwrap();
    }
    w
}
pub fn build(order: &[usize], removed: &[u32], seal: bool) -> ObjectWorld {
    build_from(&fixture_f(), order, removed, seal)
}
pub const NORMAL: [usize; 4] = [0, 1, 2, 3];
pub const REVERSE: [usize; 4] = [3, 2, 1, 0];
pub const SHUFFLED: [usize; 4] = [3, 1, 0, 2];

fn speed(v: [f32; 3]) -> f32 {
    (v[0] * v[0] + v[1] * v[1] + v[2] * v[2]).sqrt()
}
pub fn has(s: &Sample, other: Key) -> bool {
    s.contacts.contains(&other)
}

/// Regla K: primer paso 5..=120 con contacto mutuo A-B, ambos despiertos y |vB - vA| >= 0,05.
pub fn rule_k(w: &mut ObjectWorld) -> Option<u64> {
    for s in 1..=120u64 {
        w.step(DT).unwrap();
        if s < 5 {
            continue;
        }
        let a = w.sample(KA).unwrap();
        let b = w.sample(KB).unwrap();
        let rel = [b.linear[0] - a.linear[0], b.linear[1] - a.linear[1], b.linear[2] - a.linear[2]];
        if has(&a, KB) && has(&b, KA) && !a.sleeping && !b.sleeping && speed(rel) >= 0.05 {
            return Some(w.tick());
        }
    }
    None
}

/// Rama de la referencia: impulso a A en j=30, despertar de B en j=330.
pub fn branch_range<F: FnMut(usize, &ObjectWorld)>(
    w: &mut ObjectWorld,
    from: usize,
    to: usize,
    imp30: [f32; 3],
    mut cb: F,
) -> Vec<Vec<Sample>> {
    let mut out = Vec::new();
    for j in from..=to {
        if j == 30 {
            w.impulse(KA, imp30).unwrap();
        }
        if j == 330 {
            w.impulse(KB, [0.0, 0.0, 0.6]).unwrap();
        }
        w.step(DT).unwrap();
        out.push(w.samples());
        cb(j, w);
    }
    out
}
pub fn branch(w: &mut ObjectWorld, h: usize) -> Vec<Vec<Sample>> {
    branch_range(w, 1, h, [1.0, 0.0, 0.3], |_, _| {})
}

#[derive(Debug, Default, Clone)]
pub struct Diff {
    pub pos: f32,
    pub rot: f32,
    pub vel: f32,
    pub sleep_mm: usize,
    pub held_mm: usize,
    pub contacts_mm: usize,
    pub key_mm: usize,
    pub len_mm: bool,
    pub exact: bool,
    pub first_bad: Option<usize>,
}
impl Diff {
    pub fn within(&self) -> bool {
        !self.len_mm
            && self.key_mm == 0
            && self.pos <= EPS
            && self.rot <= EPS
            && self.vel <= EPS
            && self.sleep_mm == 0
            && self.held_mm == 0
            && self.contacts_mm == 0
    }
    pub fn magnitude(&self) -> f32 {
        self.pos.max(self.rot).max(self.vel)
    }
    pub fn text(&self) -> String {
        format!(
            "pos={:e} rot={:e} vel={:e} reposo_dif={} agarre_dif={} contactos_dif={} claves_dif={} largo_dif={} exacta_bits={} primer_paso_malo={:?}",
            self.pos, self.rot, self.vel, self.sleep_mm, self.held_mm, self.contacts_mm, self.key_mm, self.len_mm, self.exact, self.first_bad
        )
    }
}
fn d3(a: &[f32], b: &[f32]) -> f32 {
    a.iter().zip(b).map(|(x, y)| (x - y) * (x - y)).sum::<f32>().sqrt()
}
fn diff_into(e: &mut Diff, step: usize, a: &[Sample], b: &[Sample]) {
    if a.len() != b.len() {
        e.len_mm = true;
        e.exact = false;
        e.first_bad.get_or_insert(step);
        return;
    }
    let mut bad = false;
    for (x, y) in a.iter().zip(b) {
        if x.key != y.key || x.tick != y.tick {
            e.key_mm += 1;
            bad = true;
            continue;
        }
        let dp = d3(&x.pose[..3], &y.pose[..3]);
        let dr = (3..7).map(|i| (x.pose[i] - y.pose[i]).abs()).fold(0.0, f32::max);
        let dv = d3(&x.linear, &y.linear).max(d3(&x.angular, &y.angular));
        e.pos = e.pos.max(dp);
        e.rot = e.rot.max(dr);
        e.vel = e.vel.max(dv);
        let bits = |s: &Sample| -> Vec<u32> { s.pose.iter().chain(&s.linear).chain(&s.angular).map(|v| v.to_bits()).collect() };
        if bits(x) != bits(y) {
            e.exact = false;
        }
        if x.sleeping != y.sleeping {
            e.sleep_mm += 1;
            bad = true;
        }
        if x.held != y.held {
            e.held_mm += 1;
            bad = true;
        }
        if x.contacts != y.contacts {
            e.contacts_mm += 1;
            bad = true;
        }
        if dp > EPS || dr > EPS || dv > EPS {
            bad = true;
        }
    }
    if bad {
        e.exact = false;
        e.first_bad.get_or_insert(step);
    }
}
pub fn diff_samples(a: &[Sample], b: &[Sample]) -> Diff {
    let mut e = Diff { exact: true, ..Default::default() };
    diff_into(&mut e, 0, a, b);
    e
}
pub fn diff_hist(a: &[Vec<Sample>], b: &[Vec<Sample>]) -> Diff {
    let mut e = Diff { exact: true, ..Default::default() };
    if a.len() != b.len() {
        e.len_mm = true;
        e.exact = false;
    }
    for (i, (x, y)) in a.iter().zip(b).enumerate() {
        diff_into(&mut e, i, x, y);
    }
    e
}
pub fn hist_sha(h: &[Vec<Sample>]) -> String {
    let mut s = Sha256::new();
    for step in h {
        for x in step {
            s.update(x.key.uid.to_le_bytes());
            s.update(x.key.epoch.to_le_bytes());
            s.update(x.tick.to_le_bytes());
            for v in x.pose.iter().chain(&x.linear).chain(&x.angular) {
                s.update(v.to_bits().to_le_bytes());
            }
            s.update([x.sleeping as u8, x.held as u8]);
            for c in &x.contacts {
                s.update(c.uid.to_le_bytes());
                s.update(c.epoch.to_le_bytes());
            }
            s.update([0xff]);
        }
    }
    s.finalize().iter().map(|b| format!("{b:02x}")).collect()
}

/// Grilla de rayos (B1): 9 verticales y 3 horizontales.
pub fn grid_rays(w: &ObjectWorld) -> Vec<Option<(Key, u32)>> {
    let mut out = Vec::new();
    for x in [-0.7f32, 0.05, 0.1] {
        for z in [-0.1f32, 0.05, 0.2] {
            out.push(w.ray([x, 3.0, z], [0.0, -1.0, 0.0], 5.0).unwrap().map(|(k, d)| (k, d.to_bits())));
        }
    }
    for (y, z) in [(0.1f32, -0.1f32), (0.25, 0.05), (2.5, 0.0)] {
        out.push(w.ray([-3.0, y, z], [1.0, 0.0, 0.0], 6.0).unwrap().map(|(k, d)| (k, d.to_bits())));
    }
    out
}

pub fn envelope(payload: &[u8]) -> Vec<u8> {
    let mut b = Vec::with_capacity(payload.len() + 44);
    b.extend_from_slice(b"SOBJW001");
    b.extend_from_slice(&(payload.len() as u32).to_le_bytes());
    b.extend_from_slice(&Sha256::digest(payload));
    b.extend_from_slice(payload);
    b
}

pub struct Report {
    pub name: &'static str,
    pub fails: Vec<String>,
}
impl Report {
    pub fn new(name: &'static str) -> Self {
        Self { name, fails: Vec::new() }
    }
    fn line(&self, id: &str, verdict: &str, metric: &str, tol: &str) {
        let clean = |s: &str| s.replace(['\t', '\n', '\r'], " ");
        println!("CLAUDE_CHECK\t{}\t{}\t{}\t{}", clean(id), verdict, clean(metric), clean(tol));
    }
    pub fn check(&mut self, id: &str, ok: bool, metric: impl AsRef<str>, tol: &str) -> bool {
        self.line(id, if ok { "PASS" } else { "FAIL" }, metric.as_ref(), tol);
        if !ok {
            self.fails.push(id.to_string());
        }
        ok
    }
    pub fn info(&mut self, id: &str, metric: impl AsRef<str>) {
        self.line(id, "INFO", metric.as_ref(), "se registra");
    }
    pub fn noeval(&mut self, id: &str, why: impl AsRef<str>) {
        self.line(id, "NOEVAL", why.as_ref(), "condición previa");
    }
    pub fn finish(self) {
        println!("CLAUDE_DONE\t{}\t{}", self.name, self.fails.len());
        assert!(self.fails.is_empty(), "{} falló: {:?}", self.name, self.fails);
    }
}

pub fn err_code<T>(r: &Result<T>) -> &'static str {
    match r {
        Ok(_) => "ok",
        Err(e) => e.0,
    }
}
