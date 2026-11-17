//! Validación independiente (Claude), entrega 8: D01-D05, D07, D09-D17 y E1, E2, E4-E6.
//! Criterios: docs/net/validacion_objetos/criterios_entrega_8.md §3.6 y §3.7.
mod claude_common;
use claude_common::*;
use rapier3d::prelude::{Pose, Rotation, Vector};
use sahur_object_world::world::*;

/// Pose sin validar, armada directamente con los tipos de Rapier.
fn raw_pose(p: [f32; 3], q: [f32; 4]) -> Pose {
    Pose::from_parts(Vector::from_array(p), Rotation::from_array(q))
}

/// Compara T y K (gemelos). Sella los dos si hace falta y da 30 pasos.
fn same_state(t: &mut ObjectWorld, k: &mut ObjectWorld) -> (bool, String) {
    let samples = t.samples() == k.samples() && t.body_count() == k.body_count() && t.tick() == k.tick();
    let cache = t.cache_stats() == k.cache_stats();
    let (st, sk) = (t.snapshot(), k.snapshot());
    let sealed = st.is_ok();
    if !sealed {
        let _ = t.seal(1);
        let _ = k.seal(1);
    }
    let snap = t.snapshot().ok() == k.snapshot().ok() && t.snapshot().is_ok();
    let mut steps = true;
    for _ in 0..30 {
        let a = t.step(DT).is_ok();
        let b = k.step(DT).is_ok();
        steps &= a && b && t.samples() == k.samples();
    }
    let _ = sk;
    (samples && cache && snap && steps, format!("muestras={samples} cache={cache} snapshot={snap} sellado_antes={sealed} pasos30={steps}"))
}

fn twin(rep: &mut Report, id: &str, mk: &dyn Fn() -> ObjectWorld, op: &dyn Fn(&mut ObjectWorld) -> &'static str, expected: &str) {
    let mut t = mk();
    let mut k = mk();
    let got = op(&mut t);
    let (same, detail) = same_state(&mut t, &mut k);
    rep.check(id, got == expected && same, format!("error={got} {detail}"), &format!("{expected}, sin cambios"));
}

fn sealed_in_contact() -> ObjectWorld {
    let mut w = build(&NORMAL, &[], true);
    for _ in 0..20 {
        w.step(DT).unwrap();
    }
    w
}
fn unsealed() -> ObjectWorld {
    build(&NORMAL, &[], false)
}
fn holding() -> ObjectWorld {
    let mut w = build(&NORMAL, &[], true);
    w.begin_hold(KC, [0.0; 3], at([-0.7, 0.5, 0.2], ID)).unwrap();
    for _ in 0..5 {
        w.step(DT).unwrap();
    }
    w
}
fn with_retired() -> ObjectWorld {
    let mut w = ObjectWorld::default();
    w.add_box(k(50, 2), BoxSpec::new([0.3; 3], 1.0), at([1.0, 0.15, 1.0], ID)).unwrap();
    w.remove(k(50, 2)).unwrap();
    for b in fixture_f() {
        add(&mut w, &b).unwrap();
    }
    w
}

