//! Validación independiente (Claude), entrega 9: N1 falsos rechazos (S1, S2, S4-S7).
//! Criterios: docs/net/validacion_objetos/criterios_entrega_9.md §5 N1.
mod claude_common;
mod claude_e9_common;
use claude_common::*;
use claude_e9_common::*;
use sahur_object_world::world::*;

fn s1_ops(w: &mut ObjectWorld, n: u64) {
    if n == 30 {
        w.impulse(KA, [1.0, 0.0, 0.3]).unwrap();
    }
    if n == 330 {
        w.impulse(KB, [0.0, 0.0, 0.6]).unwrap();
    }
}
fn s2_ops(w: &mut ObjectWorld, n: u64) {
    if n == 1 {
        w.begin_hold(KC, [0.05, 0.0, 0.0], at([-0.7, 0.5, 0.2], ID)).unwrap();
    }
    if (2..=60).contains(&n) {
        let f = n as f32;
        w.set_goal(KC, at([-0.7 + 0.01 * f, 0.5 + 0.002 * f, 0.2], quat([0.0, 1.0, 0.0], 0.02 * f))).unwrap();
    }
    if n == 61 {
        w.release(KC, [0.3, 0.2, 0.0]).unwrap();
    }
}

fn s4_fixed() -> Vec<Body> {
    vec![
        Body { key: KF, size: [8.0, 0.2, 8.0], mass: 0.0, pos: [0.0, -0.1, 0.0], rot: ID },
        Body { key: key(2), size: [2.0, 0.1, 1.0], mass: 0.0, pos: [1.234567, 0.4, -0.987654], rot: quat([0.0, 0.0, 1.0], 0.3) },
        Body { key: key(3), size: [1.5, 0.12, 1.2], mass: 0.0, pos: [-1.1, 0.35, 0.77], rot: quat([0.3, 0.1, 1.0], 0.71) },
        Body { key: key(4), size: [0.2, 1.0, 3.0], mass: 0.0, pos: [2.4, 0.5, 0.123], rot: quat([0.0, 1.0, 0.0], 1.0) },
    ]
}
fn s4_dynamic() -> Vec<Body> {
    (0..6u32)
        .map(|i| {
            let f = i as f32;
            Body {
                key: key(10 + i),
                size: [0.2 + 0.03 * f, 0.2 + 0.02 * f, 0.25],
                mass: 0.5 + 0.2 * f,
                pos: [if i % 2 == 0 { 1.0 + 0.1 * f } else { -1.2 + 0.05 * f }, 1.2 + 0.15 * f, if i % 2 == 0 { -0.9 } else { 0.8 }],
                rot: quat([1.0, 0.2, 0.0], 0.1 * f),
            }
        })
        .collect()
}
fn s4_src() -> ObjectWorld {
    let mut w = ObjectWorld::default();
    let tmp = |uid| Body { key: key(uid), size: [0.2; 3], mass: 0.3, pos: [3.0, 0.1, 3.0], rot: ID };
    let (f, d) = (s4_fixed(), s4_dynamic());
    add(&mut w, &tmp(90)).unwrap();
    add(&mut w, &f[0]).unwrap();
    add(&mut w, &tmp(91)).unwrap();
    w.remove(key(90)).unwrap();
    add(&mut w, &f[1]).unwrap();
    add(&mut w, &f[2]).unwrap();
    w.remove(key(91)).unwrap();
    add(&mut w, &tmp(92)).unwrap();
    add(&mut w, &f[3]).unwrap();
    for b in &d[..3] {
        add(&mut w, b).unwrap();
    }
    w.remove(key(92)).unwrap();
    for b in &d[3..] {
        add(&mut w, b).unwrap();
    }
    w.seal(1).unwrap();
    w
}
fn s4_twin() -> ObjectWorld {
    let mut w = ObjectWorld::default();
    for b in s4_dynamic().iter().rev().chain(s4_fixed().iter().rev()) {
        add(&mut w, b).unwrap();
    }
    w.seal(1).unwrap();
    w
}
fn s4_ops(w: &mut ObjectWorld, n: u64) {
    if n == 100 {
        w.impulse(key(10), [2.0, 0.0, 0.0]).unwrap();
    }
}

