#!/usr/bin/env node
// Verificador independiente (Claude) de una corrida de validation/run_case.ps1.
// Lee solo los archivos de la corrida. Criterios y tolerancias fijados antes de ejecutar en
// docs/net/validacion_objetos/criterios_entrega_1.md. Uso: node analyze.mjs <carpeta_de_corrida>
import fs from 'node:fs';
import path from 'node:path';

const dir = process.argv[2];
const readJsonl = (f) => {
  const p = path.join(dir, f);
  if (!fs.existsSync(p)) return [];
  return fs.readFileSync(p, 'utf8').split(/\r?\n/).filter(Boolean)
    .map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
};
const readText = (f) => { const p = path.join(dir, f); return fs.existsSync(p) ? fs.readFileSync(p, 'utf8') : ''; };
const run = JSON.parse(readText('run.json').replace(/^﻿/, ''));
const H = readJsonl('host.jsonl'), C = readJsonl('client.jsonl');
const HD = readJsonl('host.driver.jsonl'), CD = readJsonl('client.driver.jsonl');
const CASE = run.case, NET = run.net;
const SLOW = run.slow ?? 1;
const DT = SLOW / 60, G = 9.8, M = 2.0;
const TOL = { pos: 0.002, ang: 0.3 * Math.PI / 180, energy: 0.04, diag: 1e-4, contactTicks: 1, kinPos: 1e-5 };
const STRICT = NET === 'clean'; // C1, C2, C10 solo deciden sin degradación

// ---------------------------------------------------------------- geometría
const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const scale = (a, s) => [a[0] * s, a[1] * s, a[2] * s];
const len = (a) => Math.hypot(a[0], a[1], a[2]);
const lerp = (a, b, f) => [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f];
const qrot = (q, v) => {
  const [x, y, z, w] = q, [vx, vy, vz] = v;
  const tx = 2 * (y * vz - z * vy), ty = 2 * (z * vx - x * vz), tz = 2 * (x * vy - y * vx);
  return [vx + w * tx + (y * tz - z * ty), vy + w * ty + (z * tx - x * tz), vz + w * tz + (x * ty - y * tx)];
};
const qconj = (q) => [-q[0], -q[1], -q[2], q[3]];
const qmul = (a, b) => [
  a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
  a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
  a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
  a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2]];
// Estable numéricamente (no usa acos de un valor cercano a 1).
const qang = (a, b) => { const r = qmul(qconj(a), b); return 2 * Math.atan2(Math.hypot(r[0], r[1], r[2]), Math.abs(r[3])); };
const SX = 0.3, SY = 0.4, SZ = 0.2;
const cornersPhys = (p, q) => { const out = []; for (const x of [-SX, SX]) for (const y of [0, SY]) for (const z of [-SZ, SZ]) out.push(add(p, qrot(q, [x, y, z]))); return out; };
const cornersDraw = (m, q) => { const out = []; for (const x of [-SX, SX]) for (const y of [-0.2, 0.2]) for (const z of [-SZ, SZ]) out.push(add(m, qrot(q, [x, y, z]))); return out; };
const comPhys = (p, q) => add(p, qrot(q, [0, 0.2, 0]));
const lowOf = (cs) => Math.min(...cs.map((c) => c[1]));
const I_BODY = [M / 12 * (0.4 ** 2 + 0.4 ** 2), M / 12 * (0.6 ** 2 + 0.4 ** 2), M / 12 * (0.6 ** 2 + 0.4 ** 2)];
const energy = (r) => {
  const wb = qrot(qconj(r.q), r.av);
  const rot = 0.5 * (I_BODY[0] * wb[0] ** 2 + I_BODY[1] * wb[1] ** 2 + I_BODY[2] * wb[2] ** 2);
  return 0.5 * M * (r.lv[0] ** 2 + r.lv[1] ** 2 + r.lv[2] ** 2) + rot + M * G * comPhys(r.p, r.q)[1];
};
const WALL_FRONT = -2.99, WALL_BACK = -3.01;
const inWallSpan = (c) => c[0] >= -2 && c[0] <= 2 && c[1] >= 0 && c[1] <= 3;
const wallMetrics = (cs, com) => {
  let pen = 0, cross = false;
  for (const c of cs) if (inWallSpan(c)) { pen = Math.max(pen, WALL_FRONT - c[2]); if (c[2] < WALL_BACK) cross = true; }
  if (com[2] < WALL_FRONT && com[0] >= -2 && com[0] <= 2) cross = true;
  return { pen, cross };
};
const r6 = (x) => (x == null || !Number.isFinite(x) ? x : Math.round(x * 1e6) / 1e6);

// ---------------------------------------------------------------- series
const byKind = (arr, k) => arr.filter((r) => r.kind === k);
const physMap = (arr) => { const m = { 1: new Map(), 2: new Map() }; for (const r of byKind(arr, 'physics')) m[r.uid]?.set(r.tick, r); return m; };
const HP = physMap(H), CP = physMap(C);
const ppMap = (arr) => { const m = new Map(); for (const r of arr) if (r.k === 'pp' && r.ready) m.set(r.tick, r); return m; };
const HPP = ppMap(HD), CPP = ppMap(CD);
const objOf = (pp, uid) => pp?.objs?.find((o) => o.uid === uid);
const draws = CD.filter((r) => r.k === 'dr');
const ev = (arr, k) => arr.filter((r) => r.k === k);
const sortedTicks = (m) => [...m.keys()].sort((a, b) => a - b);
const hostAt = (uid, s) => { // pose interpolada del host en un instante fraccionario
  const a = HP[uid].get(Math.floor(s)), b = HP[uid].get(Math.ceil(s));
  if (!a || !b) return null;
  const f = s - Math.floor(s);
  const ca = comPhys(a.p, a.q), cb = comPhys(b.p, b.q);
  return { com: lerp(ca, cb, f), low: lowOf(cornersPhys(a.p, a.q)) * (1 - f) + lowOf(cornersPhys(b.p, b.q)) * f, q: f < 0.5 ? a.q : b.q, rec: f < 0.5 ? a : b };
};

