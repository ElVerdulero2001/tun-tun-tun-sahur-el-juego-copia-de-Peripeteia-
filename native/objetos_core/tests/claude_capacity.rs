//! Validación independiente (Claude), entrega 8: D06, D08 y E3 (capacidad y caché por bytes).
//! Criterios: docs/net/validacion_objetos/criterios_entrega_8.md §3.6 y §3.7.
mod claude_common;
use claude_common::*;
use sahur_object_world::world::*;
use std::collections::VecDeque;

fn pile() -> ObjectWorld {
    let mut w = ObjectWorld::default();
    w.add_box(KF, BoxSpec::new([8.0, 0.2, 8.0], 0.0), at([0.0, -0.1, 0.0], ID)).unwrap();
    let mut uid = 1000;
    'outer: for layer in 0..6 {
        for i in 0..5 {
            for j in 0..5 {
                if w.body_count() >= MAX_BODIES {
                    break 'outer;
                }
                let off = 0.01 * ((i * 3 + j * 7 + layer * 5) % 5) as f32;
                let p = [-0.6 + 0.3 * i as f32 + off, 0.13 + 0.27 * layer as f32, -0.6 + 0.3 * j as f32 - off];
                let r = quat([0.0, 1.0, 0.0], 0.05 * ((i + j + layer) % 4) as f32);
                w.add_box(key(uid), BoxSpec::new([0.25; 3], 0.5), at(p, r)).unwrap();
                uid += 1;
            }
        }
    }
    w
}

#[test]
fn d06_d08_capacity_limits() {
    let mut rep = Report::new("d06_d08_capacity_limits");
    let mut w = pile();
    rep.check("D06_128_aceptados", w.body_count() == MAX_BODIES && MAX_BODIES == 128, format!("cuerpos={}", w.body_count()), "128");
    let before = w.samples();
    let r = w.add_box(key(5000), BoxSpec::new([0.25; 3], 0.5), at([3.0, 0.2, 3.0], ID));
    let same = w.samples() == before && w.body_count() == 128;
    rep.check("D06_129_rechazado", err_code(&r) == "body_capacity" && same, format!("{} sin_cambios={same}", err_code(&r)), "body_capacity");

    let mut w = ObjectWorld::default();
    let mut all = true;
    for uid in 1..=512u32 {
        all &= w.add_box(key(uid), BoxSpec::new([0.2; 3], 0.3), at([0.0, 0.1, 0.0], ID)).is_ok();
        all &= w.remove(key(uid)).is_ok();
    }
    rep.check("D08_512_retirados", all, format!("todos_aceptados={all}"), "aceptados");
    w.add_box(key(2000), BoxSpec::new([0.2; 3], 0.3), at([0.0, 0.1, 0.0], ID)).unwrap();
    let r = w.remove(key(2000));
    let still = w.sample(key(2000)).is_ok() && w.body_count() == 1;
    rep.check("D08_retiro_513", err_code(&r) == "retired_capacity" && still, format!("{} sigue={still}", err_code(&r)), "retired_capacity y el cuerpo sigue");
    let again = w.remove(key(2000));
    rep.info("D08_reintento", err_code(&again));
    let reuse = w.remove(key(1));
    rep.info("D08_retirar_uid_ya_retirado_desconocido", err_code(&reuse));
    rep.finish();
}

#[test]
fn e3_cache_byte_limit_with_128_bodies() {
    let mut rep = Report::new("e3_cache_byte_limit_with_128_bodies");
    let mut w = pile();
    w.seal(1).unwrap();
    let start = std::time::Instant::now();
    for _ in 0..90 {
        w.step(DT).unwrap();
    }
    let s = w.samples();
    let contacts: usize = s.iter().map(|x| x.contacts.len()).sum();
    let snap = w.snapshot();
    let len = snap.as_ref().map(|b| b.len()).unwrap_or(0);
    rep.check("E3_snapshot_128_cuerpos", snap.is_ok(), format!("bytes={len} contactos_listados={contacts} fraccion_de_1MiB={:.4}", len as f64 / MAX_SNAPSHOT_BYTES as f64), "≤ 1 MiB + 44");
    let mut model: VecDeque<(u64, usize)> = VecDeque::new();
    let mut model_bytes = 0usize;
    let mut agree = true;
    let mut max_len = 0;
    for _ in 0..150 {
        let l = w.snapshot().unwrap().len();
        max_len = max_len.max(l);
        let t = w.cache_checkpoint().unwrap();
        model.push_back((t, l));
        model_bytes += l;
        while model.len() > MAX_CACHED_TICKS || model_bytes > 16 * MAX_SNAPSHOT_BYTES {
            model_bytes -= model.pop_front().unwrap().1;
        }
        agree &= w.cache_stats() == (model.len(), model_bytes);
        w.step(DT).unwrap();
    }
    let (count, bytes) = w.cache_stats();
    let exercised = 120 * max_len > 16 * MAX_SNAPSHOT_BYTES;
    rep.check("E3_regla_simulada_coincide", agree && bytes <= 16 * MAX_SNAPSHOT_BYTES, format!("cantidad={count} bytes={bytes} modelo=({},{}) maximo_snapshot={max_len}", model.len(), model_bytes), "igual a mi simulación, ≤ 16 MiB");
    if exercised {
        rep.check("E3_limite_de_bytes", count < 120, format!("cantidad={count}"), "< 120 por bytes");
    } else {
        rep.noeval("E3_limite_de_bytes", format!("no ejercitado: 120 × {max_len} = {} < 16 MiB", 120 * max_len));
    }
    rep.info("E3_tiempo", format!("{:.3} s para 240 pasos y 300 snapshots con 128 cuerpos (perfil dev opt 1; no es medida de rendimiento)", start.elapsed().as_secs_f64()));
    rep.finish();
}