#[test]
fn d_api_rejections_are_atomic() {
    let mut rep = Report::new("d_api_rejections_are_atomic");
    let next_above = f32::from_bits((1.0f32 / 30.0).to_bits() + 1);
    for (name, dt) in [("0", 0.0f32), ("menos_1_60", -1.0 / 60.0), ("NaN", f32::NAN), ("inf", f32::INFINITY), ("siguiente_a_1_30", next_above), ("0_1", 0.1)] {
        twin(&mut rep, &format!("D01_dt_{name}"), &sealed_in_contact, &|w| err_code(&w.step(dt)), "invalid_dt");
    }
    let mut w = sealed_in_contact();
    rep.info("D01_dt_1_30_exacto", err_code(&w.step(1.0 / 30.0)));

    let cube = |kk: Key| move |w: &mut ObjectWorld| err_code(&w.add_box(kk, BoxSpec::new([0.3; 3], 1.0), at([1.0, 0.15, 1.0], ID)));
    twin(&mut rep, "D02_alta_sellada", &sealed_in_contact, &cube(key(40)), "sealed_topology");
    twin(&mut rep, "D03_uid_en_uso_otra_aparicion", &unsealed, &cube(k(10, 2)), "identity_in_use");
    twin(&mut rep, "D04_retirado_misma_aparicion", &with_retired, &cube(k(50, 2)), "retired_identity");
    twin(&mut rep, "D04_retirado_aparicion_menor", &with_retired, &cube(k(50, 1)), "retired_identity");
    let mut w = with_retired();
    rep.info("D04_retirado_aparicion_mayor", err_code(&w.add_box(k(50, 3), BoxSpec::new([0.3; 3], 1.0), at([1.0, 0.15, 1.0], ID))));

    for (name, size) in [("0", [0.0, 0.3, 0.3]), ("negativo", [-0.3, 0.3, 0.3]), ("NaN", [f32::NAN, 0.3, 0.3]), ("1001", [1001.0, 0.3, 0.3])] {
        twin(&mut rep, &format!("D05_tamano_{name}"), &unsealed, &move |w| err_code(&w.add_box(key(40), BoxSpec::new(size, 1.0), at([1.0, 0.15, 1.0], ID))), "invalid_box");
    }
    for (name, mass) in [("menos_1", -1.0f32), ("0_0005", 0.0005), ("2e6", 2.0e6), ("NaN", f32::NAN)] {
        twin(&mut rep, &format!("D05_masa_{name}"), &unsealed, &move |w| err_code(&w.add_box(key(40), BoxSpec::new([0.3; 3], mass), at([1.0, 0.15, 1.0], ID))), "invalid_box");
    }
    for (name, pos, rot) in [
        ("cuaternion_no_unitario", [1.0f32, 0.15, 1.0], [0.0f32, 0.0, 0.0, 1.01]),
        ("cuaternion_NaN", [1.0, 0.15, 1.0], [f32::NAN, 0.0, 0.0, 1.0]),
        ("posicion_NaN", [f32::NAN, 0.15, 1.0], ID),
        ("posicion_mayor_1e6", [1.1e6, 0.15, 1.0], ID),
    ] {
        let r = pose(pos, rot);
        rep.check(&format!("D05_pose_{name}"), err_code(&r) == "invalid_pose", err_code(&r), "invalid_pose");
        twin(&mut rep, &format!("D05_alta_pose_{name}"), &unsealed, &move |w| err_code(&w.add_box(key(40), BoxSpec::new([0.3; 3], 1.0), raw_pose(pos, rot))), "invalid_pose");
        twin(&mut rep, &format!("D10_objetivo_{name}"), &sealed_in_contact, &move |w| err_code(&w.begin_hold(KC, [0.0; 3], raw_pose(pos, rot))), "invalid_pose");
        twin(&mut rep, &format!("D11_objetivo_agarrado_{name}"), &holding, &move |w| err_code(&w.set_goal(KC, raw_pose(pos, rot))), "invalid_pose");
    }
    twin(&mut rep, "D07_baja_sellada", &sealed_in_contact, &|w| err_code(&w.remove(KC)), "sealed_topology");
    twin(&mut rep, "D07_baja_desconocida", &unsealed, &|w| err_code(&w.remove(key(77))), "unknown_identity");
    twin(&mut rep, "D09_sellar_0", &unsealed, &|w| err_code(&w.seal(0)), "invalid_context");
    twin(&mut rep, "D09_sellar_otra_revision", &sealed_in_contact, &|w| err_code(&w.seal(2)), "sealed_topology");
    let mut w = sealed_in_contact();
    rep.info("D09_sellar_misma_revision", err_code(&w.seal(1)));

    let goal = at([0.0, 1.0, 0.0], ID);
    twin(&mut rep, "D10_agarrar_fijo", &sealed_in_contact, &move |w| err_code(&w.begin_hold(KF, [0.0; 3], goal)), "invalid_hold_transition");
    twin(&mut rep, "D10_agarrar_ya_agarrado", &holding, &move |w| err_code(&w.begin_hold(KC, [0.0; 3], goal)), "invalid_hold_transition");
    twin(&mut rep, "D10_agarrar_desconocido", &sealed_in_contact, &move |w| err_code(&w.begin_hold(key(77), [0.0; 3], goal)), "unknown_identity");
    twin(&mut rep, "D10_ancla_NaN", &sealed_in_contact, &move |w| err_code(&w.begin_hold(KC, [f32::NAN, 0.0, 0.0], goal)), "invalid_anchor");
    twin(&mut rep, "D10_ancla_mayor_1000", &sealed_in_contact, &move |w| err_code(&w.begin_hold(KC, [1001.0, 0.0, 0.0], goal)), "invalid_anchor");
    twin(&mut rep, "D11_objetivo_sin_agarre", &sealed_in_contact, &move |w| err_code(&w.set_goal(KC, goal)), "not_held");
    twin(&mut rep, "D12_suelta_sin_agarre", &sealed_in_contact, &|w| err_code(&w.release(KC, [0.0; 3])), "not_held");
    twin(&mut rep, "D12_suelta_impulso_NaN", &holding, &|w| err_code(&w.release(KC, [f32::NAN, 0.0, 0.0])), "invalid_impulse");
    twin(&mut rep, "D12_suelta_impulso_1e6", &holding, &|w| err_code(&w.release(KC, [1.0e6, 0.0, 0.0])), "invalid_impulse");
    let mut w = holding();
    let _ = w.release(KC, [f32::NAN, 0.0, 0.0]);
    rep.check("D12_sigue_agarrado", w.sample(KC).unwrap().held, "held después del rechazo", "true");
    twin(&mut rep, "D13_impulso_fijo", &sealed_in_contact, &|w| err_code(&w.impulse(KF, [1.0, 0.0, 0.0])), "fixed_body");
    twin(&mut rep, "D13_impulso_desconocido", &sealed_in_contact, &|w| err_code(&w.impulse(key(77), [1.0, 0.0, 0.0])), "unknown_identity");
    for (name, v) in [("NaN", [f32::NAN, 0.0, 0.0]), ("inf", [f32::INFINITY, 0.0, 0.0]), ("1e6", [1.0e6, 0.0, 0.0])] {
        twin(&mut rep, &format!("D13_impulso_{name}"), &sealed_in_contact, &move |w| err_code(&w.impulse(KA, v)), "invalid_impulse");
    }
    let w = sealed_in_contact();
    for (name, o, d, dist) in [
        ("origen_NaN", [f32::NAN, 3.0, 0.0], [0.0f32, -1.0, 0.0], 5.0f32),
        ("direccion_nula", [0.0, 3.0, 0.0], [0.0, 0.0, 0.0], 5.0),
        ("distancia_0", [0.0, 3.0, 0.0], [0.0, -1.0, 0.0], 0.0),
        ("distancia_negativa", [0.0, 3.0, 0.0], [0.0, -1.0, 0.0], -1.0),
        ("distancia_NaN", [0.0, 3.0, 0.0], [0.0, -1.0, 0.0], f32::NAN),
        ("distancia_1e6", [0.0, 3.0, 0.0], [0.0, -1.0, 0.0], 1.0e6),
    ] {
        let r = w.ray(o, d, dist);
        rep.check(&format!("D14_rayo_{name}"), err_code(&r) == "invalid_ray", err_code(&r), "invalid_ray");
    }
    twin(&mut rep, "D15_tick_nunca_guardado", &sealed_in_contact, &|w| err_code(&w.restore_cached(999)), "checkpoint_expired");
    let w = unsealed();
    rep.check("D16_snapshot_sin_sellar", err_code(&w.snapshot()) == "unsealed_topology", err_code(&w.snapshot()), "unsealed_topology");
    rep.finish();
}