const checks = [];
const info = {};
const check = (id, ok, metric, tol, note = '') => checks.push({ id, ok, metric, tol, note });

// ---------------------------------------------------------------- proceso y errores
info.process = { host_exit: run.host_exit, client_exit: run.client_exit, killed: run.killed, total_s: run.total_s,
  host_errors: run.host_errors, client_errors: run.client_errors, failures: run.failures,
  host_end: HD.find((r) => r.k === 'end'), client_end: CD.find((r) => r.k === 'end') };
const expectClientExit = CASE === 'fingerprint_mismatch' ? [2] : CASE === 'disconnect_holding' ? [0, 2] : [0];
check('E0_procesos', expectClientExit.includes(run.client_exit) && run.host_exit === 0 && (run.killed ?? []).length === 0
  && (run.host_errors ?? []).length === 0 && (CASE === 'fingerprint_mismatch' || (run.client_errors ?? []).length === 0),
  `host=${run.host_exit} client=${run.client_exit} killed=${(run.killed ?? []).length}`, 'código esperado, sin errores ni procesos matados');

// ---------------------------------------------------------------- red
{
  const rtts = byKind(C, 'physics').map((r) => r.rtt_ms).filter((x) => x > 0);
  const enetC = [], enetH = [], lossC = [];
  for (const r of CD) if (r.k === 'pp' && r.enet) for (const v of Object.values(r.enet)) { enetC.push(v.rtt); lossC.push(v.loss); }
  for (const r of HD) if (r.k === 'pp' && r.enet) for (const v of Object.values(r.enet)) enetH.push(v.rtt);
  const st = (a) => a.length ? { min: Math.min(...a), max: Math.max(...a), mean: r6(a.reduce((x, y) => x + y, 0) / a.length), n: a.length } : null;
  const rates = new Set([...CPP.values()].map((r) => r.rate));
  const clockReady = C.find((r) => r.kind === 'clock_ready');
  const recv = byKind(C, 'received').filter((r) => clockReady && r.usec > clockReady.usec);
  const firstRecv = recv[0]?.tick, lastRecv = recv.at(-1)?.tick;
  let expected = 0;
  if (firstRecv != null) for (const uid of [1, 2]) for (const t of sortedTicks(HP[uid])) if (t % 2 === 0 && t >= firstRecv && t <= lastRecv) expected++;
  const perFrame = new Map();
  for (const r of CPP.values()) perFrame.set(r.pf, (perFrame.get(r.pf) ?? 0) + 1);
  info.net = { app_rtt_ms: st(rtts), enet_rtt_client_ms: st(enetC), enet_rtt_host_ms: st(enetH), enet_loss_client: st(lossC),
    client_rates_hz: [...rates].sort((a, b) => a - b), snapshots_accepted: recv.length, snapshots_expected_window: expected,
    accepted_fraction: expected ? r6(recv.length / expected) : null,
    max_physics_steps_in_one_frame: Math.max(0, ...perFrame.values()),
    lead_ticks_at_receipt: st(recv.map((r) => r.local_tick - r.tick)) };
}

// ---------------------------------------------------------------- 3.3 correspondencia paso/captura
function mappingFor(label, P, slowValue) {
  const dt = slowValue / 60;
  const out = { pairs: 0, awake_pairs: 0, frame_mismatch: 0, callback_step_not_1: 0, dt_bad: 0, offsets: new Set(),
    kin_pairs: 0, kin_pos_bad: 0, kin_vel_bad: 0, max_pos_err: 0, max_vel_err_excess: 0, examples: [] };
  for (const uid of [1, 2]) {
    const ticks = sortedTicks(P[uid]);
    for (let i = 1; i < ticks.length; i++) {
      const a = P[uid].get(ticks[i - 1]), b = P[uid].get(ticks[i]);
      if (b.tick !== a.tick + 1) continue;
      out.pairs++;
      out.offsets.add(b.engine_frame - b.tick);
      if (!a.sleep && !b.sleep) {
        out.awake_pairs++;
        if (b.native_frame !== b.engine_frame) { out.frame_mismatch++; if (out.examples.length < 3) out.examples.push({ uid, tick: b.tick, why: 'native_frame', b: b.native_frame, e: b.engine_frame }); }
        if (b.native_callbacks - a.native_callbacks !== 1) { out.callback_step_not_1++; if (out.examples.length < 3) out.examples.push({ uid, tick: b.tick, why: 'callbacks', d: b.native_callbacks - a.native_callbacks }); }
        if (Math.abs(b.native_dt - dt) / dt > 1e-6 || Math.abs(b.physics_delta - dt) / dt > 1e-6) out.dt_bad++;
      }
      const free = a.phase === 0 && b.phase === 0 && a.contacts === 0 && b.contacts === 0 && !a.sleep && !b.sleep
        && a.impulses === b.impulses && a.revision === b.revision;
      if (free && !(label === 'client' && corrTicks.has(b.tick))) {
        out.kin_pairs++;
        const dp = sub(b.p, a.p), pe = len(sub(dp, scale(b.lv, dt)));
        out.max_pos_err = Math.max(out.max_pos_err, pe);
        if (pe > TOL.kinPos) out.kin_pos_bad++;
        const v = len(b.lv), dvy = b.lv[1] - a.lv[1];
        const excess = Math.abs(dvy + G * dt) - (0.1 * dt * v + 1e-4);
        out.max_vel_err_excess = Math.max(out.max_vel_err_excess, excess);
        if (excess > 0) out.kin_vel_bad++;
      }
    }
  }
  out.offsets = [...out.offsets];
  out.max_pos_err = r6(out.max_pos_err); out.max_vel_err_excess = r6(out.max_vel_err_excess);
  return out;
}

