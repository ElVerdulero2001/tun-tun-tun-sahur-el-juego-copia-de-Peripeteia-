//! Validación independiente (Claude), entrega 8: A1-A6, B1-B3, F1-F4.
//! Criterios: docs/net/validacion_objetos/criterios_entrega_8.md §3.2, §3.3 y §3.5.
mod claude_common;
use claude_common::*;
use sahur_object_world::world::*;

#[test]
fn a_contact_sleep_wake_and_b_identity() {
    let mut rep = Report::new("a_contact_sleep_wake_and_b_identity");
    let mut w = build(&NORMAL, &[], true);
    let Some(cp) = rule_k(&mut w) else {
        rep.noeval("A_regla_K", "no hubo contacto dinámico activo en 120 pasos");
        return rep.finish();
    };
    let a = w.sample(KA).unwrap();
    let b = w.sample(KB).unwrap();
    rep.info(
        "A0_checkpoint",
        format!(
            "tick={cp} vA={:?} vB={:?} contactos_A={:?} contactos_B={:?} dormidos=({},{})",
            a.linear, b.linear, a.contacts, b.contacts, a.sleeping, b.sleeping
        ),
    );
    let initial = w.samples();
    let rays_cp = grid_rays(&w);
    let snap = w.snapshot().unwrap();
    rep.info("A0_bytes_checkpoint", format!("{}", snap.len()));
    assert_eq!(w.cache_checkpoint().unwrap(), cp);

    // Referencia, con el snapshot dormido (A3) y el estado en el despertar.
    let mut sleep_snap: Option<(usize, Vec<u8>)> = None;
    let reference = branch_range(&mut w, 1, 420, [1.0, 0.0, 0.3], |j, w| {
        if sleep_snap.is_none() && (31..=329).contains(&j) {
            let s = w.samples();
            if s.iter().filter(|x| x.key != KF).all(|x| x.sleeping) {
                sleep_snap = Some((j, w.snapshot().unwrap()));
            }
        }
    });
    let v1 = sleep_snap.is_some();
    let b330 = reference[329].iter().find(|x| x.key == KB).unwrap().clone();
    let v2 = !b330.sleeping;
    rep.info(
        "A0_validez",
        format!("V1_todos_dormidos={} paso={:?} V2_B_despierto_en_330={} vB_330={:?}", v1, sleep_snap.as_ref().map(|x| x.0), v2, b330.linear),
    );
    let ref_sha = hist_sha(&reference);
    println!("CLAUDE_TRAJ_SHA\t{ref_sha}");

    // A1: caché local en el mismo mundo.
    let ok = w.restore_cached(cp).is_ok();
    let d0 = diff_samples(&initial, &w.samples());
    let rep1 = branch(&mut w, 420);
    let d1 = diff_hist(&reference, &rep1);
    rep.check("A1_restore_cached_contacto", ok && d0.within() && d1.within(), format!("restaurado={ok} inicial: {} | repetición: {}", d0.text(), d1.text()), "≤ EPS, reposo/contactos iguales, 420 pasos");
    rep.info("A5_A1_exacta_bits", format!("{}", d0.exact && d1.exact));
    rep.check("A6_sha_en_proceso", hist_sha(&rep1) == ref_sha, hist_sha(&rep1), "igual a la referencia");

    // A2/B1: snapshot en otros destinos.
    let dests: Vec<(&str, ObjectWorld)> = vec![
        ("D1_inverso", build(&REVERSE, &[], true)),
        ("D2_retirados_y_mezclado", build(&SHUFFLED, &[90, 91], true)),
        ("D3_inverso_avanzado_50", {
            let mut d = build(&REVERSE, &[], true);
            for _ in 0..50 {
                d.step(DT).unwrap();
            }
            d
        }),
    ];
    for (name, mut d) in dests {
        let before = d.samples();
        let pre = diff_samples(&before, &initial);
        let ok = d.restore_trusted(&snap).is_ok();
        let di = diff_samples(&initial, &d.samples());
        let rays = grid_rays(&d);
        let rays_ok = rays == rays_cp;
        let rh = branch(&mut d, 420);
        let dr = diff_hist(&reference, &rh);
        rep.check(
            &format!("A2_{name}"),
            ok && di.within() && dr.within(),
            format!("antes_de_importar_distinto={} restaurado={ok} inicial: {} | repetición: {}", !pre.within(), di.text(), dr.text()),
            "≤ EPS, reposo/contactos iguales, 420 pasos",
        );
        rep.info(&format!("A5_{name}_exacta_bits"), format!("{}", di.exact && dr.exact));
        rep.check(&format!("B1_{name}_rayos"), ok && rays_ok, format!("{:?}", rays), "misma identidad y distancia (bits) que el origen");
    }
    let hits = rays_cp.iter().filter(|r| r.is_some()).count();
    rep.info("B1_rayos_origen", format!("aciertos={hits}/12 detalle={:?}", rays_cp));

    // A3: checkpoint dormido.
    if let (true, true, Some((js, ss))) = (v1, v2, sleep_snap.as_ref()) {
        let mut d = build(&REVERSE, &[], true);
        let ok = d.restore_trusted(ss).is_ok();
        let tail = branch_range(&mut d, js + 1, 420, [1.0, 0.0, 0.3], |_, _| {});
        let dt = diff_hist(&reference[*js..], &tail);
        let woke = !tail[329 - js].iter().find(|x| x.key == KB).unwrap().sleeping;
        let asleep_before = tail[328 - js].iter().find(|x| x.key == KB).unwrap().sleeping;
        rep.check(
            "A3_checkpoint_dormido",
            ok && dt.within() && woke && asleep_before,
            format!("paso_dormido={js} restaurado={ok} B_dormido_329={asleep_before} B_despierto_330={woke} {}", dt.text()),
            "≤ EPS hasta 420 y despertar en 330",
        );
        rep.info("A5_A3_exacta_bits", format!("{}", dt.exact));
    } else {
        rep.noeval("A3_checkpoint_dormido", format!("V1={v1} V2={v2}"));
    }

    // A4: sensibilidad.
    let ok = w.restore_cached(cp).is_ok();
    let alt = branch_range(&mut w, 1, 420, [1.0, 0.0, 0.31], |_, _| {});
    let da = diff_hist(&reference, &alt);
    rep.check("A4_control_negativo", ok && da.magnitude() > SENS, da.text(), "> 1e-3 (sensibilidad)");
    rep.finish();
}

