//! Validación independiente (Claude), entrega 9: utilidades de los verificadores nuevos.
//! Criterios: docs/net/validacion_objetos/criterios_entrega_9.md §5. No cambia claude_common.
#![allow(dead_code)]
use crate::claude_common::*;
use sahur_object_world::world::*;

/// Pila de 128 cuerpos (misma geometría que claude_capacity.rs, como lista de cuerpos).
pub fn pile_bodies() -> Vec<Body> {
    let mut out = vec![Body { key: KF, size: [8.0, 0.2, 8.0], mass: 0.0, pos: [0.0, -0.1, 0.0], rot: ID }];
    let mut uid = 1000;
    'outer: for layer in 0..6 {
        for i in 0..5 {
            for j in 0..5 {
                if out.len() >= MAX_BODIES {
                    break 'outer;
                }
                let off = 0.01 * ((i * 3 + j * 7 + layer * 5) % 5) as f32;
                let p = [-0.6 + 0.3 * i as f32 + off, 0.13 + 0.27 * layer as f32, -0.6 + 0.3 * j as f32 - off];
                let r = quat([0.0, 1.0, 0.0], 0.05 * ((i + j + layer) % 4) as f32);
                out.push(Body { key: key(uid), size: [0.25; 3], mass: 0.5, pos: p, rot: r });
                uid += 1;
            }
        }
    }
    out
}

pub struct Lcg(pub u32);
impl Lcg {
    pub fn next(&mut self) -> f32 {
        self.0 = self.0.wrapping_mul(1664525).wrapping_add(1013904223);
        (self.0 >> 8) as f32 / (1u32 << 24) as f32
    }
    pub fn range(&mut self, a: f32, b: f32) -> f32 {
        a + (b - a) * self.next()
    }
}

pub fn total_contacts(s: &[Sample]) -> usize {
    s.iter().map(|x| x.contacts.len()).sum()
}

/// N1: snapshots genuinos de `src` cada `stride` ticks, restaurados en un gemelo nuevo.
/// `ops(w, n)` se aplica antes del paso n (mismo cronograma en origen y gemelo).
pub fn false_reject_scenario(
    rep: &mut Report,
    name: &str,
    make_src: &dyn Fn() -> ObjectWorld,
    make_twin: &dyn Fn() -> ObjectWorld,
    ops: &dyn Fn(&mut ObjectWorld, u64),
    ticks: u64,
    stride: u64,
    include_start: bool,
) {
    let start = std::time::Instant::now();
    let mut src = make_src();
    let t0 = src.tick();
    let mut hist = vec![src.samples()];
    let mut snaps = Vec::new();
    if include_start {
        snaps.push((t0, src.snapshot().unwrap()));
    }
    for n in 1..=ticks {
        let next = src.tick() + 1;
        ops(&mut src, next);
        src.step(DT).unwrap();
        hist.push(src.samples());
        if n % stride == 0 {
            snaps.push((src.tick(), src.snapshot().unwrap()));
        }
    }
    let max_contacts = hist.iter().map(|s| total_contacts(s)).max().unwrap_or(0);
    let mut rejected = Vec::new();
    let mut mismatched = Vec::new();
    let mut cont_checked = 0;
    let mut cont_bad = Vec::new();
    let mut max_bytes = 0;
    for (t, bytes) in &snaps {
        max_bytes = max_bytes.max(bytes.len());
        let mut twin = make_twin();
        if let Err(e) = twin.restore_trusted(bytes) {
            rejected.push(format!("t{t}:{}", e.0));
            continue;
        }
        let i = (*t - t0) as usize;
        if !diff_samples(&hist[i], &twin.samples()).exact {
            mismatched.push(*t);
            continue;
        }
        if t % 25 == 0 && i + 30 < hist.len() {
            cont_checked += 1;
            for _ in 0..30 {
                let next = twin.tick() + 1;
                ops(&mut twin, next);
                twin.step(DT).unwrap();
            }
            if !diff_samples(&hist[i + 30], &twin.samples()).exact {
                cont_bad.push(*t);
            }
        }
    }
    let ok = rejected.is_empty() && mismatched.is_empty() && cont_bad.is_empty();
    rep.check(
        &format!("N1_{name}"),
        ok,
        format!(
            "snapshots={} rechazados={} {:?} distintos={:?} continuaciones={} continuaciones_distintas={:?} max_contactos_listados={} max_bytes={} tiempo={:.3}s",
            snaps.len(), rejected.len(), rejected.iter().take(5).collect::<Vec<_>>(), mismatched.iter().take(5).collect::<Vec<_>>(),
            cont_checked, cont_bad, max_contacts, max_bytes, start.elapsed().as_secs_f64()
        ),
        "0 rechazos, muestras y continuación iguales por bits",
    );
    if max_contacts == 0 {
        rep.noeval(&format!("N1_{name}_grafos"), "sin contactos listados: el grafo no se ejercitó");
    }
}
