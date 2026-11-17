//! Validación independiente (Claude), entrega 9: N2, bits 4 a 7 de cada byte del payload.
mod claude_common;
mod claude_e9_sweep;

#[test]
fn n2_all_bits_high() {
    claude_e9_sweep::sweep("N2_bits_4_7", 4..8);
}
