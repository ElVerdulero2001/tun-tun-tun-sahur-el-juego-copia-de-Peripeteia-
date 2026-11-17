//! Validación independiente (Claude), entrega 9: N1 S3, falsos rechazos con 128 cuerpos apilados.
//! Criterios: docs/net/validacion_objetos/criterios_entrega_9.md §5 N1.
mod claude_common;
mod claude_e9_common;
use claude_common::*;
use claude_e9_common::*;

#[test]
fn n1_s3_pile() {
    let mut rep = Report::new("n1_s3_pile");
    let b = pile_bodies();
    let normal: Vec<usize> = (0..b.len()).collect();
    let reverse: Vec<usize> = (0..b.len()).rev().collect();
    false_reject_scenario(&mut rep, "S3_pila_128", &|| build_from(&b, &normal, &[], true), &|| build_from(&b, &reverse, &[], true), &|_, _| {}, 120, 4, true);
    rep.finish();
}
