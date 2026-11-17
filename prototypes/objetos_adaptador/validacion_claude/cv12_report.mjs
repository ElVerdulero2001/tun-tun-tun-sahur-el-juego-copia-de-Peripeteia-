// Validación independiente (Claude), entrega 12: resumen de una corrida de run_adapter_claude_e12.ps1.
// Copia de cv10_report.mjs; solo cambia la cantidad de scripts cargados esperada (13).
// Uso: node cv10_report.mjs <carpeta adapter_...> <raíz del repositorio>
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const [dir, repo] = process.argv.slice(2);
const read = (f) => { try { return JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8').replace(/^﻿/, '')); } catch { return null; } };
const sha = (f) => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const runner = read('runner.json');
const checks = [];
const add = (mode, id, verdict, metric, tol) => checks.push({ mode, id, verdict, metric: typeof metric === 'string' ? metric : JSON.stringify(metric), tol });
const KNOWN = /^ERROR: Failed to read the root certificate store\.$/;
for (const r of runner.records) {
  const script = r.error_lines.filter((l) => /^SCRIPT ERROR/.test(l));
  const other = r.error_lines.filter((l) => !/^SCRIPT ERROR/.test(l) && !KNOWN.test(l));
  const isImport = r.name === 'import';
  const ok = !r.timed_out && r.ms <= 8500 && script.length === 0 && (isImport ? r.exit_code === 0 : r.result && r.exit_code === 0);
  add('proceso', `G0_${r.name}`, ok ? 'PASS' : 'FAIL', `exit ${r.exit_code}, ${r.ms} ms${r.timed_out ? ' VENCIDO' : ''}, script_errors=${script.length}, otras=${JSON.stringify(other.slice(0, 4))}`, 'código 0, sin vencer, sin SCRIPT ERROR');
}
add('proceso', 'G0_godot_abiertos', runner.godot_left === 0 ? 'PASS' : 'FAIL', runner.godot_left, '0');
// A0a: copias.
const bad = runner.copies.filter((c) => !c.equal);
const key = runner.copies.filter((c) => /scripts\\(actor\\(actor_input|actor_body|actor_motor|actor_tuning|base_registry)|net\\sim_clock|inventory\\(inv_authority|inv_hold_motion))\.gd$|actor\.tscn$|clock_adapter\.gd$/.test(c.path));
add('copias', 'A0a_copias_iguales', bad.length === 0 && key.length === 10 ? 'PASS' : 'FAIL', `copias=${runner.copies.length} distintas=${bad.length} clave=${key.length} ${JSON.stringify(bad.slice(0, 3))}`, 'todas iguales al repositorio');
// A0b y checks por modo.
for (const m of runner.modes) {
  const r = read(`${m}.result.json`);
  if (!r) { add(m, 'resultado', 'FAIL', 'sin archivo', 'escrito'); continue; }
  for (const c of r.checks) add(m, c.id, c.verdict, c.metric, c.tol);
  const ls = r.facts?.loaded_scripts ?? {};
  const diffs = [];
  for (const [name, v] of Object.entries(ls)) {
    const rel = (v.path ?? '').replace('res://', '');
    const local = rel.startsWith('prototypes/objetos_adaptador/') || rel.startsWith('scripts/') || rel.startsWith('scenes/') ? path.join(repo, rel) : null;
    if (!local || !fs.existsSync(local) || sha(local) !== v.sha256) diffs.push([name, v.path]);
  }
  add(m, 'A0b_scripts_cargados', diffs.length === 0 && Object.keys(ls).length === 13 ? 'PASS' : 'FAIL', `clases=${Object.keys(ls).length} distintas=${JSON.stringify(diffs)}`, 'SHA del repositorio');
}
const summary = Object.fromEntries(['PASS', 'FAIL', 'INFO', 'NOEVAL'].map((v) => [v, checks.filter((c) => c.verdict === v).length]));
fs.writeFileSync(path.join(dir, 'report.json'), JSON.stringify({ dir, checks, summary }, null, 1));
for (const c of checks) console.log(`${c.verdict.padEnd(6)} [${c.mode}] ${c.id}: ${c.metric.slice(0, 400)}  [${c.tol}]`);
console.log(JSON.stringify(summary));
