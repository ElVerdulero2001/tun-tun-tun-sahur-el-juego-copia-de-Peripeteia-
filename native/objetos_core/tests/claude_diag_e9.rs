//! Diagnóstico (no decide), entrega 9:
//! (1) ubica en el payload los parámetros de integración (dt y los contadores usize del solver),
//!     para explicar los cuelgues de N3;
//! (2) para las 5 mutaciones de N2 que solo cambian el signo de un cero del piso, compara 300 pasos
//!     contra el snapshot genuino.
//! Misma fuente que D18 y N2.
mod claude_common;
use claude_common::*;

fn find(hay: &[u8], needle: &[u8]) -> Vec<usize> {
    (0..=hay.len().saturating_sub(needle.len())).filter(|&i| &hay[i..i + needle.len()] == needle).collect()
}

#[test]
fn diag_e9() {
    let mut rep = Report::new("diag_e9");
    let mut src = build(&NORMAL, &[], true);
    rule_k(&mut src).unwrap();
    for _ in 0..3 {
        src.step(DT).unwrap();
    }
    let snap = src.snapshot().unwrap();
    let payload = &snap[44..];
    let dt = find(payload, &DT.to_le_bytes());
    let mut iters = Vec::new();
    for a in [4u64, 1, 2, 8] {
        let mut pat = a.to_le_bytes().to_vec();
        pat.extend_from_slice(&1u64.to_le_bytes());
        iters.push(format!("{a},1@{:?}", find(payload, &pat).iter().take(4).collect::<Vec<_>>()));
    }
    let window: Vec<String> = (140..180).map(|i| format!("{i}:{:02x}", payload[i])).collect();
    rep.info("DIAG_E9_parametros", format!("dt_en={:?} usize_seguidos={iters:?} bytes_140_179=[{}]", dt.iter().take(4).collect::<Vec<_>>(), window.join(" ")));
    let hang: Vec<String> = [159usize, 160, 161, 162, 163, 167]
        .iter()
        .map(|&i| {
            let start = i - (i % 8);
            let old = u64::from_le_bytes(payload[start..start + 8].try_into().unwrap());
            let mut p = payload.to_vec();
            p[i] ^= 1 << (i % 8);
            let new = u64::from_le_bytes(p[start..start + 8].try_into().unwrap());
            format!("byte {i}: palabra alineada {start}..{} {old} -> {new}", start + 8)
        })
        .collect();
    rep.info("DIAG_E9_cuelgues", hang.join(" ; "));
    // (2) signo del cero.
    let mut genuine = build(&NORMAL, &[], true);
    genuine.restore_trusted(&snap).unwrap();
    let mut gh = Vec::new();
    for _ in 0..300 {
        genuine.step(DT).unwrap();
        gh.push(genuine.samples());
    }
    for (i, bit) in [(4992usize, 7u32), (4996, 7), (5000, 7), (5008, 7), (5016, 7)] {
        let mut p = payload.to_vec();
        p[i] ^= 1 << bit;
        let mut d = build(&NORMAL, &[], true);
        let ok = d.restore_trusted(&envelope(&p)).is_ok();
        let floor = d.samples()[0].pose;
        let mut h = Vec::new();
        for _ in 0..300 {
            d.step(DT).unwrap();
            h.push(d.samples());
        }
        let df = diff_hist(&gh, &h);
        rep.info(&format!("DIAG_E9_cero_negativo_{i}"), format!("aceptado={ok} piso={floor:?} trayectoria_300: {}", df.text()));
    }
    rep.finish();
}
