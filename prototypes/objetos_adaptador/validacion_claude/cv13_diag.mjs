// Validación independiente (Claude), entrega 13: diagnóstico agregado después de la primera corrida.
// Por modo: tramos de ticks en que el host repitió el input del cliente (NetSync.used_input_tick != tick)
// y tramos en que ENet estranguló el envío no confiable del cliente (PEER_PACKET_THROTTLE < 32).
// Uso: node cv13_diag.mjs <carpeta network13_...>
import fs from 'node:fs';
import path from 'node:path';

const [dir] = process.argv.slice(2);
const read = (f) => { try { return JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8').replace(/^﻿/, '')); } catch { return null; } };
const runs = (ticks) => { const out = []; for (const t of ticks.sort((a, b) => a - b)) { const r = out[out.length - 1]; if (r && r[1] === t - 1) r[1] = t; else out.push([t, t]); } return out; };
const runner = read('runner.json');
const rows = [];
for (const m of runner?.modes || []) {
  if (m === 'capacity') continue;
  const h = read(`${m}_host.result.json`), c = read(`${m}_client.result.json`);
  if (!h || !c) continue;
  const repeated = Object.entries(h.ticks).filter(([t, x]) => x.used !== +t).map(([t]) => +t);
  const enet = c.enet || {};
  const throttled = Object.entries(enet).filter(([, s]) => s[0] < 32).map(([t]) => +t);
  const minThrottle = Math.min(...Object.values(enet).map((s) => s[0]));
  const maxRtt = Math.max(...Object.values(enet).map((s) => s[2]));
  const maxLoss = Math.max(...Object.values(enet).map((s) => s[1]));
  const hostEnet = h.enet || {};
  const hostMin = Math.min(...Object.values(hostEnet).map((s) => s[0]));
  const row = { modo: m, publicados_host: h.publishes.length, repetidos: repeated.length, tramos_repetidos: runs(repeated),
    cliente_estrangulado: runs(throttled), cliente_min_throttle: minThrottle, cliente_max_rtt_ms: maxRtt, cliente_max_perdida: maxLoss, host_min_throttle: hostMin };
  rows.push(row);
  console.log(JSON.stringify(row));
}
fs.writeFileSync(path.join(dir, 'diag.json'), JSON.stringify(rows, null, 1));