// ---------------------------------------------------------------- correcciones del invitado
const corrections = [];
const corrTicks = new Set();
for (const [t, pp] of CPP) {
  const prev = CPP.get(t - 1);
  for (const uid of [1, 2]) {
    const o = objOf(pp, uid), po = objOf(prev, uid);
    if (!o || !po || !o.pred || !po.pred) continue;
    const ph = CP[uid].get(t - 1);
    if (!ph) continue;
    const v = sub(o.p, ph.p), d = len(v), a = qang(o.q, ph.q);
    if (d > 1e-7 || a > 1e-6) { corrections.push({ uid, tick: t, dist: r6(d), up: r6(v[1]), vec: v.map(r6), ang_deg: r6(a * 180 / Math.PI) }); corrTicks.add(t); }
  }
}

const mapH = mappingFor('host', HP, SLOW);
const mapC = mappingFor('client', CP, run.net === 'mismatch' ? 0.5 : SLOW);
info.mapping = { host: mapH, client: mapC };
for (const [role, m] of [['host', mapH], ['client', mapC]]) {
  if (m.pairs === 0) continue;
  check(`P1_${role}_callback_en_el_mismo_cuadro`, m.frame_mismatch === 0, `${m.frame_mismatch}/${m.awake_pairs}`, '0');
  check(`P2_${role}_un_callback_por_tick`, m.callback_step_not_1 === 0, `${m.callback_step_not_1}/${m.awake_pairs}`, '0');
  check(`P3_${role}_dt`, m.dt_bad === 0, `${m.dt_bad}/${m.awake_pairs}`, `slow/60 ±1e-6 rel`);
  check(`P4_${role}_un_paso_por_tick`, m.offsets.length <= 1, `engine_frame-tick=${JSON.stringify(m.offsets)}`, 'un solo valor');
  if (m.kin_pairs) check(`P5_${role}_cinematica_un_paso`, m.kin_pos_bad === 0 && m.kin_vel_bad === 0,
    `pares=${m.kin_pairs} pos_mal=${m.kin_pos_bad} (max ${m.max_pos_err} m) vel_mal=${m.kin_vel_bad} (exceso max ${m.max_vel_err_excess})`, '1e-5 m; g·dt ± amortiguación');
}

// ---------------------------------------------------------------- etiqueta de instante del dibujo predicho
{
  let m0 = 0, m1 = 0, n = 0;
  for (const d of draws) for (const o of d.objs) {
    if (!o.pred) continue;
    const a = CP[o.uid].get(o.pt), b = CP[o.uid].get(o.pt - 1);
    n++;
    if (a && len(sub(o.bp, a.p)) < 1e-7) m0++;
    if (b && len(sub(o.bp, b.p)) < 1e-7) m1++;
  }
  info.draw_label = { predicted_draws: n, matches_prepared_tick: m0, matches_prepared_tick_minus_1: m1 };
}
const drawOffset = (info.draw_label.matches_prepared_tick_minus_1 > info.draw_label.matches_prepared_tick) ? 1 : 0;
const drawInstant = (o) => (o.pred ? o.pt - drawOffset : o.st);

// ---------------------------------------------------------------- eventos de acción
const requests = byKind(C, 'request'), applied = byKind(H, 'applied'), results = byKind(C, 'result');
info.actions = requests.map((r) => {
  const a = applied.find((x) => x.action === r.action && x.uid === r.uid && x.op === r.op);
  const res = results.filter((x) => x.action === r.action);
  return { op: r.op, uid: r.uid, action: r.action, client_exec_tick: r.local_tick, requested_tick: r.requested_tick,
    host_applied_tick: a?.applied_tick ?? null, late: a?.late ?? null,
    host_minus_client_start: a ? a.applied_tick - r.local_tick : null,
    results: res.map((x) => `${x.status}${x.reason ? ':' + x.reason : ''}@${x.local_tick}`) };
});
info.reconcile = {};
for (const r of byKind(C, 'reconcile')) info.reconcile[r.status] = (info.reconcile[r.status] ?? 0) + 1;
info.handoffs = byKind(C, 'handoff').map((h) => ({ uid: h.uid, tick: h.local_tick, source_tick: h.source_tick, distance: r6(h.distance) }));
info.auto_release = byKind(H, 'auto_release');

// ---------------------------------------------------------------- correcciones durante agarre (C5 en todo el ciclo)
{
  const grabReq = requests.find((r) => r.op === 'grab');
  const relReq = requests.find((r) => r.op === 'release' || r.op === 'throw');
  const phase = (t) => (relReq && t > relReq.local_tick ? 'suelta' : 'agarre');
  const big = corrections.filter((c) => c.dist > TOL.pos || c.ang_deg * Math.PI / 180 > TOL.ang);
  info.corrections = { count: corrections.length, over_tol: big.length,
    by_phase: { agarre: big.filter((c) => phase(c.tick) === 'agarre').length, suelta: big.filter((c) => phase(c.tick) === 'suelta').length },
    largest: [...corrections].sort((a, b) => b.dist - a.dist).slice(0, 6).map((c) => ({ ...c, phase: phase(c.tick) })),
    max_up_m: r6(Math.max(0, ...corrections.map((c) => c.up))) };
  if (grabReq) check('C5_correcciones_<=2mm', big.length === 0,
    `${big.length} > 2 mm (agarre ${info.corrections.by_phase.agarre}, suelta ${info.corrections.by_phase.suelta}); max ${info.corrections.largest[0]?.dist ?? 0} m, subida max ${info.corrections.max_up_m} m`, '2 mm / 0,3°');
}

