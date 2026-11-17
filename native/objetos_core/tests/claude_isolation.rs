//! Validación independiente (Claude), entrega 8: C1-C5, aislamiento entre instancias.
//! Criterios: docs/net/validacion_objetos/criterios_entrega_8.md §3.4.
mod claude_common;
use claude_common::*;
use sahur_object_world::world::*;

const KX: Key = key(100);
const KY: Key = key(101);

fn w3_new() -> ObjectWorld {
    let mut w = build(&NORMAL, &[], false);
    w.add_box(KX, BoxSpec::new([0.4; 3], 1.0), at([2.0, 0.2, 0.0], ID)).unwrap();
    w
}
fn w2_step(w: &mut ObjectWorld) {
    if w.tick() == 40 {
        w.impulse(KA, [2.0, 0.0, 0.0]).unwrap();
    }
    w.step(DT).unwrap();
}
/// Operaciones de W3 en el momento de la restauración de I'.
fn w3_ops(w: &mut ObjectWorld) -> (Option<(Key, f32)>, Option<(Key, f32)>, bool, bool) {
    let y = w.add_box(KY, BoxSpec::new([0.4; 3], 1.0), at([-2.0, 0.2, 0.0], ID)).is_ok();
    let r1 = w.ray([2.0, 3.0, 0.0], [0.0, -1.0, 0.0], 5.0).unwrap();
    let freed = w.remove(KY).is_ok();
    let r2 = w.ray([2.0, 3.0, 0.0], [0.0, -1.0, 0.0], 5.0).unwrap();
    w.impulse(KX, [3.0, 0.0, 0.0]).unwrap();
    (r1, r2, y, freed)
}

#[test]
fn c_isolation_between_instances() {
    let mut rep = Report::new("c_isolation_between_instances");
    // Referencias, cada una sola en el proceso.
    let (cp, r_i) = {
        let mut i = build(&NORMAL, &[], true);
        let Some(cp) = rule_k(&mut i) else {
            rep.noeval("C_regla_K", "sin contacto activo");
            return rep.finish();
        };
        (cp, branch(&mut i, 420))
    };
    let total = cp as usize + 30 + 420;
    let r_w2: Vec<Vec<Sample>> = {
        let mut w = build(&NORMAL, &[], true);
        (0..total).map(|_| { w2_step(&mut w); w.samples() }).collect()
    };
    let r_w3: Vec<Vec<Sample>> = {
        let mut w = w3_new();
        let mut h = Vec::new();
        for _ in 0..(cp as usize + 30) {
            w.step(DT).unwrap();
            h.push(w.samples());
        }
        w3_ops(&mut w);
        for _ in 0..420 {
            w.step(DT).unwrap();
            h.push(w.samples());
        }
        h
    };
    let r_w4: Vec<Vec<Sample>> = {
        let mut w = build(&NORMAL, &[], true);
        (0..120).map(|_| { w.step(DT).unwrap(); w.samples() }).collect()
    };

    // Ensayo intercalado.
    let mut ip = build(&NORMAL, &[], true);
    let mut w2 = build(&NORMAL, &[], true);
    let mut w3 = w3_new();
    let mut h2 = Vec::new();
    let mut h3 = Vec::new();
    let mut cp_ip = None;
    for s in 1..=120u64 {
        ip.step(DT).unwrap();
        w2_step(&mut w2);
        h2.push(w2.samples());
        w3.step(DT).unwrap();
        h3.push(w3.samples());
        if s == cp {
            cp_ip = Some(s);
            break;
        }
    }
    rep.check("C0_mismo_tick_de_checkpoint", cp_ip == Some(cp) && ip.tick() == cp, format!("cp_referencia={cp} tick_I'={}", ip.tick()), "igual");
    assert_eq!(ip.cache_checkpoint().unwrap(), cp);
    for _ in 0..30 {
        ip.step(DT).unwrap();
        w2_step(&mut w2);
        h2.push(w2.samples());
        w3.step(DT).unwrap();
        h3.push(w3.samples());
    }
    let s2 = w2.samples();
    let b2 = w2.snapshot().unwrap();
    let s3 = w3.samples();
    let ok = ip.restore_cached(cp).is_ok();
    let c1 = s2 == w2.samples() && b2 == w2.snapshot().unwrap() && s3 == w3.samples();
    rep.check("C1_otros_sin_cambios", ok && c1, format!("restaurado={ok} iguales={c1}"), "muestras y snapshot iguales");
    let (r1, r2, y_ok, freed) = w3_ops(&mut w3);
    let ri = ip.ray([2.0, 3.0, 0.0], [0.0, -1.0, 0.0], 5.0).unwrap();
    rep.check(
        "C2_rayos_y_altas_bajas_ajenas",
        y_ok && freed && matches!(r1, Some((kk, _)) if kk == KX) && matches!(r2, Some((kk, _)) if kk == KX) && !matches!(ri, Some((kk, _)) if kk == KX) && matches!(ri, Some((kk, d)) if kk == KF && (d - 3.0).abs() <= EPS),
        format!("Y_creado={y_ok} rayo_con_Y={r1:?} Y_liberado={freed} rayo_sin_Y={r2:?} rayo_en_I'={ri:?}"),
        "X, X, y en I' el piso propio a 3 m",
    );
    let x0 = w3.sample(KX).unwrap().pose[0];
    let mut hi = Vec::new();
    let mut w4: Option<ObjectWorld> = None;
    let mut h4 = Vec::new();
    let mut x_awake_first = None;
    for j in 1..=420usize {
        if j == 30 {
            ip.impulse(KA, [1.0, 0.0, 0.3]).unwrap();
        }
        if j == 330 {
            ip.impulse(KB, [0.0, 0.0, 0.6]).unwrap();
        }
        ip.step(DT).unwrap();
        hi.push(ip.samples());
        w2_step(&mut w2);
        h2.push(w2.samples());
        w3.step(DT).unwrap();
        h3.push(w3.samples());
        if x_awake_first.is_none() {
            x_awake_first = Some(!w3.sample(KX).unwrap().sleeping);
        }
        if j == 1 {
            w4 = Some(build(&NORMAL, &[], true));
        }
        if let Some(w) = w4.as_mut() {
            if h4.len() < 120 {
                w.step(DT).unwrap();
                h4.push(w.samples());
            }
        }
    }
    let di = diff_hist(&r_i, &hi);
    let d2 = diff_hist(&r_w2, &h2);
    let d3 = diff_hist(&r_w3, &h3);
    rep.check("C3_isla_igual_a_su_referencia", di.within(), di.text(), "≤ EPS, 420 pasos");
    rep.check("C3_W2_igual_a_su_control", d2.within(), d2.text(), "≤ EPS");
    rep.check("C3_W3_igual_a_su_control", d3.within(), d3.text(), "≤ EPS");
    rep.info("C3_exacta_bits", format!("isla={} W2={} W3={}", di.exact, d2.exact, d3.exact));
    let x1 = w3.sample(KX).unwrap().pose[0];
    rep.check("C4_X_avanza_despierto", x1 - x0 >= 0.1 && x_awake_first == Some(true), format!("avance={} despierto_en_el_primer_paso={:?}", x1 - x0, x_awake_first), "≥ 0,1 m y despierto");
    let d4 = diff_hist(&r_w4, &h4);
    rep.check("C5_mundo_creado_despues", d4.within(), d4.text(), "≤ EPS, 120 pasos");
    rep.finish();
}
