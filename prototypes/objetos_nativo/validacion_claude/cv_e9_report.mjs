// Validación independiente (Claude), entrega 9: resumen de una corrida de run_claude_rust_e9.ps1.
// Uso: node cv_e9_report.mjs <carpeta e9_...>
import fs from 'node:fs';
import path from 'node:path';

const dir = process.argv[2];
const read = (f) => fs.readFileSync(path.join(dir, f), 'utf8').replace(/^﻿/, '');
const runner = JSON.parse(read('runner.json'));
const checks = [];
const lines = (name) => read(name + '.stdout.log').split(/\r?\n/).map((raw) => {
  const at = Math.max(raw.indexOf('CLAUDE_CHECK\t'), raw.indexOf('CLAUDE_COST\t'), raw.indexOf('CLAUDE_DONE\t'));
  return at >= 0 ? raw.slice(at) : raw;
});
const expected = {
  claude_e9_false_reject: ['n1_false_rejections'], claude_e9_pile: ['n1_s3_pile'],
  claude_e9_sweep_lo: ['N2_bits_0_3'], claude_e9_sweep_hi: ['N2_bits_4_7'],
};
const runs = runner.runs.filter((r) => !r.name.startsWith('compile'));
const stepRuns = runs.filter((r) => r.name.startsWith('claude_e9_step_after_'));
const lastStep = stepRuns.at(-1);
const procs = [];
for (const r of runs) {
  if (r.name.startsWith('claude_e9_step_after_') && r !== lastStep) { procs.push(`${r.name}: exit ${r.exit_code} ${r.ms} ms${r.timed_out ? ' VENCIDO (reanudado)' : ''}`); continue; }
  const ls = lines(r.name);
  const done = ls.filter((l) => l.startsWith('CLAUDE_DONE\t')).map((l) => l.split('\t')[1]);
  const miss = (expected[r.name] ?? []).filter((t) => !done.includes(t));
  procs.push(`${r.name}: exit ${r.exit_code} ${r.ms} ms${r.timed_out ? ' VENCIDO' : ''}${miss.length ? ' faltan ' + miss.join(',') : ''}`);
  if (r.name.startsWith('cost_')) continue;
  for (const l of ls) {
    if (!l.startsWith('CLAUDE_CHECK\t')) continue;
    const [, id, verdict, metric, tol] = l.split('\t');
    checks.push({ process: r.name, id, verdict, metric, tol });
  }
  if (miss.length) checks.push({ process: r.name, id: `R0_${r.name}`, verdict: 'FAIL', metric: 'faltan ' + miss.join(','), tol: 'todas las funciones terminadas' });
}
const finalOk = runs.filter((r) => !r.name.startsWith('claude_e9_step_after_') || r === lastStep).every((r) => !r.timed_out && r.ms <= 8500);
checks.unshift({ process: 'runner', id: 'R0_procesos', verdict: finalOk ? 'PASS' : 'FAIL', metric: procs.join('; '), tol: 'sin vencer 8 s (N3 reanudado se informa aparte)' });
checks.push({ process: 'runner', id: 'N3_reanudaciones', verdict: 'INFO', metric: `intentos=${stepRuns.length} indices_salteados=${JSON.stringify(runner.step_after_skipped)}`, tol: 'se registra' });
// Costo: mediana de las medianas por ronda.
const cost = {};
for (const r of runs.filter((x) => x.name.startsWith('cost_'))) {
  const which = r.name.startsWith('cost_actual') ? 'actual' : 'base';
  for (const l of lines(r.name)) {
    if (!l.startsWith('CLAUDE_COST\t')) continue;
    const [, name, med, p90, , n, bytes] = l.split('\t');
    ((cost[name] ??= { bytes: +bytes, n: +n, actual: [], base: [] })[which]).push({ med: +med, p90: +p90 });
  }
}
const mid = (a) => { const s = [...a].sort((x, y) => x - y); return s[Math.floor(s.length / 2)]; };
for (const [name, c] of Object.entries(cost)) {
  const a = mid(c.actual.map((x) => x.med)), b = mid(c.base.map((x) => x.med));
  checks.push({ process: 'costo', id: `N4_${name}`, verdict: 'INFO',
    metric: `bytes=${c.bytes} n=${c.n} mediana_us actual=${a} base=${b} relacion=${(a / b).toFixed(2)} rondas_actual=${JSON.stringify(c.actual.map((x) => x.med))} rondas_base=${JSON.stringify(c.base.map((x) => x.med))} p90_actual=${JSON.stringify(c.actual.map((x) => x.p90))}`,
    tol: 'perfil dev opt 1, no es medida de rendimiento' });
}
checks.push({ process: 'runner', id: 'N4_base', verdict: 'INFO', metric: `commit=${runner.baseline_commit} exe_sha256=${runner.baseline_exe_sha256} worktree_quitado=${runner.worktree_removed}`, tol: 'se registra' });
const summary = Object.fromEntries(['PASS', 'FAIL', 'INFO', 'NOEVAL'].map((v) => [v, checks.filter((c) => c.verdict === v).length]));
fs.writeFileSync(path.join(dir, 'report.json'), JSON.stringify({ dir, checks, summary }, null, 1));
for (const c of checks) console.log(`${c.verdict.padEnd(6)} ${c.id}: ${c.metric}  [${c.tol}]`);
console.log(JSON.stringify(summary));