// ---------------------------------------------------------------- análisis de la suelta (caja 1)
function riseOf(series) { // series: [{t, y, low}] ordenada; usa low para el inicio
  if (series.length < 3) return null;
  const yFinal = series.at(-1).low;
  const i0 = series.findIndex((s) => s.low <= yFinal + 0.003);
  if (i0 < 0) return null;
  let minY = Infinity, minLow = Infinity, rCom = 0, rLow = 0, at = null;
  for (let i = i0; i < series.length; i++) {
    minY = Math.min(minY, series[i].y); minLow = Math.min(minLow, series[i].low);
    if (series[i].y - minY > rCom) rCom = series[i].y - minY;
    if (series[i].low - minLow > rLow) { rLow = series[i].low - minLow; at = series[i].t; }
  }
  return { com: r6(rCom), low: r6(rLow), at, start: series[i0].t };
}
const rel = requests.find((r) => r.uid === 1 && (r.op === 'release' || r.op === 'throw'));
// ready_gate termina 30 ticks después de soltar: no mide caída ni traspaso.
if (rel && CASE !== 'ready_gate') {
  // Cada jugador numera sus acciones: emparejar también por caja y operación
  // (en `wall` el host suelta la caja 2 con el mismo número que el invitado la 1).
  const app = applied.find((a) => a.action === rel.action && a.uid === rel.uid && a.op === rel.op);
  const Tl = rel.local_tick, Th = app?.applied_tick ?? null;
  const hand = byKind(C, 'handoff').find((h) => h.uid === 1 && h.local_tick >= Tl);
  const Tend = hand ? hand.local_tick : Infinity;
  const rr = { client_release_tick: Tl, host_applied_tick: Th, requested_tick: rel.requested_tick, late: app?.late ?? null,
    applied_delay_ticks: Th != null ? Th - (rel.requested_tick + 1) : null, handoff_tick: hand?.local_tick ?? null };
  // Divergencia del mismo tick.
  const hostContact = sortedTicks(HP[1]).find((t) => Th != null && t >= Th && HP[1].get(t).contacts > 0);
  const clientContact = sortedTicks(CP[1]).find((t) => t >= Tl && t < Tend && CP[1].get(t).contacts > 0);
  let preMax = 0, preAng = 0, allMax = 0, allAng = 0, lowMaxDiff = 0, n = 0, firstOverTick = null;
  for (const t of sortedTicks(CP[1])) {
    if (t < Tl || t >= Tend) continue;
    const c = CP[1].get(t), h = HP[1].get(t);
    if (!h) continue;
    n++;
    const d = len(sub(comPhys(c.p, c.q), comPhys(h.p, h.q))), a = qang(c.q, h.q);
    const dl = lowOf(cornersPhys(c.p, c.q)) - lowOf(cornersPhys(h.p, h.q));
    allMax = Math.max(allMax, d); allAng = Math.max(allAng, a); lowMaxDiff = Math.max(lowMaxDiff, Math.abs(dl));
    if (hostContact == null || t < hostContact) { preMax = Math.max(preMax, d); preAng = Math.max(preAng, a); }
    if (firstOverTick == null && (d > TOL.pos || a > TOL.ang)) firstOverTick = t;
  }
  Object.assign(rr, { same_tick_pairs: n, host_first_contact: hostContact ?? null, client_first_contact: clientContact ?? null,
    pre_contact_max_m: r6(preMax), pre_contact_max_deg: r6(preAng * 180 / Math.PI), all_max_m: r6(allMax), all_max_deg: r6(allAng * 180 / Math.PI),
    low_point_max_diff_m: r6(lowMaxDiff), first_over_tol_tick: firstOverTick });
  check('C1_divergencia_antes_del_contacto', STRICT ? (n > 0 && preMax <= TOL.pos && preAng <= TOL.ang) : null,
    `${r6(preMax)} m / ${r6(preAng * 180 / Math.PI)}° (${n} ticks)`, '2 mm / 0,3°', STRICT ? '' : 'informativo con degradación');
  check('C2_primer_contacto', STRICT ? (hostContact != null && clientContact != null && Math.abs(hostContact - clientContact) <= 1) : null,
    `host ${hostContact} / invitado ${clientContact}`, '±1 tick', STRICT ? '' : 'informativo con degradación');
  check('C10_suelta_a_tiempo', STRICT ? (Th === rel.requested_tick + 1 && app?.late === false) : null,
    `pedida ${rel.requested_tick}, aplicada ${Th}, late=${app?.late}`, 'requested+1', STRICT ? '' : 'informativo con degradación');
  // Elevación posterior.
  const hostSeries = sortedTicks(HP[1]).filter((t) => Th != null && t >= Th).map((t) => { const r = HP[1].get(t); return { t, y: comPhys(r.p, r.q)[1], low: lowOf(cornersPhys(r.p, r.q)) }; });
  const clientSeries = sortedTicks(CP[1]).filter((t) => t >= Tl && t < Tend).map((t) => { const r = CP[1].get(t); return { t, y: comPhys(r.p, r.q)[1], low: lowOf(cornersPhys(r.p, r.q)) }; });
  const relDraws = draws.filter((d) => d.tick >= Tl).map((d) => ({ d, o: d.objs.find((o) => o.uid === 1) })).filter((x) => x.o);
  const drawSeries = relDraws.map(({ d, o }) => ({ t: d.usec, s: drawInstant(o), pred: o.pred, y: o.m[1], low: lowOf(cornersDraw(o.m, o.mq)), o, d }));
  const Rh = riseOf(hostSeries), Rc = riseOf(clientSeries), Rd = riseOf(drawSeries);
  rr.rise = { host: Rh, client_phys: Rc, client_draw: Rd };
  const extra = (R) => (R && Rh ? Math.max(R.com - Rh.com, R.low - Rh.low) : null);
  check('C3_elevacion_posterior', Rh != null && Rd != null && extra(Rd) <= TOL.pos && (Rc == null || extra(Rc) <= TOL.pos),
    `host com/low ${Rh?.com}/${Rh?.low}; invitado física ${Rc?.com}/${Rc?.low}; dibujo ${Rd?.com}/${Rd?.low}`, 'invitado − host ≤ 2 mm');
  // Ascenso artificial A1 y saltos del dibujo.
  let a1 = 0, a1max = 0, a1at = null, back = 0, backMax = 0;
  const contrib = [];
  for (let i = 1; i < drawSeries.length; i++) {
    const p = drawSeries[i - 1], c = drawSeries[i];
    const dyDraw = c.low - p.low;
    let dyHost = 0;
    if (c.s > p.s) { const hp = hostAt(1, p.s), hc = hostAt(1, c.s); if (hp && hc) dyHost = hc.low - hp.low; }
    else if (c.s < p.s) { back++; backMax = Math.max(backMax, p.s - c.s); }
    const art = Math.max(0, dyDraw - Math.max(0, dyHost));
    if (art > 1e-6) contrib.push({ tick: c.d.tick, s: r6(c.s), art: r6(art), pred: c.pred });
    a1 += art;
    if (art > a1max) { a1max = art; a1at = { tick: c.d.tick, s: c.s, pred: c.pred, prev_pred: p.pred }; }
  }
  // Diagnóstico agregado DESPUÉS de ver drop020_degraded (no decide): A1 contra el host
  // corrido por el atraso aplicado k. Separa "mismo movimiento físico k ticks antes" de
  // "movimiento que el host no tiene en ningún momento".
  const k = Th != null ? Th - (rel.requested_tick + 1) : 0;
  let a1s = 0;
  for (let i = 1; i < drawSeries.length; i++) {
    const p = drawSeries[i - 1], c = drawSeries[i];
    let dyHost = 0;
    if (c.s > p.s) { const hp = hostAt(1, p.s + k), hc = hostAt(1, c.s + k); if (hp && hc) dyHost = hc.low - hp.low; }
    a1s += Math.max(0, (c.low - p.low) - Math.max(0, dyHost));
  }
  rr.a1 = { sum_m: r6(a1), max_step_m: r6(a1max), at: a1at, instant_regressions: back, max_regression_ticks: r6(backMax),
    top: contrib.sort((x, y) => y.art - x.art).slice(0, 5), diag_sum_vs_host_shifted_by_applied_delay_m: r6(a1s), applied_delay_ticks: k };
  check('C4_ascenso_artificial', a1 <= TOL.pos, `Σ ${r6(a1)} m, paso max ${r6(a1max)} m; diagnóstico con host corrido ${k} tick(s): Σ ${r6(a1s)} m`, '2 mm');
  // Penetración máxima en el piso después de soltar (física de cada lado).
  const minLow = (S) => (S.length ? r6(Math.min(...S.map((x) => x.low))) : null);
  rr.floor_min_low_point_m = { host: minLow(hostSeries), client_phys: minLow(clientSeries), client_draw: minLow(drawSeries) };
  // Traspaso.
  let hj = null;
  const i1 = drawSeries.findIndex((x, i) => i > 0 && drawSeries[i - 1].pred && !x.pred);
  if (i1 > 0) {
    const a = drawSeries[i1 - 1], b = drawSeries[i1];
    hj = { dist: r6(len(sub(b.o.m, a.o.m))), ang_deg: r6(qang(a.o.mq, b.o.mq) * 180 / Math.PI), instant_before: a.s, instant_after: r6(b.s), tick: b.d.tick };
  }
  rr.handoff_visual = hj;
  check('C6_traspaso', hand != null && hj != null && hj.dist <= TOL.pos && hj.ang_deg * Math.PI / 180 <= TOL.ang && hj.instant_after >= hj.instant_before - 1e-9,
    hj ? `salto ${hj.dist} m / ${hj.ang_deg}°, instante ${hj.instant_before}→${hj.instant_after}` : 'sin traspaso', '2 mm / 0,3°, sin retroceso');
  // Impulsos.
  const impBefore = (P, t) => { const k = sortedTicks(P[1]).filter((x) => x < t); return k.length ? P[1].get(k.at(-1)).impulses : 0; };
  const impAfter = (P) => { const k = sortedTicks(P[1]); return k.length ? P[1].get(k.at(-1)).impulses : 0; };
  const want = rel.op === 'throw' ? 1 : 0;
  const dh = Th != null ? impAfter(HP) - impBefore(HP, Th) : null, dc = impAfter(CP) - impBefore(CP, Tl);
  rr.impulses = { host: dh, client: dc, expected: want };
  check('C7_impulsos', dh === want && dc === want, `host +${dh}, invitado +${dc}`, `+${want}`);
  // Dirección del impulso.
  if (rel.op === 'throw') {
    const dirOf = (P, t) => { const a = P[1].get(t - 1), b = P[1].get(t); if (!a || !b) return null; const dv = sub(b.lv, a.lv); dv[1] += G * DT; return scale(dv, 1 / len(dv)); };
    const reqDir = CD.find((r) => r.k === 'drv_throw')?.dir;
    const want = reqDir ? scale(reqDir, 1 / len(reqDir)) : null;
    const ang = (u) => (u && want ? r6(Math.acos(Math.max(-1, Math.min(1, u[0] * want[0] + u[1] * want[1] + u[2] * want[2]))) * 180 / Math.PI) : null);
    const hd = Th != null ? dirOf(HP, Th) : null, cdv = dirOf(CP, Tl);
    rr.throw_direction = { requested: want?.map(r6), host: hd?.map(r6), client: cdv?.map(r6), host_err_deg: ang(hd), client_err_deg: ang(cdv),
      result_initial_lv: app?.initial?.lv?.map(r6), host_lv_after_step: HP[1].get(Th)?.lv?.map(r6) };
    check('K2_direccion_del_lanzamiento', ang(hd) != null && ang(hd) < 1 && ang(cdv) != null && ang(cdv) < 1,
      `host ${ang(hd)}°, invitado ${ang(cdv)}°`, '< 1°');
  }
  // Revisiones.
  let regress = 0;
  for (const uid of [1, 2]) {
    let maxS = 0, maxV = 0;
    for (const t of sortedTicks(CPP)) { const o = objOf(CPP.get(t), uid); if (!o) continue; if (o.srev < maxS || o.vrev < maxV) regress++; maxS = Math.max(maxS, o.srev); maxV = Math.max(maxV, o.vrev); }
    let maxR = 0; for (const r of byKind(C, 'received').filter((x) => x.uid === uid)) { if (r.revision < maxR) regress++; maxR = Math.max(maxR, r.revision); }
  }
  check('C8_revisiones', regress === 0, `${regress} retrocesos`, '0');
  // Pose final.
  // Mismo instante: el host sigue registrando después de que el invitado termina
  // (en `moving` la caja seguía empujada; comparar contra su último registro mide tiempo, no error).
  const lastDraw = drawSeries.at(-1);
  const lastHost = lastDraw ? hostAt(1, Math.min(lastDraw.s, sortedTicks(HP[1]).at(-1)))?.rec : null;
  if (lastDraw && lastHost) {
    const fd = len(sub(lastDraw.o.m, comPhys(lastHost.p, lastHost.q))), fa = qang(lastDraw.o.mq, lastHost.q);
    rr.final = { dist: r6(fd), ang_deg: r6(fa * 180 / Math.PI) };
    check('C9_pose_final', fd <= TOL.pos && fa <= TOL.ang, `${r6(fd)} m / ${r6(fa * 180 / Math.PI)}°`, '2 mm / 0,3°');
  }
  // Energía.
  const riseE = (P, t0, t1) => { let mn = Infinity, r = 0; for (const t of sortedTicks(P[1])) { if (t <= t0 || t >= t1) continue; const e = energy(P[1].get(t)); mn = Math.min(mn, e); r = Math.max(r, e - mn); } return r; };
  const eh = Th != null ? riseE(HP, Th, Infinity) : null, ec = riseE(CP, Tl, Tend);
  rr.energy_rise = { host_J: r6(eh), client_J: r6(ec) };
  check('C11_energia', eh != null && ec - eh <= TOL.energy, `invitado ${r6(ec)} J, host ${r6(eh)} J`, 'invitado − host ≤ 0,04 J');
  info.release = rr;
}

