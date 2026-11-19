// Informe de una corrida de la pista de objetos (run_pista_objetos.ps1).
// Lee guest.csv y host.csv (PistaMedidor) y separa, por fase del guion del
// invitado, los saltos de la cámara, del personaje dibujado y de la caja.
//
// "Salto" de un cuadro: cuánto se apartó la posición de seguir con la misma
// velocidad del cuadro anterior (|Δp_i − Δp_{i−1}·dt_i/dt_{i−1}|), en cm. Un
// movimiento parejo da cerca de 0; arrancar o frenar caminando, unos mm por
// cuadro; un golpe de la caja contra el piso, unos cm (es física, no dibujo).
// "Retroceso": la caja dibujada va para atrás en horizontal más de 1 cm en un
// cuadro, contra el sentido en que venía. "Cambio de paso" del personaje: lo mismo
// para el personaje dibujado; arrancar o frenar caminando da hasta unos 3 cm, sin
// que sea un salto: los saltos del personaje son sus correcciones (cuántas y la
// más grande). La cámara se mide respecto del personaje (lo que agrega ella).
// La caja en mano se mide en el espacio de la vista (como se ve en pantalla):
// girar la cámara con la caja no cuenta como salto.
import fs from 'node:fs';
import path from 'node:path';

const dir = process.argv[2];
if (!dir) { console.error('uso: node pista_objetos_report.mjs <carpeta>'); process.exit(2); }
const PISTA = [53, 0, -6];
const BOX = [0.52, 0.45, 0.58];
const BLOCK = { x: [1.45 + PISTA[0], 3.55 + PISTA[0]], z: [-3.15 + PISTA[2], -2.35 + PISTA[2]], top: 0.5 };

function read(file) {
  if (!fs.existsSync(file)) return [];
  const [head, ...lines] = fs.readFileSync(file, 'utf8').trim().split(/\r?\n/);
  const keys = head.split(',');
  return lines.map((line) => {
    const v = line.split(',');
    const row = {};
    keys.forEach((k, i) => { row[k] = k === 'fase' ? v[i] : (v[i] === '' ? NaN : Number(v[i])); });
    return row;
  });
}
const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const len = (a) => Math.hypot(a[0], a[1], a[2]);
const scale = (a, s) => [a[0] * s, a[1] * s, a[2] * s];
const P = (r, k) => [r[k + '_x'], r[k + '_y'], r[k + '_z']];
// Un vector del mundo en el espacio de la cámara de ese cuadro (gira con la vista).
function toView(r, v) {
  const [x, y, z, w] = [-r.cam_qx, -r.cam_qy, -r.cam_qz, r.cam_qw];
  const t2 = [2 * (y * v[2] - z * v[1]), 2 * (z * v[0] - x * v[2]), 2 * (x * v[1] - y * v[0])];
  return [v[0] + w * t2[0] + (y * t2[2] - z * t2[1]), v[1] + w * t2[1] + (z * t2[0] - x * t2[2]), v[2] + w * t2[2] + (x * t2[1] - y * t2[0])];
}

function jumps(rows, get) {
  const out = new Array(rows.length).fill(0);
  for (let i = 2; i < rows.length; i++) {
    const a = get(rows[i - 2]), b = get(rows[i - 1]), c = get(rows[i]);
    if ([a, b, c].some((p) => p.some((x) => !Number.isFinite(x)))) continue;
    const dt1 = rows[i - 1].ms - rows[i - 2].ms, dt2 = rows[i].ms - rows[i - 1].ms;
    if (dt1 <= 0 || dt2 <= 0) continue;
    out[i] = len(sub(sub(c, b), scale(sub(b, a), dt2 / dt1)));
  }
  return out;
}

function angle(q1, q2) {
  const d = Math.abs(q1[0] * q2[0] + q1[1] * q2[1] + q1[2] * q2[2] + q1[3] * q2[3]);
  return 2 * Math.acos(Math.min(1, d)) * 180 / Math.PI;
}