fn variant(change: &dyn Fn(&mut Vec<Body>), seal_rev: Option<u64>) -> ObjectWorld {
    let mut b = fixture_f();
    change(&mut b);
    let mut w = ObjectWorld::default();
    for x in &b {
        add(&mut w, x).unwrap();
    }
    if let Some(r) = seal_rev {
        w.seal(r).unwrap();
    }
    w
}

#[test]
fn d17_snapshot_rejections_keep_world_and_cache() {
    let mut rep = Report::new("d17_snapshot_rejections_keep_world_and_cache");
    let mut src = build(&NORMAL, &[], true);
    for _ in 0..20 {
        src.step(DT).unwrap();
    }
    let snap = src.snapshot().unwrap();
    let payload = snap[44..].to_vec();
    let n = payload.len();
    let mut cases: Vec<(&str, Vec<u8>, &[&str])> = Vec::new();
    let env_codes: &[&str] = &["invalid_snapshot_envelope", "snapshot_checksum"];
    cases.push(("sobre_vacio", Vec::new(), &["invalid_snapshot_envelope"]));
    cases.push(("sobre_43", snap[..43].to_vec(), &["invalid_snapshot_envelope"]));
    let mut b = snap.clone();
    b[0] ^= 1;
    cases.push(("otra_marca", b, &["invalid_snapshot_envelope"]));
    let mut b = snap.clone();
    b[8] ^= 1;
    cases.push(("largo_declarado_distinto", b, env_codes));
    let mut b = snap.clone();
    b.push(0);
    cases.push(("un_byte_de_mas", b, env_codes));
    cases.push(("un_byte_de_menos", snap[..snap.len() - 1].to_vec(), env_codes));
    let mut big = snap.clone();
    big.resize(MAX_SNAPSHOT_BYTES + 45, 0);
    cases.push(("mayor_1MiB_mas_44", big, &["invalid_snapshot_envelope"]));
    let mut b = snap.clone();
    b[44 + n / 2] ^= 0x10;
    cases.push(("suma_byte_del_payload", b, &["snapshot_checksum"]));
    let mut b = snap.clone();
    b[20] ^= 0x10;
    cases.push(("suma_byte_de_la_suma", b, &["snapshot_checksum"]));
    cases.push(("decodif_payload_truncado", envelope(&payload[..n - 10]), &["snapshot_decode"]));
    let mut p = payload.clone();
    p.push(7);
    cases.push(("decodif_byte_sobrante", envelope(&p), &["snapshot_decode"]));
    let mut seed = 0x1234_5678u32;
    let garbage: Vec<u8> = (0..n)
        .map(|_| {
            seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
            (seed >> 24) as u8
        })
        .collect();
    cases.push(("decodif_basura", envelope(&garbage), &["snapshot_decode"]));
    let mut p = payload.clone();
    p[0] ^= 1;
    cases.push(("modelo_alterado", envelope(&p), &["snapshot_model_or_context"]));
    let mut p = payload.clone();
    p[n - 8..].copy_from_slice(&2u64.to_le_bytes());
    cases.push(("contexto_alterado_en_payload", envelope(&p), &["snapshot_model_or_context"]));
    let mut p = payload.clone();
    p[n - 17..n - 9].copy_from_slice(&(i64::MAX as u64 + 1).to_le_bytes());
    cases.push(("tick_fuera_de_rango", envelope(&p), &["snapshot_model_or_context"]));
    // Verificación del desplazamiento: el contexto real es 1 y el tick real es 20.
    let ctx_ok = payload[n - 9] == 1 && payload[n - 8..] == 1u64.to_le_bytes() && payload[n - 17..n - 9] == 20u64.to_le_bytes();
    rep.check("D17_desplazamientos_del_payload", ctx_ok, format!("tag={} ctx={:?} tick={:?}", payload[n - 9], &payload[n - 8..], &payload[n - 17..n - 9]), "contexto 1 y tick 20 al final");

    for (name, bytes, codes) in &cases {
        let mut d = build(&REVERSE, &[], true);
        for _ in 0..3 {
            d.step(DT).unwrap();
        }
        let t0 = d.cache_checkpoint().unwrap();
        d.step(DT).unwrap();
        let before = d.snapshot().unwrap();
        let cache_before = d.cache_stats();
        let r = d.restore_trusted(bytes);
        let code = err_code(&r);
        let same = d.snapshot().unwrap() == before && d.cache_stats() == cache_before;
        let still = d.restore_cached(t0).is_ok();
        rep.check(&format!("D17_{name}"), codes.contains(&code) && same && still, format!("error={code} sin_cambios={same} checkpoint_previo_restaurable={still}"), &format!("{codes:?}, sin cambios, caché intacta"));
    }
    // Destinos incompatibles.
    let dests: Vec<(&str, Box<dyn Fn() -> ObjectWorld>, &str)> = vec![
        ("contexto_2", Box::new(|| variant(&|_| {}, Some(2))), "snapshot_model_or_context"),
        ("destino_sin_sellar", Box::new(|| variant(&|_| {}, None)), "snapshot_model_or_context"),
        ("otro_tamano", Box::new(|| variant(&|b| b[1].size[0] = 0.51, Some(1))), "snapshot_manifest"),
        ("otra_masa", Box::new(|| variant(&|b| b[1].mass = 1.6, Some(1))), "snapshot_manifest"),
        ("otra_pose_del_piso", Box::new(|| variant(&|b| b[0].pos[1] = -0.11, Some(1))), "snapshot_manifest"),
        ("un_cuerpo_menos", Box::new(|| variant(&|b| { b.pop(); }, Some(1))), "snapshot_topology"),
        ("un_cuerpo_mas", Box::new(|| variant(&|b| b.push(Body { key: key(40), size: [0.2; 3], mass: 0.4, pos: [1.5, 0.1, 1.5], rot: ID }), Some(1))), "snapshot_topology"),
        ("otro_uid", Box::new(|| variant(&|b| b[3].key = key(31), Some(1))), "snapshot_identity"),
        ("otra_aparicion", Box::new(|| variant(&|b| b[3].key = k(30, 2), Some(1))), "snapshot_identity"),
    ];
    for (name, mk, expected) in &dests {
        let mut d = mk();
        let sealed = d.snapshot().is_ok();
        let (t0, before, cache_before) = if sealed {
            d.step(DT).unwrap();
            let t0 = d.cache_checkpoint().unwrap();
            d.step(DT).unwrap();
            (Some(t0), d.snapshot().unwrap(), d.cache_stats())
        } else {
            (None, Vec::new(), d.cache_stats())
        };
        let samples_before = d.samples();
        let r = d.restore_trusted(&snap);
        let code = err_code(&r);
        let same = d.samples() == samples_before && d.cache_stats() == cache_before && (!sealed || d.snapshot().unwrap() == before);
        let still = t0.map(|t| d.restore_cached(t).is_ok()).unwrap_or(true);
        rep.check(&format!("D17_{name}"), code == *expected && same && still, format!("error={code} sin_cambios={same} checkpoint_previo_restaurable={still}"), &format!("{expected}, sin cambios, caché intacta"));
    }
    rep.finish();
}