// ---------------------------------------------------------------- dibujo remoto (réplicas)
{
  const res = {};
  for (const uid of [1, 2]) {
    let n = 0, maxErr = 0, starved = 0, frozenRun = 0, frozenMax = 0, lastSt = null, worst = null;
    for (const d of draws) {
      const o = d.objs.find((x) => x.uid === uid);
      if (!o || o.pred || d.est == null || o.st < 0) continue;
      const h = hostAt(uid, o.st);
      if (!h) continue;
      n++;
      const e = len(sub(o.m, h.com));
      if (e > maxErr) { maxErr = e; worst = { tick: d.tick, st: r6(o.st), est: r6(d.est) }; }
      if (d.est - 6 > o.vlast + 1e-6) starved++;
      if (lastSt != null && o.st === lastSt && d.est - 6 > o.st + 1) { frozenRun++; frozenMax = Math.max(frozenMax, d.est - 6 - o.st); } else frozenRun = 0;
      lastSt = o.st;
    }
    res[uid] = { draws: n, max_err_vs_host_at_shown_instant_m: r6(maxErr), worst, starved_fraction: n ? r6(starved / n) : null, max_behind_buffer_ticks: r6(frozenMax) };
  }
  info.remote_draw = res;
}

// ---------------------------------------------------------------- proxies
{
  const res = {};
  for (const uid of [1, 2]) {
    let n = 0, maxErr = 0, lags = [];
    for (const [t, pp] of CPP) {
      const o = objOf(pp, uid);
      if (!o || o.pred || !o.frz || o.lay === 0 || pp.est == null) continue;
      const h = HP[uid].get(t);
      if (!h) continue;
      n++;
      maxErr = Math.max(maxErr, len(sub(comPhys(o.p, o.q), comPhys(h.p, h.q))));
      lags.push(t - (pp.est - 6));
    }
    if (n) res[uid] = { active_ticks: n, max_err_vs_host_same_tick_m: r6(maxErr), mean_lag_ticks: r6(lags.reduce((a, b) => a + b, 0) / lags.length) };
  }
  info.proxies = res;
}

