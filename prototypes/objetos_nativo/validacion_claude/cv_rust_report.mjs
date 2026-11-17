// Validación independiente (Claude), entrega 8: resumen de una corrida de run_claude_rust.ps1.
// Uso: node cv_rust_report.mjs <carpeta rust_...>
import fs from 'node:fs';
import path from 'node:path';

const dir = process.argv[2];
const read = (f) => fs.readFileSync(path.join(dir, f), 'utf8').replace(/^﻿/, '');
const runner = JSON.parse(read('runner.json'));
const expected = {
  claude_replay_run1: ['a_contact_sleep_wake_and_b_identity', 'b2_ray_distances', 'b3_epochs', 'f_controller_in_checkpoint'],
  claude_replay_run2: ['a_contact_sleep_wake_and_b_identity', 'b2_ray_distances', 'b3_epochs', 'f_controller_in_checkpoint'],
  claude_isolation: ['c_isolation_between_instances'],
  claude_rejections: ['d_api_rejections_are_atomic', 'd17_snapshot_rejections_keep_world_and_cache', 'e_cache_limits_expiry_and_discards'],
  claude_capacity: ['d06_d08_capacity_limits', 'e3_cache_byte_limit_with_128_bodies'],
  claude_mutations: ['d18_mutation_sweep'],
};
const out = { dir, processes: [], checks: [], summary: {} };
const sha = {};
for (const r of runner.runs) {
  const text = read(r.name + '.stdout.log');
  const lines = text.split(/\r?\n/);
  const done = lines.filter((l) => l.startsWith('CLAUDE_DONE\t')).map((l) => l.split('\t')[1]);
  const tests = Object.fromEntries(lines.map((l) => /^test (\S+) \.\.\. (ok|FAILED)/.exec(l) ?? /^test (\S+) \.\.\. .*?(ok|FAILED)$/.exec(l)).filter(Boolean).map((m) => [m[1], m[2]]));
  const missing = (expected[r.name] ?? []).filter((t) => !done.includes(t));
  out.processes.push({ name: r.name, exit: r.exit_code, ms: r.ms, timed_out: r.timed_out, done, tests, missing });
  for (const l of lines) {
    if (l.startsWith('CLAUDE_TRAJ_SHA\t')) sha[r.name] = l.split('\t')[1];
    if (!l.startsWith('CLAUDE_CHECK\t')) continue;
    const [, id, verdict, metric, tol] = l.split('\t');
    if (r.name === 'claude_replay_run2') continue; // la segunda corrida solo aporta A6
    out.checks.push({ process: r.name, id, verdict, metric, tol });
  }
}
const s1 = sha.claude_replay_run1, s2 = sha.claude_replay_run2;
out.checks.push({ process: 'dos_procesos', id: 'A6_sha_entre_procesos', verdict: s1 && s1 === s2 ? 'PASS' : 'FAIL', metric: `${s1} / ${s2}`, tol: 'igual en dos procesos' });
const procOk = out.processes.every((p) => !p.timed_out && p.ms <= 8000 && p.missing.length === 0);
out.checks.unshift({ process: 'runner', id: 'R0_procesos_completos', verdict: procOk ? 'PASS' : 'FAIL',
  metric: out.processes.map((p) => `${p.name}: exit ${p.exit} ${p.ms} ms${p.timed_out ? ' VENCIDO' : ''}${p.missing.length ? ' faltan ' + p.missing.join(',') : ''}`).join('; '), tol: 'sin vencer 8 s, todas las funciones terminadas' });
for (const v of ['PASS', 'FAIL', 'INFO', 'NOEVAL']) out.summary[v] = out.checks.filter((c) => c.verdict === v).length;
fs.writeFileSync(path.join(dir, 'report.json'), JSON.stringify(out, null, 1));
for (const c of out.checks) console.log(`${c.verdict.padEnd(6)} ${c.id}: ${c.metric}  [${c.tol}]`);
console.log(JSON.stringify(out.summary));