#[test]
fn e_cache_limits_expiry_and_discards() {
    let mut rep = Report::new("e_cache_limits_expiry_and_discards");
    let mut w = build(&NORMAL, &[], true);
    let mut lens = std::collections::BTreeMap::new();
    for _ in 0..135 {
        let len = w.snapshot().unwrap().len();
        let t = w.cache_checkpoint().unwrap();
        lens.insert(t, len);
        w.step(DT).unwrap();
    }
    let (count, bytes) = w.cache_stats();
    let expected: usize = (15..=134u64).map(|t| lens[&t]).sum();
    rep.check("E1_quedan_120", count == 120, format!("cantidad={count}"), "120");
    let before = w.snapshot().unwrap();
    let r = w.restore_cached(14);
    let same = w.snapshot().unwrap() == before && w.cache_stats() == (count, bytes);
    rep.check("E1_mas_viejo_vencido", err_code(&r) == "checkpoint_expired" && same, format!("{} sin_cambios={same}", err_code(&r)), "checkpoint_expired, sin cambios");
    let r15 = w.snapshot().is_ok();
    rep.check("E2_bytes_iguales_a_la_suma", bytes == expected, format!("cache={bytes} calculado={expected}"), "igual");
    // Guardar dos veces el mismo tick (135).
    let len135 = w.snapshot().unwrap().len();
    w.cache_checkpoint().unwrap();
    w.cache_checkpoint().unwrap();
    lens.insert(135, len135);
    let expected2: usize = (16..=135u64).map(|t| lens[&t]).sum();
    let (c2, b2) = w.cache_stats();
    rep.check("E2_mismo_tick_dos_veces", c2 == 120 && b2 == expected2 && r15, format!("cantidad={c2} cache={b2} calculado={expected2}"), "120 y suma de 16..=135");
    // E4
    let ok = w.restore_cached(100).is_ok();
    let expected4: usize = (16..=100u64).map(|t| lens[&t]).sum();
    let (c4, b4) = w.cache_stats();
    let r101 = w.restore_cached(101);
    let again = w.restore_cached(100).is_ok();
    rep.check(
        "E4_conserva_pasado_quita_futuro",
        ok && w.tick() == 100 && c4 == 85 && b4 == expected4 && err_code(&r101) == "checkpoint_expired" && again,
        format!("restaurado={ok} tick={} cantidad={c4} cache={b4} calculado={expected4} t+1={} t_otra_vez={again}", w.tick(), err_code(&r101)),
        "85 entradas 16..=100, 101 vencido, 100 restaurable",
    );
    // E6: rechazos que no tocan la caché.
    let cs = w.cache_stats();
    let r = w.restore_cached(500);
    let mut damaged = w.snapshot().unwrap();
    let last = damaged.len() - 1;
    damaged[last] ^= 1;
    let r2 = w.restore_trusted(&damaged);
    let kept = w.cache_stats() == cs && w.restore_cached(90).is_ok();
    rep.check("E6_rechazos_no_tocan_la_cache", r.is_err() && r2.is_err() && kept, format!("restore_cached(500)={} restore_trusted(dañado)={} cache_igual_y_90_restaurable={kept}", err_code(&r), err_code(&r2)), "caché intacta");
    // E5: importar autoridad borra todo; los mismos números de tick son de la rama nueva.
    let mut w = build(&NORMAL, &[], true);
    for _ in 0..100 {
        w.step(DT).unwrap();
    }
    let auth = w.snapshot().unwrap();
    let mut old103 = Vec::new();
    for _ in 0..10 {
        w.cache_checkpoint().unwrap();
        if w.tick() == 103 {
            old103 = w.snapshot().unwrap();
        }
        w.step(DT).unwrap();
    }
    let had = w.cache_stats().0;
    let ok = w.restore_trusted(&auth).is_ok();
    let cleared = w.cache_stats() == (0, 0);
    let expired_all = (100..110u64).all(|t| w.restore_cached(t).is_err());
    w.impulse(KC, [0.5, 0.0, 0.0]).unwrap();
    let mut new103 = Vec::new();
    for _ in 0..6 {
        w.cache_checkpoint().unwrap();
        if w.tick() == 103 {
            new103 = w.snapshot().unwrap();
        }
        w.step(DT).unwrap();
    }
    let ok103 = w.restore_cached(103).is_ok();
    let got = w.snapshot().unwrap();
    rep.check(
        "E5_importar_descarta_y_tick_repetido_es_rama_nueva",
        had == 10 && ok && cleared && expired_all && ok103 && got == new103 && got != old103,
        format!("antes={had} restaurado={ok} vacia={cleared} viejos_vencidos={expired_all} 103_restaurado={ok103} igual_rama_nueva={} distinto_de_la_vieja={}", got == new103, got != old103),
        "(0,0), viejos vencidos, 103 = rama nueva",
    );
    rep.finish();
}
