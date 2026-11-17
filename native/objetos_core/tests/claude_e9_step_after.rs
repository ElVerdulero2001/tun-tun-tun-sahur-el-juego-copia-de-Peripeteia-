//! Validación independiente (Claude), entrega 9: N3 (informativo), un paso después de aceptar.
//! Mismas mutaciones que D18 (un bit por byte, bit = índice % 8, suma recalculada).
//! Imprime CLAUDE_STEP_AT antes de cada paso para ubicar un cuelgue si vence el límite externo.
//! CLAUDE_STEP_START (env) reanuda desde un índice; CLAUDE_STEP_SKIP (env, lista) saltea índices.
mod claude_common;
use claude_common::*;
use std::collections::BTreeMap;
use std::io::Write;
use std::panic::{AssertUnwindSafe, catch_unwind};

#[test]
fn n3_step_after_accept() {
    let mut rep = Report::new("n3_step_after_accept");
    let start_at: usize = std::env::var("CLAUDE_STEP_START").ok().and_then(|v| v.parse().ok()).unwrap_or(0);
    let skip: Vec<usize> = std::env::var("CLAUDE_STEP_SKIP").unwrap_or_default().split(',').filter_map(|v| v.trim().parse().ok()).collect();
    let mut src = build(&NORMAL, &[], true);
    rule_k(&mut src).expect("regla K");
    for _ in 0..3 {
        src.step(DT).unwrap();
    }
    let snap = src.snapshot().unwrap();
    let floor_bits: Vec<u32> = src.samples()[0].pose.iter().map(|v| v.to_bits()).collect();
    let payload = &snap[44..];
    let prev = std::panic::take_hook();
    std::panic::set_hook(Box::new(|_| {}));
    let mut out: BTreeMap<&str, usize> = BTreeMap::new();
    let mut examples: BTreeMap<&str, Vec<usize>> = BTreeMap::new();
    let mut note = |k: &'static str, i: usize| {
        *out.entry(k).or_default() += 1;
        let e = examples.entry(k).or_default();
        if e.len() < 6 {
            e.push(i);
        }
    };
    let stdout = std::io::stdout();
    for i in start_at..payload.len() {
        if skip.contains(&i) {
            continue;
        }
        let mut p = payload.to_vec();
        p[i] ^= 1 << (i % 8);
        let env = envelope(&p);
        let mut d = build(&NORMAL, &[], true);
        if !matches!(catch_unwind(AssertUnwindSafe(|| d.restore_trusted(&env))), Ok(Ok(()))) {
            continue;
        }
        {
            let mut h = stdout.lock();
            let _ = writeln!(h, "CLAUDE_STEP_AT\t{i}");
            let _ = h.flush();
        }
        match catch_unwind(AssertUnwindSafe(|| d.step(DT))) {
            Err(_) => note("panico_en_paso", i),
            Ok(Err(_)) => note("error_en_paso", i),
            Ok(Ok(())) => match catch_unwind(AssertUnwindSafe(|| d.samples())) {
                Err(_) => note("panico_al_muestrear_tras_paso", i),
                Ok(s) => {
                    let finite = s.iter().all(|x| x.pose.iter().chain(&x.linear).chain(&x.angular).all(|v| v.is_finite()));
                    let fb: Vec<u32> = s[0].pose.iter().map(|v| v.to_bits()).collect();
                    if !finite {
                        note("valores_no_finitos_tras_paso", i);
                    } else if fb != floor_bits {
                        note("piso_movido_tras_paso", i);
                    } else {
                        note("paso_normal", i);
                    }
                }
            },
        }
    }
    std::panic::set_hook(prev);
    rep.info("N3_resultado", format!("desde={start_at} salteados={skip:?} conteo={out:?} ejemplos={examples:?}"));
    rep.finish();
}