fn s5_build(reverse: bool) -> ObjectWorld {
    let mut list: Vec<(Key, BoxSpec, [f32; 3])> = vec![
        (KF, BoxSpec::new([8.0, 0.2, 8.0], 0.0), [0.0, -0.1, 0.0]),
        (key(2), BoxSpec::new([0.2, 1.0, 4.0], 0.0), [3.0, 0.5, 0.0]),
    ];
    for (i, h) in [1.0f32, 1.5, 2.0].iter().enumerate() {
        let mut s = BoxSpec::new([0.25; 3], 0.6);
        s.restitution = 0.9;
        s.friction = 0.1;
        list.push((key(10 + i as u32), s, [-0.5 + 0.5 * i as f32, *h, 0.4]));
    }
    list.push((key(13), BoxSpec::new([0.2; 3], 0.5), [-2.0, 0.3, 0.0]));
    if reverse {
        list.reverse();
    }
    let mut w = ObjectWorld::default();
    for (k, s, p) in list {
        w.add_box(k, s, at(p, ID)).unwrap();
    }
    w.seal(1).unwrap();
    w
}
fn s5_ops(w: &mut ObjectWorld, n: u64) {
    if n == 1 {
        w.impulse(key(13), [10.0, 0.0, 0.0]).unwrap();
    }
}

fn s6_bodies() -> Vec<Body> {
    let mut r = Lcg(0xC1A0_D009);
    let mut out = vec![Body { key: KF, size: [8.0, 0.2, 8.0], mass: 0.0, pos: [0.0, -0.1, 0.0], rot: ID }];
    for i in 0..24u32 {
        let axis = [r.range(-1.0, 1.0), r.range(-1.0, 1.0), r.range(-1.0, 1.0) + 0.01];
        out.push(Body {
            key: key(100 + i),
            size: [r.range(0.1, 0.5), r.range(0.1, 0.5), r.range(0.1, 0.5)],
            mass: 0.0,
            pos: [r.range(-3.0, 3.0), r.range(0.0, 2.0), r.range(-3.0, 3.0)],
            rot: quat(axis, r.range(0.0, 3.14159)),
        });
    }
    for i in 0..3u32 {
        out.push(Body { key: key(200 + i), size: [0.3; 3], mass: 1.0, pos: [r.range(-2.0, 2.0), 3.0, r.range(-2.0, 2.0)], rot: ID });
    }
    out
}

#[test]
fn n1_false_rejections() {
    let mut rep = Report::new("n1_false_rejections");
    false_reject_scenario(&mut rep, "S1_fixture_F", &|| build(&NORMAL, &[], true), &|| build(&REVERSE, &[], true), &s1_ops, 600, 1, false);
    false_reject_scenario(&mut rep, "S2_agarre", &|| build(&NORMAL, &[], true), &|| build(&REVERSE, &[], true), &s2_ops, 180, 1, false);
    false_reject_scenario(&mut rep, "S4_rampas_y_bajas", &s4_src, &s4_twin, &s4_ops, 400, 1, false);
    false_reject_scenario(&mut rep, "S5_rebotes_y_ccd", &|| s5_build(false), &|| s5_build(true), &s5_ops, 300, 1, false);
    let b6 = s6_bodies();
    let n6 = b6.len();
    let normal: Vec<usize> = (0..n6).collect();
    let reverse: Vec<usize> = (0..n6).rev().collect();
    false_reject_scenario(&mut rep, "S6_fijos_aleatorios", &|| build_from(&b6, &normal, &[], true), &|| build_from(&b6, &reverse, &[], true), &|_, _| {}, 60, 1, true);
    // S7: camino de caché.
    let mut w = build(&NORMAL, &[], true);
    let mut hist = std::collections::BTreeMap::new();
    for _ in 0..200 {
        let next = w.tick() + 1;
        s1_ops(&mut w, next);
        w.step(DT).unwrap();
        hist.insert(w.tick(), w.samples());
        w.cache_checkpoint().unwrap();
    }
    let (count, _) = w.cache_stats();
    let mut bad = Vec::new();
    let mut done = 0;
    for t in (81..=200u64).rev() {
        match w.restore_cached(t) {
            Ok(()) => {
                if !diff_samples(&hist[&t], &w.samples()).exact {
                    bad.push(format!("t{t}:distinto"));
                }
            }
            Err(e) => bad.push(format!("t{t}:{}", e.0)),
        }
        done += 1;
    }
    rep.check("N1_S7_cache", count == 120 && done == 120 && bad.is_empty(), format!("en_cache={count} restaurados={done} problemas={:?}", bad.iter().take(5).collect::<Vec<_>>()), "120 restauraciones iguales");
    rep.finish();
}
