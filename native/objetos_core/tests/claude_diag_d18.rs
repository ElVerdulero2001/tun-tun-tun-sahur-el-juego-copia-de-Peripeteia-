//! Diagnóstico (no decide), entrega 8: detalle de D18b. Para cada mutación aceptada que
//! después hace fallar `samples()`, el byte y el mensaje del pánico; para las que cambian el
//! cuerpo fijo, qué componente cambió. Misma fuente y misma regla de mutación que claude_mutations.rs.
mod claude_common;
use claude_common::*;
use sahur_object_world::world::*;
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::sync::Mutex;

static LAST: Mutex<String> = Mutex::new(String::new());

#[test]
fn diag_d18_detail() {
    let mut rep = Report::new("diag_d18_detail");
    let mut src = build(&NORMAL, &[], true);
    rule_k(&mut src).expect("regla K");
    for _ in 0..3 {
        src.step(DT).unwrap();
    }
    let snap = src.snapshot().unwrap();
    let src_samples = src.samples();
    let payload = &snap[44..];
    let prev = std::panic::take_hook();
    std::panic::set_hook(Box::new(|info| {
        let msg = info.payload().downcast_ref::<&str>().map(|s| s.to_string()).or_else(|| info.payload().downcast_ref::<String>().cloned()).unwrap_or_default();
        let loc = info.location().map(|l| format!("{}:{}", l.file(), l.line())).unwrap_or_default();
        *LAST.lock().unwrap() = format!("{msg} @ {loc}");
    }));
    let mut panics = Vec::new();
    let mut fixed = Vec::new();
    let mut steps_after_fixed = Vec::new();
    for i in 0..payload.len() {
        let mut p = payload.to_vec();
        p[i] ^= 1 << (i % 8);
        let env = envelope(&p);
        let mut d = build(&NORMAL, &[], true);
        let Ok(Ok(())) = catch_unwind(AssertUnwindSafe(|| d.restore_trusted(&env))) else { continue };
        match catch_unwind(AssertUnwindSafe(|| d.samples())) {
            Err(_) => panics.push(format!("byte={i} bit={} msg={}", i % 8, LAST.lock().unwrap())),
            Ok(s) if s.len() == src_samples.len() && s[0].pose != src_samples[0].pose => {
                let comp: Vec<String> = (0..7).filter(|c| s[0].pose[*c].to_bits() != src_samples[0].pose[*c].to_bits())
                    .map(|c| format!("c{c}:{:e}->{:e}", src_samples[0].pose[c], s[0].pose[c])).collect();
                fixed.push(format!("byte={i} {}", comp.join(",")));
                // ¿El mundo con el piso alterado sigue avanzando? Un paso, sin bucles largos.
                let r = catch_unwind(AssertUnwindSafe(|| d.step(DT).is_ok()));
                steps_after_fixed.push(match r { Ok(true) => "ok", Ok(false) => "err", Err(_) => "panico" });
            }
            _ => {}
        }
    }
    std::panic::set_hook(prev);
    rep.info("DIAG_D18_panicos", format!("{} | {}", panics.len(), panics.join(" ; ")));
    rep.info("DIAG_D18_cuerpo_fijo", format!("{} | {}", fixed.len(), fixed.join(" ; ")));
    rep.info("DIAG_D18_paso_tras_piso_alterado", format!("{steps_after_fixed:?}"));
    rep.finish();
}