#[test]
fn b2_ray_distances() {
    let mut rep = Report::new("b2_ray_distances");
    let floor = fixture_f()[0].clone();
    let mut w = ObjectWorld::default();
    add(&mut w, &floor).unwrap();
    let r = w.ray([0.0, 3.0, 0.0], [0.0, -1.0, 0.0], 5.0).unwrap();
    rep.check("B2_piso", matches!(r, Some((kk, d)) if kk == KF && (d - 3.0).abs() <= EPS), format!("{r:?}"), "piso, 3 m ± 1e-5");
    let w = build(&NORMAL, &[], false);
    let r = w.ray([-0.7, 3.0, 0.2], [0.0, -1.0, 0.0], 5.0).unwrap();
    rep.check("B2_C_recien_creada", matches!(r, Some((kk, d)) if kk == KC && (d - 2.7).abs() <= EPS), format!("{r:?}"), "C, 2,7 m ± 1e-5, sin pasos");
    let miss = w.ray([3.5, 3.0, 3.5], [0.0, 1.0, 0.0], 5.0).unwrap();
    rep.check("B2_sin_acierto", miss.is_none(), format!("{miss:?}"), "None");
    rep.finish();
}

#[test]
fn b3_epochs() {
    let mut rep = Report::new("b3_epochs");
    let mut bodies = fixture_f();
    bodies[2].key = k(20, 3);
    let mut s = ObjectWorld::default();
    for e in 1..=2 {
        s.add_box(k(20, e), BoxSpec::new([0.4; 3], 1.0), at([0.1, 0.9, 0.05], ID)).unwrap();
        s.remove(k(20, e)).unwrap();
    }
    for b in &bodies {
        add(&mut s, b).unwrap();
    }
    s.seal(1).unwrap();
    for _ in 0..20 {
        s.step(DT).unwrap();
    }
    let snap = s.snapshot().unwrap();
    let initial = s.samples();
    let mut href = Vec::new();
    for _ in 0..120 {
        s.step(DT).unwrap();
        href.push(s.samples());
    }
    let mut d = build_from(&bodies, &REVERSE, &[], true);
    let ok = d.restore_trusted(&snap).is_ok();
    let di = diff_samples(&initial, &d.samples());
    let mut hd = Vec::new();
    for _ in 0..120 {
        d.step(DT).unwrap();
        hd.push(d.samples());
    }
    let dh = diff_hist(&href, &hd);
    rep.check("B3_misma_aparicion_sin_historia", ok && di.within() && dh.within(), format!("restaurado={ok} {} | {}", di.text(), dh.text()), "≤ EPS");
    let mut e = build(&REVERSE, &[], true);
    let before = e.snapshot().unwrap();
    let r = e.restore_trusted(&snap);
    let same = e.snapshot().unwrap() == before;
    rep.check("B3_aparicion_vieja_rechazada", err_code(&r) == "snapshot_identity" && same, format!("{} sin_cambios={same}", err_code(&r)), "snapshot_identity, sin cambios");
    rep.noeval("B4_retirados", "el mapa de retirados no es observable por la API una vez sellada la topología");
    rep.finish();
}