// ---------------------------------------------------------------- casos específicos
if (CASE === 'ready_gate') {
  const wr = C.find((r) => r.kind === 'world_ready'), cr = C.find((r) => r.kind === 'clock_ready');
  const req = requests[0];
  const physBefore = byKind(C, 'physics').filter((r) => cr && r.usec < cr.usec).length;
  const hammer = ev(CD, 'hammer').length;
  check('R1_orden_world_clock', wr && cr && wr.usec <= cr.usec, `world ${wr?.usec} clock ${cr?.usec}`, 'world_ready ≤ clock_ready');
  check('R2_sin_acciones_antes_de_listo', cr && (!req || req.usec > cr.usec) && physBefore === 0 && hammer > 0,
    `${hammer} intentos antes de listo; primer request ${req?.usec}; capturas previas ${physBefore}`, '0 acciones previas');
  check('R3_primera_accion_posterior', req && req.op === 'grab' && results.some((r) => r.action === req.action && r.status === 'accepted'),
    `${req?.op} ${req?.action}`, 'agarre aceptado');
}
if (CASE === 'fingerprint_mismatch') {
  const err = readText('client.stderr.log') + readText('client.stdout.log');
  check('R4_huella_incompatible', run.client_exit === 2 && /Prototipos incompatibles/.test(err) && !C.some((r) => ['world_ready', 'clock_ready', 'request'].includes(r.kind)) && applied.length === 0,
    `exit ${run.client_exit}; mensaje ${/Prototipos incompatibles/.test(err)}; world/clock/request ${C.filter((r) => ['world_ready', 'clock_ready', 'request'].includes(r.kind)).length}; applied host ${applied.length}`, 'código 2, sin estado');
}
if (CASE === 'dup_throw') {
  const thr = requests.find((r) => r.op === 'throw');
  const resThr = results.filter((r) => thr && r.action === thr.action);
  const appThr = applied.filter((a) => thr && a.action === thr.action);
  const k = sortedTicks(HP[1]);
  const totalImp = k.length ? HP[1].get(k.at(-1)).impulses : null;
  const flood = ev(CD, 'drv_flood')[0];
  const lastDup = ev(CD, 'drv_dup').at(-1);
  const resAfterLast = resThr.filter((r) => lastDup && r.usec != null);
  check('D1_un_impulso_con_duplicados', totalImp === 1 && appThr.length === 1, `impulsos host ${totalImp}, applied ${appThr.length}`, '1');
  info.dup = { dups: ev(CD, 'drv_dup').map((d) => ({ tick: d.tick, action: d.action })), results_for_throw: resThr.map((r) => `${r.status}@${r.local_tick}`),
    flood: flood ? { tick: flood.tick, n: flood.n } : null, results_total: results.length };
  const lastDupTick = lastDup?.tick ?? Infinity;
  const late = resThr.filter((r) => r.local_tick > lastDupTick);
  check('D2_duplicado_tras_expulsion_no_ejecuta', totalImp === 1 && late.filter((r) => r.status === 'accepted').length === 0,
    `${late.length} resultados tras el último duplicado`, 'sin nueva aplicación', 'el adaptador no responde a stale');
}
if (CASE === 'stale_snapshot') {
  const inj = ev(HD, 'drv_inject_old');
  info.stale = inj.map((x) => ({ host_tick: x.tick, old_rev: x.old_rev, old_tick: x.old_tick, current_rev: x.current_rev }));
  check('S1_snapshot_viejo_inyectado', inj.length === 3 && inj.every((x) => x.old_rev < x.current_rev), `${inj.length} envíos`, '3 con revisión vieja');
}
if (CASE === 'disconnect_holding') {
  const ar = info.auto_release.filter((r) => r.uid === 1);
  const disc = ev(CD, 'drv_disconnect')[0];
  const left = ev(HD, 'peer_disconnected')[0];
  const after = [...HPP.values()].filter((r) => left && r.tick > left.tick).map((r) => objOf(r, 1));
  const k = sortedTicks(HP[1]);
  const lastH = k.length ? HP[1].get(k.at(-1)) : null;
  const goalsChanged = after.some((o, i) => i > 0 && o.lg !== after[i - 1].lg);
  const revs = new Set(after.map((o) => o.arev));
  check('X1_liberacion_por_desconexion', ar.length === 1 && after.length > 0 && after.at(-1).aown === 0 && after.at(-1).aph === 0 && revs.size === 1
    && lastH && lastH.impulses === 0 && !goalsChanged && lowOf(cornersPhys(lastH.p, lastH.q)) < 0.003,
    `auto_release ${ar.length} en ${ar[0]?.local_tick} (desconexión del peer en ${left?.tick}); dueño ${after.at(-1)?.aown}; impulsos ${lastH?.impulses}; altura final ${r6(lastH ? lowOf(cornersPhys(lastH.p, lastH.q)) : null)} m; objetivos cambian ${goalsChanged}`,
    'una liberación, sin impulso, cae al piso');
  info.disconnect = { client_disconnect_tick: disc?.tick, host_peer_disconnected_tick: left?.tick, auto_release: ar };
}
if (CASE === 'grab_rejected') {
  const g = requests.find((r) => r.op === 'grab' && r.uid === 2);
  const res = g ? results.find((r) => r.action === g.action) : null;
  const physAfter = res ? byKind(C, 'physics').filter((r) => r.uid === 2 && r.local_tick > res.local_tick).length : null;
  const drawsAfter = res ? draws.filter((d) => d.tick > res.local_tick + 10).map((d) => ({ d, o: d.objs.find((o) => o.uid === 2) })) : [];
  let maxErr = 0, maxBehind = 0;
  for (const { d, o } of drawsAfter) {
    if (!o || o.pred || d.est == null) continue;
    const h = hostAt(2, Math.min(d.est - 6, sortedTicks(HP[2]).at(-1)));
    if (h) maxErr = Math.max(maxErr, len(sub(o.m, h.com)));
    maxBehind = Math.max(maxBehind, d.est - 6 - o.st);
  }
  info.rejected = { request: g, result: res, predicted_physics_after: physAfter, max_err_vs_host_at_buffer_instant_m: r6(maxErr), max_shown_behind_buffer_ticks: r6(maxBehind),
    client_state_rev_uid2_last: objOf(CPP.get(sortedTicks(CPP).at(-1)), 2)?.srev, host_rev_uid2_last: objOf(HPP.get(sortedTicks(HPP).at(-1)), 2)?.arev };
  check('G1_rechazo_sin_predictor', res && res.status === 'rejected' && physAfter === 0, `${res?.status}:${res?.reason}; capturas predichas posteriores ${physAfter}`, 'rechazo, 0 capturas');
  check('G2_replica_sigue_al_host', maxErr <= TOL.pos && maxBehind <= 2, `error max ${r6(maxErr)} m; atraso max sobre el buffer ${r6(maxBehind)} ticks`, '2 mm; ≤ 2 ticks detrás del buffer');
}
if (CASE === 'release_before_ack' || CASE === 'throw_before_ack') {
  const call = ev(CD, CASE === 'release_before_ack' ? 'drv_release' : 'drv_throw')[0];
  const exec = requests.find((r) => r.op === (CASE === 'release_before_ack' ? 'release' : 'throw'));
  const grab = requests.find((r) => r.op === 'grab');
  const usecAt = (t) => [...CPP.values()].find((r) => r.tick === t)?.usec;
  const waitTicks = call && exec ? exec.local_tick - call.tick : null;
  const waitMs = call && exec && usecAt(exec.local_tick) != null ? r6((usecAt(exec.local_tick) - call.usec) / 1000) : null;
  info.before_ack = { call_tick: call?.tick, dependent_at_call: call?.dependent, grab_exec_tick: grab?.local_tick, local_exec_tick: exec?.local_tick, wait_ticks: waitTicks, wait_ms: waitMs, action_ids: { grab: grab?.action, executed: exec?.action, recorded_by_driver: call?.action } };
  check('K1_respuesta_inmediata', waitTicks != null && waitTicks <= 1, `${waitTicks} ticks / ${waitMs} ms`, '≤ 1 tick', 'límite declarado 6 del README: pendiente');
  const owners = new Set([...HPP.values()].map((r) => objOf(r, 1)?.aown).filter((x) => x));
  check('K3_un_duenio', owners.size <= 1, `${owners.size} dueños distintos`, '≤ 1');
}
if (CASE === 'wall' || CASE === 'throw_wall') {
  const res = {};
  const scan = (label, items) => { let pen = 0, cross = false, floor = 0; for (const it of items) { const w = wallMetrics(it.cs, it.com); pen = Math.max(pen, w.pen); cross ||= w.cross; floor = Math.max(floor, -lowOf(it.cs)); } res[label] = { wall_pen_m: r6(pen), cross, floor_pen_m: r6(floor), n: items.length }; };
  for (const uid of [1, 2]) {
    scan(`host_phys_${uid}`, sortedTicks(HP[uid]).map((t) => { const r = HP[uid].get(t); return { cs: cornersPhys(r.p, r.q), com: comPhys(r.p, r.q) }; }));
    scan(`client_phys_${uid}`, sortedTicks(CP[uid]).map((t) => { const r = CP[uid].get(t); return { cs: cornersPhys(r.p, r.q), com: comPhys(r.p, r.q) }; }));
    scan(`client_draw_${uid}`, draws.map((d) => d.objs.find((o) => o.uid === uid)).filter((o) => o && (o.pred || o.st >= 0)).map((o) => ({ cs: cornersDraw(o.m, o.mq), com: o.m })));
  }
  info.wall = res;
  const anyCross = Object.values(res).some((r) => r.cross);
  check('W1_sin_cruce', !anyCross, Object.entries(res).filter(([, r]) => r.cross).map(([k]) => k).join(',') || 'ninguno', 'sin cruce');
  for (const k of Object.keys(res)) if (res[k].n) check(`W2_penetracion_${k}`, res[k].wall_pen_m <= TOL.pos && res[k].floor_pen_m <= TOL.pos,
    `pared ${res[k].wall_pen_m} m, piso ${res[k].floor_pen_m} m`, '2 mm');
}

