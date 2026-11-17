//! Validación independiente (Claude), entrega 9: N4 (informativo), costo de restaurar.
//! Se compila igual en db4b6e0 y en aeee009 (worktree temporal) para comparar. Perfil dev opt 1:
//! no es medida de rendimiento. Imprime CLAUDE_COST\t<caso>\t<mediana_us>\t<p90_us>\t<media_us>\t<n>\t<bytes>.
mod claude_common;
mod claude_e9_common;
use claude_common::*;
use claude_e9_common::*;
use std::time::Instant;

fn stats(name: &str, mut v: Vec<f64>, bytes: usize) {
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let med = v[v.len() / 2];
    let p90 = v[(v.len() * 9) / 10];
    let mean = v.iter().sum::<f64>() / v.len() as f64;
    println!("CLAUDE_COST\t{name}\t{med:.2}\t{p90:.2}\t{mean:.2}\t{}\t{bytes}", v.len());
}

#[test]
fn n4_restore_cost() {
    let mut src = build(&NORMAL, &[], true);
    rule_k(&mut src).unwrap();
    for _ in 0..3 {
        src.step(DT).unwrap();
    }
    let snap = src.snapshot().unwrap();
    let mut d = build(&NORMAL, &[], true);
    for _ in 0..100 {
        d.restore_trusted(&snap).unwrap();
    }
    let v: Vec<f64> = (0..3000)
        .map(|_| {
            let t = Instant::now();
            d.restore_trusted(&snap).unwrap();
            t.elapsed().as_secs_f64() * 1e6
        })
        .collect();
    stats("F_restore_trusted", v, snap.len());

    let b = pile_bodies();
    let order: Vec<usize> = (0..b.len()).collect();
    let mut p = build_from(&b, &order, &[], true);
    for _ in 0..90 {
        p.step(DT).unwrap();
    }
    let big = p.snapshot().unwrap();
    let mut q = build_from(&b, &order, &[], true);
    for _ in 0..5 {
        q.restore_trusted(&big).unwrap();
    }
    let v: Vec<f64> = (0..40)
        .map(|_| {
            let t = Instant::now();
            q.restore_trusted(&big).unwrap();
            t.elapsed().as_secs_f64() * 1e6
        })
        .collect();
    stats("pila128_restore_trusted", v, big.len());
    let tick = q.cache_checkpoint().unwrap();
    let v: Vec<f64> = (0..40)
        .map(|_| {
            let t = Instant::now();
            q.restore_cached(tick).unwrap();
            t.elapsed().as_secs_f64() * 1e6
        })
        .collect();
    stats("pila128_restore_cached", v, big.len());
}