fn hold_timeline(w: &mut ObjectWorld, n: u64, goals: bool) -> Result<()> {
    if n == 1 {
        w.begin_hold(KC, [0.05, 0.0, 0.0], at([-0.7, 0.5, 0.2], ID))?;
    }
    if goals && (2..=60).contains(&n) {
        let f = n as f32;
        w.set_goal(KC, at([-0.7 + 0.01 * f, 0.5 + 0.002 * f, 0.2], quat([0.0, 1.0, 0.0], 0.02 * f)))?;
    }
    if n == 61 {
        w.release(KC, [0.3, 0.2, 0.0])?;
    }
    Ok(())
}

#[test]
fn f_controller_in_checkpoint() {
    let mut rep = Report::new("f_controller_in_checkpoint");
    let mut w = build(&NORMAL, &[], true);
    let mut href: Vec<Vec<Sample>> = Vec::new();
    let mut cp25 = Vec::new();
    let mut cp70 = Vec::new();
    for n in 1..=180u64 {
        hold_timeline(&mut w, n, true).unwrap();
        w.step(DT).unwrap();
        href.push(w.samples());
        if n == 25 {
            assert_eq!(w.cache_checkpoint().unwrap(), 25);
            cp25 = w.snapshot().unwrap();
        }
        if n == 70 {
            cp70 = w.snapshot().unwrap();
        }
    }
    let c25 = &href[24].iter().find(|x| x.key == KC).unwrap();
    rep.info("F0_C_en_25", format!("held={} v={:?} contactos={:?}", c25.held, c25.linear, c25.contacts));
    let replay = |w: &mut ObjectWorld, goals: bool| -> Vec<Vec<Sample>> {
        (26..=180u64)
            .map(|n| {
                hold_timeline(w, n, goals).unwrap();
                w.step(DT).unwrap();
                w.samples()
            })
            .collect()
    };
    // F1a + F3 (agarre restaurado).
    let ok = w.restore_cached(25).is_ok();
    let before = w.snapshot().unwrap();
    let again = w.begin_hold(KC, [0.0; 3], at([0.0, 1.0, 0.0], ID));
    let unchanged = w.snapshot().unwrap() == before;
    rep.check("F3_agarre_viene_en_el_checkpoint", err_code(&again) == "invalid_hold_transition" && unchanged, format!("{} sin_cambios={unchanged}", err_code(&again)), "invalid_hold_transition, sin cambios");
    let r1 = replay(&mut w, true);
    let d1 = diff_hist(&href[25..], &r1);
    rep.check("F1_restore_cached_25", ok && d1.within(), d1.text(), "≤ EPS, agarre igual, 26..180");
    let before = w.snapshot().unwrap();
    let second = w.release(KC, [0.3, 0.2, 0.0]);
    let unchanged = w.snapshot().unwrap() == before;
    rep.check("F3_segunda_suelta", err_code(&second) == "not_held" && unchanged, format!("{} sin_cambios={unchanged}", err_code(&second)), "not_held, sin cambios");
    // F1b
    let mut d = build(&REVERSE, &[], true);
    let ok = d.restore_trusted(&cp25).is_ok();
    let r2 = replay(&mut d, true);
    let d2 = diff_hist(&href[25..], &r2);
    rep.check("F1_restore_trusted_inverso", ok && d2.within(), d2.text(), "≤ EPS, agarre igual, 26..180");
    rep.info("F1_exacta_bits", format!("{}", d1.exact && d2.exact));
    // F2
    let ok = w.restore_cached(25).is_ok();
    let r3 = replay(&mut w, false);
    let d3 = diff_hist(&href[25..], &r3);
    rep.check("F2_sin_objetivos_se_separa", ok && d3.magnitude() > SENS, d3.text(), "> 1e-3 (sensibilidad)");
    // F4
    let mut g = build(&NORMAL, &[], true);
    for n in 1..=30u64 {
        hold_timeline(&mut g, n, true).unwrap();
        g.step(DT).unwrap();
    }
    let held_before = g.sample(KC).unwrap().held;
    let ok = g.restore_trusted(&cp70).is_ok();
    let held_after = g.sample(KC).unwrap().held;
    let goal = g.set_goal(KC, at([0.0, 1.0, 0.0], ID));
    rep.check(
        "F4_importar_suelta_quita_agarre",
        held_before && ok && !held_after && err_code(&goal) == "not_held",
        format!("agarrado_antes={held_before} restaurado={ok} agarrado_despues={held_after} set_goal={}", err_code(&goal)),
        "held=false y not_held",
    );
    rep.finish();
}