function bottom(r) {
  // Altura del punto más bajo de la caja dibujada (giro por cuaternión).
  const [x, y, z, w] = [r.box_qx, r.box_qy, r.box_qz, r.box_qw];
  const col = [ // fila y de la matriz de giro: componentes y de los ejes de la caja
    2 * (x * y + w * z), 1 - 2 * (x * x + z * z), 2 * (y * z - w * x)];
  const reach = Math.abs(col[0]) * BOX[0] / 2 + Math.abs(col[1]) * BOX[1] / 2 + Math.abs(col[2]) * BOX[2] / 2;
  return r.box_y - reach;
}

function analyse(rows, label) {
  if (!rows.length) return null;
  const cam = jumps(rows, (r) => P(r, 'cam'));
  const act = jumps(rows, (r) => P(r, 'act'));
  const box = jumps(rows, (r) => P(r, 'box'));
  const rel = jumps(rows, (r) => toView(r, sub(P(r, 'box'), P(r, 'cam'))));
  const camAct = jumps(rows, (r) => sub(P(r, 'cam'), P(r, 'act')));
  const raw = jumps(rows, (r) => P(r, 'raw'));
  let lastDir = null;
  const phases = new Map();
  const get = (name) => {
    if (!phases.has(name)) phases.set(name, { frames: 0, ms0: Infinity, ms1: 0, cam: [], act: [], box: [], rel: [], turn: 0,
      drawnSim: 0, back: 0, backMax: 0, penBlock: 0, penFloor: 0, actCorr: 0, actLast: 0, boxCorr: 0, boxLast: 0, recov: 0,
      releases: [], grabs: [], heldFrames: 0, camAct: [], corrRaw: 0, corrCam: 0 });
    return phases.get(name);
  };
  let prevTurn = 0;
  for (let i = 1; i < rows.length; i++) {
    const r = rows[i], p = rows[i - 1];
    const ph = get(r.fase || 'sin_fase');
    ph.frames++; ph.ms0 = Math.min(ph.ms0, r.ms); ph.ms1 = Math.max(ph.ms1, r.ms);
    ph.cam.push(cam[i]); ph.act.push(act[i]); ph.box.push(box[i]); ph.camAct.push(camAct[i]);
    if (r.held) { ph.rel.push(rel[i]); ph.heldFrames++; }
    const turn = angle([p.box_qx, p.box_qy, p.box_qz, p.box_qw], [r.box_qx, r.box_qy, r.box_qz, r.box_qw]);
    if (i > 1) ph.turn = Math.max(ph.turn, Math.abs(turn - prevTurn));
    prevTurn = turn;
    if (Number.isFinite(r.sim_x)) ph.drawnSim = Math.max(ph.drawnSim, len(sub(P(r, 'box'), P(r, 'sim'))));
    // Retroceso: contra la última dirección en que se movía (aunque se haya
    // detenido un cuadro en el medio, como al pasar de la mano a la caja suelta).
    const d2 = [r.box_x - p.box_x, 0, r.box_z - p.box_z];
    if (!r.held && lastDir && len(d2) > 0.01 && lastDir[0] * d2[0] + lastDir[2] * d2[2] < 0) {
      ph.back++; ph.backMax = Math.max(ph.backMax, len(d2));
    }
    if (len(d2) > 0.005) lastDir = d2;
    const b = bottom(r);
    const over = r.box_x > BLOCK.x[0] && r.box_x < BLOCK.x[1] && r.box_z > BLOCK.z[0] && r.box_z < BLOCK.z[1];
    if (over && b < BLOCK.top && b > BLOCK.top - 0.12) ph.penBlock = Math.max(ph.penBlock, BLOCK.top - b);
    if (b < 0) ph.penFloor = Math.max(ph.penFloor, -b);
    if (r.act_corr > p.act_corr) {
      ph.actCorr += r.act_corr - p.act_corr; ph.actLast = Math.max(ph.actLast, r.act_last);
      // Lo que saltó el personaje simulado y lo que se movió de más la cámara en ese cuadro y los 3 siguientes.
      ph.corrRaw = Math.max(ph.corrRaw, raw[i]);
      for (let k = i; k <= Math.min(rows.length - 1, i + 3); k++) ph.corrCam = Math.max(ph.corrCam, cam[k]);
    }
    if (r.box_corr > p.box_corr) { ph.boxCorr += r.box_corr - p.box_corr; ph.boxLast = Math.max(ph.boxLast, r.box_last); }
    if (r.recov > p.recov) ph.recov += r.recov - p.recov;
    if (p.held && !r.held) {
      // La suelta en pantalla: el salto más grande de la caja en los 3 cuadros de cada lado.
      let worst = 0;
      for (let k = Math.max(2, i - 3); k <= Math.min(rows.length - 1, i + 3); k++) worst = Math.max(worst, box[k]);
      ph.releases.push(worst);
    }
    if (!p.held && r.held) {
      let worst = 0;
      for (let k = Math.max(2, i - 3); k <= Math.min(rows.length - 1, i + 3); k++) worst = Math.max(worst, rel[k]);
      ph.grabs.push(worst);
    }
  }
  const max = (a) => a.length ? Math.max(...a) : 0;
  const over = (a, t) => a.filter((x) => x > t).length;
  const cm = (m) => (m * 100).toFixed(1);
  console.log(`\n## ${label}: ${rows.length} cuadros, ${((rows.at(-1).ms - rows[0].ms) / 1000).toFixed(1)} s`);
  console.log('| fase | s | personaje: correcciones (máx m) / salto simulado máx / cámara en ese momento (cm) | personaje: cambio de paso máx (cm) | cámara respecto del personaje: salto máx (cm) / >1 cm | caja: salto máx en el mundo / >2 cm | caja en mano en la vista: salto máx / >2 cm | giro: salto máx (°) | dibujo − simulación máx (cm) | retrocesos (máx cm) | correcciones físicas de la caja (máx cm) | recuperaciones | agarres: salto en la vista (cm) | sueltas: salto en pantalla (cm) | hundida en bloque / piso (cm) |');
  console.log('| --- |' + ' --- |'.repeat(14));
  for (const [name, ph] of phases) {
    console.log(`| ${name} | ${((ph.ms1 - ph.ms0) / 1000).toFixed(1)} | ${ph.actCorr} (${ph.actLast.toFixed(3)}) / ${cm(ph.corrRaw)} / ${cm(ph.corrCam)} | ${cm(max(ph.act))} | ${cm(max(ph.camAct))} / ${over(ph.camAct, 0.01)} | ${cm(max(ph.box))} / ${over(ph.box, 0.02)} | ${ph.heldFrames ? cm(max(ph.rel)) + ' / ' + over(ph.rel, 0.02) : '—'} | ${ph.turn.toFixed(1)} | ${cm(ph.drawnSim)} | ${ph.back} (${cm(ph.backMax)}) | ${ph.boxCorr} (${cm(ph.boxLast)}) | ${ph.recov} | ${ph.grabs.map(cm).join(', ') || '—'} | ${ph.releases.map(cm).join(', ') || '—'} | ${cm(ph.penBlock)} / ${cm(ph.penFloor)} |`);
  }
  return phases;
}

