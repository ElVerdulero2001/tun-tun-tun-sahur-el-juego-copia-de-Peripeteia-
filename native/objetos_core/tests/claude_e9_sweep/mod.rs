//! Validación independiente (Claude), entrega 9: N2, barrido de todos los bits del payload.
//! Misma fuente que D18 (fixture F, regla K + 3 pasos). Criterios: criterios_entrega_9.md §5 N2.
use crate::claude_common::*;
use sahur_object_world::world::*;
use std::collections::BTreeMap;
use std::panic::{AssertUnwindSafe, catch_unwind};

fn dest() -> ObjectWorld {
    build(&NORMAL, &[], true)
}

pub fn sweep(name: &'static str, bits: std::ops::Range<u32>) {
    let mut rep = Report::new(name);
    let mut src = build(&NORMAL, &[], true);
    let cp = rule_k(&mut src).expect("regla K");
    for _ in 0..3 {
        src.step(DT).unwrap();
    }
    let snap = src.snapshot().unwrap();
    let src_samples = src.samples();
    let floor_bits: Vec<u32> = src_samples[0].pose.iter().map(|v| v.to_bits()).collect();
    let fresh = dest().snapshot().unwrap();
    let payload = &snap[44..];
    rep.info(&format!("{name}_fuente"), format!("tick={} checkpoint_K={cp} bytes={} bits={bits:?}", src.tick(), snap.len()));
    let start = std::time::Instant::now();
    let prev = std::panic::take_hook();
    std::panic::set_hook(Box::new(|_| {}));
    let (mut total, mut p_restore, mut p_samples, mut p_rays, mut changed, mut fixed) = (0usize, Vec::new(), 0usize, 0usize, 0usize, Vec::new());
    let mut codes: BTreeMap<&str, usize> = BTreeMap::new();
    let mut accepted: BTreeMap<&str, usize> = BTreeMap::new();
    for i in 0..payload.len() {
        for bit in bits.clone() {
            total += 1;
            let mut p = payload.to_vec();
            p[i] ^= 1 << bit;
            let env = envelope(&p);
            let mut d = dest();
            match catch_unwind(AssertUnwindSafe(|| d.restore_trusted(&env))) {
                Err(_) => p_restore.push((i, bit)),
                Ok(Err(e)) => {
                    *codes.entry(e.0).or_default() += 1;
                    if d.snapshot().unwrap() != fresh {
                        changed += 1;
                    }
                }
                Ok(Ok(())) => {
                    let Ok(s) = catch_unwind(AssertUnwindSafe(|| d.samples())) else {
                        p_samples += 1;
                        continue;
                    };
                    if catch_unwind(AssertUnwindSafe(|| grid_rays(&d))).is_err() {
                        p_rays += 1;
                    }
                    let fb: Vec<u32> = s[0].pose.iter().map(|v| v.to_bits()).collect();
                    let class = if s[0].key != KF || fb != floor_bits {
                        fixed.push((i, bit));
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
    }
    std::panic::set_hook(prev);
    let acc: usize = accepted.values().sum();
    rep.check(&format!("{name}_sin_panico_en_restore"), p_restore.is_empty(), format!("mutaciones={total} panicos={} primeros={:?}", p_restore.len(), p_restore.iter().take(8).collect::<Vec<_>>()), "0");
    rep.check(&format!("{name}_rechazo_sin_cambios"), changed == 0, format!("rechazos_que_cambiaron={changed}"), "0");
    rep.check(&format!("{name}_piso_intacto_en_aceptadas"), fixed.is_empty(), format!("aceptadas_con_piso_distinto={} primeras={:?}", fixed.len(), fixed.iter().take(8).collect::<Vec<_>>()), "0");
    rep.check(&format!("{name}_sin_panico_en_muestras_y_rayos"), p_samples == 0 && p_rays == 0, format!("muestras={p_samples} rayos={p_rays}"), "0");
    rep.info(&format!("{name}_codigos"), format!("{codes:?}"));
    rep.info(&format!("{name}_aceptadas"), format!("total={acc} de {total} clases={accepted:?}"));
    rep.info(&format!("{name}_tiempo"), format!("{:.3} s", start.elapsed().as_secs_f64()));
    rep.finish();
}
