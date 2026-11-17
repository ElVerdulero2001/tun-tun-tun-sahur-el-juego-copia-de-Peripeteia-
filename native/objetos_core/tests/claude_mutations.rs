//! Validación independiente (Claude), entrega 8: D18, barrido de mutaciones del snapshot.
//! Criterios: docs/net/validacion_objetos/criterios_entrega_8.md §3.6.
mod claude_common;
use claude_common::*;
use sahur_object_world::world::*;
use std::collections::BTreeMap;
use std::panic::{AssertUnwindSafe, catch_unwind};

fn dest() -> ObjectWorld {
    build(&NORMAL, &[], true)
}

#[test]
fn d18_mutation_sweep() {
    let mut rep = Report::new("d18_mutation_sweep");
    let mut src = build(&NORMAL, &[], true);
    let cp = rule_k(&mut src).expect("regla K");
    for _ in 0..3 {
        src.step(DT).unwrap();
    }
    let snap = src.snapshot().unwrap();
    let src_samples = src.samples();
    let fresh = dest().snapshot().unwrap();
    rep.info("D18_fuente", format!("tick={} checkpoint_K={cp} bytes={}", src.tick(), snap.len()));
    let start = std::time::Instant::now();
    let prev_hook = std::panic::take_hook();
    std::panic::set_hook(Box::new(|_| {}));

    // (a) sin recalcular la suma.
    let mut a_bad = 0usize;
    let mut a_codes: BTreeMap<&str, usize> = BTreeMap::new();
    for i in 0..snap.len() {
        let mut m = snap.clone();
        m[i] ^= 1 << (i % 8);
        let mut d = dest();
        let r = catch_unwind(AssertUnwindSafe(|| d.restore_trusted(&m)));
        match r {
            Ok(Err(e)) => {
                *a_codes.entry(e.0).or_default() += 1;
                if d.snapshot().unwrap() != fresh {
                    a_bad += 1;
                }
            }
            _ => a_bad += 1,
        }
    }
    // (b) con la suma recalculada.
    let payload = &snap[44..];
    let mut panics_restore = 0usize;
    let mut panics_after = 0usize;
    let mut changed_on_reject = 0usize;
    let mut codes: BTreeMap<&str, usize> = BTreeMap::new();
    let mut accepted: BTreeMap<&str, usize> = BTreeMap::new();
    let mut fixed_examples = Vec::new();
    for i in 0..payload.len() {
        let mut p = payload.to_vec();
        p[i] ^= 1 << (i % 8);
        let env = envelope(&p);
        let mut d = dest();
        match catch_unwind(AssertUnwindSafe(|| d.restore_trusted(&env))) {
            Err(_) => panics_restore += 1,
            Ok(Err(e)) => {
                *codes.entry(e.0).or_default() += 1;
                if d.snapshot().unwrap() != fresh {
                    changed_on_reject += 1;
                }
            }
            Ok(Ok(())) => {
                let s = catch_unwind(AssertUnwindSafe(|| d.samples()));
                let Ok(s) = s else {
                    panics_after += 1;
                    continue;
                };
                let class = if s.len() != src_samples.len() {
                    "cantidad"
                } else if s[0].pose != src_samples[0].pose {
                    if fixed_examples.len() < 5 {
                        fixed_examples.push(format!("byte={i} piso_y={} vs {}", s[0].pose[1], src_samples[0].pose[1]));
                    }
                    "pose_del_cuerpo_fijo"
                } else if s.iter().zip(&src_samples).any(|(x, y)| x.tick != y.tick) {
                    "tick"
                } else if s.iter().zip(&src_samples).any(|(x, y)| x.pose != y.pose || x.linear != y.linear || x.angular != y.angular) {
                    "dinamico"
                } else if s.iter().zip(&src_samples).any(|(x, y)| x.sleeping != y.sleeping || x.held != y.held || x.contacts != y.contacts) {
                    "reposo_agarre_o_contactos"
                } else {
                    "nada_visible_en_muestras"
                };
                *accepted.entry(class).or_default() += 1;
            }
        }
    }
    std::panic::set_hook(prev_hook);
    let total_accepted: usize = accepted.values().sum();
    rep.check("D18a_sin_suma_todo_rechazado", a_bad == 0, format!("mutaciones={} problemas={a_bad} codigos={a_codes:?}", snap.len()), "todas rechazadas y sin cambios");
    rep.check("D18b_sin_panico_en_restore", panics_restore == 0, format!("mutaciones={} panicos={panics_restore}", payload.len()), "0");
    rep.check("D18b_sin_panico_al_muestrear_aceptadas", panics_after == 0, format!("panicos={panics_after}"), "0");
    rep.check("D18b_rechazo_sin_cambios", changed_on_reject == 0, format!("rechazos_que_cambiaron={changed_on_reject}"), "0");
    rep.info("D18b_codigos_de_rechazo", format!("{codes:?}"));
    rep.info("D18b_aceptadas", format!("total={total_accepted} de {} clases={accepted:?}", payload.len()));
    rep.info("D18b_ejemplos_cuerpo_fijo", format!("{fixed_examples:?}"));
    rep.info("D18_tiempo", format!("{:.3} s", start.elapsed().as_secs_f64()));
    rep.finish();
}