// ---------------------------------------------------------------- salida
const out = { case: CASE, net: NET, slow: SLOW, run_dir: dir, checks, info };
fs.writeFileSync(path.join(dir, 'analysis.json'), JSON.stringify(out, null, 1));
const fmt = (c) => `${c.ok === true ? 'PASS' : c.ok === false ? 'FAIL' : 'INFO'} ${c.id}: ${c.metric}  [tol ${c.tol}]${c.note ? '  (' + c.note + ')' : ''}`;
console.log(`== ${CASE} / ${NET}${SLOW !== 1 ? ' / slow ' + SLOW : ''}`);
for (const c of checks) console.log('  ' + fmt(c));
const brief = { net: info.net, actions: info.actions, reconcile: info.reconcile, handoffs: info.handoffs, draw_label: info.draw_label,
  corrections: info.corrections && { count: info.corrections.count, over_tol: info.corrections.over_tol, by_phase: info.corrections.by_phase, top: info.corrections.largest?.slice(0, 3) },
  release: info.release && { ...info.release, rise: info.release.rise, a1: info.release.a1 && { ...info.release.a1, top: undefined } },
  remote_draw: info.remote_draw, proxies: info.proxies };
console.log(JSON.stringify(brief, null, 1).split('\n').map((l) => '  ' + l).join('\n'));
