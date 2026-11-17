//! Validación independiente (Claude), entrega 9: N2, bits 0 a 3 de cada byte del payload.
mod claude_common;
mod claude_e9_sweep;

#[test]
fn n2_all_bits_low() {
    claude_e9_sweep::sweep("N2_bits_0_3", 0..4);
}