const guest = read(path.join(dir, 'guest.csv'));
const host = read(path.join(dir, 'host.csv'));
console.log(`# Pista de objetos · ${path.basename(dir)}`);
const g = analyse(guest, 'Invitado');
// El host se reparte con las fases del invitado (misma PC, mismo reloj del sistema).
if (host.length && guest.length) {
  const marks = [];
  for (const r of guest) if (!marks.length || marks.at(-1)[1] !== r.fase) marks.push([r.ms, r.fase]);
  for (const r of host) {
    let name = 'antes';
    for (const [ms, f] of marks) if (r.ms >= ms) name = f;
    r.fase = name;
  }
}
analyse(host, 'Host (vista del jugador del host)');
const glog = fs.existsSync(path.join(dir, 'guest.log')) ? fs.readFileSync(path.join(dir, 'guest.log'), 'utf8') : '';
const hlog = fs.existsSync(path.join(dir, 'host.log')) ? fs.readFileSync(path.join(dir, 'host.log'), 'utf8') : '';
for (const [who, log] of [['invitado', glog], ['host', hlog]]) {
  const lines = log.split(/\r?\n/).filter((l) => /\[pista\] (resumen|caja sobre|host:|invitado:)|net_lab\] resumen|SCRIPT ERROR|ERROR:/.test(l));
  console.log(`\n### Consola del ${who}`);
  for (const l of lines.slice(0, 40)) console.log('    ' + l.trim().slice(0, 400));
}
