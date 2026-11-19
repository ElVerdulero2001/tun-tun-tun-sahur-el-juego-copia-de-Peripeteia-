import { spawn } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { createReadStream, existsSync } from 'node:fs';
import { mkdir, readdir, readFile, rename, rmdir, unlink, writeFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { hostname, networkInterfaces } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

const tools = dirname(fileURLToPath(import.meta.url));
const source = resolve(tools, '../..');
const state = resolve(source, '../pista_en_red');
const project = join(state, 'proyecto_host');
const logs = join(state, 'diagnosticos_pista');
const port = 48174;
const projectDirs = ['addons', 'assets', 'bin', 'levels', 'prototypes', 'scenes', 'scripts'];
const projectFiles = ['project.godot', 'icon.svg', 'icon.svg.import', 'extension.gdextension', 'extension.gdextension.uid'];
const prepareOnly = process.argv[2] === '--preparar';
const godot = process.argv[2] || [
    join(source, 'godot.exe'),
    join(process.env.USERPROFILE, 'Desktop', 'Godot_v4.7.2.exe'),
].find(existsSync);

const sha = (data) => createHash('sha256').update(data).digest('hex');

async function projectPaths(folder, relative = '') {
    const paths = [];
    for (const entry of await readdir(join(folder, relative), { withFileTypes: true })) {
        if (entry.name.startsWith('.')) continue;
        const path = [relative, entry.name].filter(Boolean).join('/');
        if (entry.isDirectory() && (relative || projectDirs.includes(entry.name))) {
            paths.push(...await projectPaths(folder, path));
        } else if (entry.isFile() && (relative || projectFiles.includes(entry.name))) {
            paths.push(path);
        }
    }
    return paths.sort();
}

async function publish() {
    const active = new Set(await projectPaths(source));
    for (const path of [...projectFiles, 'bin/sahur_object_world.dll']) {
        if (!active.has(path)) throw new Error('Falta ' + path + ' en la pista.');
    }
    await mkdir(project, { recursive: true });
    let changed = 0;
    for (const path of await projectPaths(project)) {
        if (active.has(path)) continue;
        const file = join(project, path);
        await unlink(file);
        for (let folder = dirname(file); folder !== project; folder = dirname(folder)) {
            if ((await readdir(folder)).length) break;
            await rmdir(folder);
        }
        changed++;
    }
    for (const path of active) {
        const dest = join(project, path);
        const data = await readFile(join(source, path));
        const previous = await readFile(dest).catch((error) => {
            if (error.code !== 'ENOENT') throw error;
        });
        if (previous && data.equals(previous)) continue;
        const folder = dirname(dest);
        await mkdir(folder, { recursive: true });
        const temporary = join(folder, '.pista-nuevo');
        await writeFile(temporary, data);
        await rename(temporary, dest);
        changed++;
    }
    console.log('Pista publicada. Archivos nuevos, actualizados o retirados: ' + changed + '.');
    // Cada arranque revisa el proyecto local. Godot conserva su cache de importacion.
    const importer = spawn(godot, ['--headless', '--path', project, '--import', '--log-file', join(state, 'import_host.log')], {
        stdio: 'ignore', windowsHide: true,
    });
    const result = await exited(importer);
    if (result !== 0) throw new Error('Godot no pudo importar la pista. Revisa import_host.log en ' + state);

    const files = await Promise.all((await projectPaths(project)).map(async (path) => ({
        path, hash: sha(await readFile(join(project, path))),
    })));
    return {
        files,
        contents: new Map(files.map(({ path, hash }) => [hash, join(project, path)])),
    };
}

function exited(child) {
    return new Promise((done, fail) => {
        child.once('error', fail);
        child.once('exit', done);
    });
}

function localAddresses() {
    const lan = [];
    const vpn = [];
    for (const [name, items] of Object.entries(networkInterfaces())) {
        for (const { family, address } of items) {
            if (family !== 'IPv4') continue;
            if (/^(192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.)/.test(address)) {
                lan.push(address);
            } else if ((/radmin/i.test(name) && /^26\./.test(address)) ||
                (/tailscale/i.test(name) && /^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\./.test(address))) {
                vpn.push(address);
            }
        }
    }
    return [...new Set([...lan, ...vpn])];
}

async function prepareInstaller(addresses) {
    await mkdir(state, { recursive: true });
    await writeFile(join(state, '.gitignore'), '*\n');
    const keyFile = join(state, 'clave.txt');
    if (!existsSync(keyFile)) await writeFile(keyFile, randomBytes(24).toString('hex'), { flag: 'wx' });
    const key = (await readFile(keyFile, 'utf8')).trim();
    if (!/^[0-9a-f]{48}$/.test(key)) throw new Error('Clave local de la pista invalida: ' + keyFile);
    const hosts = [...addresses, hostname()];
    const installer = (await readFile(join(tools, 'invitado_pista.cmd.in'), 'utf8'))
        .replace('@CLAVE@', key)
        .replace('@SERVIDORES@', hosts.map((host) => "'http://" + host + ':' + port + "'").join(', '))
        .replace(/\r?\n/g, '\r\n');
    const file = join(state, 'Jugar_como_invitado.cmd');
    await writeFile(file, installer, 'utf8');
    console.log('Lanzador para la otra PC: ' + file);
    return { installer, key };
}

function listen(address, handler) {
    return new Promise((ready, fail) => {
        const server = createServer(handler);
        server.once('error', fail);
        server.listen(port, address, () => ready(server));
    });
}

async function reservePublisher(handler) {
    for (let attempt = 0; ; attempt++) {
        try {
            return await listen('127.0.0.1', handler);
        } catch (error) {
            if (error.code !== 'EADDRINUSE' || attempt === 8) throw error;
            await sleep(250);
        }
    }
}

async function run() {
    const addresses = localAddresses();
    const { installer, key } = await prepareInstaller(addresses);
    if (prepareOnly) return;
    if (!godot || !existsSync(godot)) throw new Error('Instala Godot 4.7.2 en el Escritorio o arrastra el EXE sobre Jugar_como_host.cmd.');

    let published;
    const serve = (request, response) => {
        const endpoint = request.url;
        response.setHeader('Cache-Control', 'no-store');
        if (request.method !== 'GET') return response.writeHead(405).end();
        if (endpoint === '/' + key + '/Jugar_como_invitado.cmd') {
            return response.writeHead(200, {
                'Content-Type': 'application/octet-stream',
                'Content-Disposition': 'attachment; filename="Jugar_como_invitado.cmd"',
            }).end(installer);
        }
        if (request.headers.authorization !== 'Bearer ' + key) return response.writeHead(403).end();
        if (!published) return response.writeHead(503).end();
        if (endpoint === '/manifest.json') {
            return response.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8' })
                .end(JSON.stringify({ version: 1, files: published.files, host: request.socket.localAddress }));
        }
        const hash = /^\/archivo\/([0-9a-f]{64})$/.exec(endpoint)?.[1];
        const file = published.contents.get(hash);
        if (!file) return response.writeHead(404).end();
        createReadStream(file).once('error', () => response.destroy()).pipe(response);
    };

    // El puerto de loopback impide que dos ventanas modifiquen la misma copia.
    const servers = [await reservePublisher(serve)];
    try {
        for (const address of addresses) {
            try {
                servers.push(await listen(address, serve));
            } catch (error) {
                console.warn('No se pudo publicar en ' + address + ': ' + error.message);
            }
        }
        if (servers.length === 1) console.warn('Solo esta disponible en esta PC. Revisa la conexion Wi-Fi o VPN.');
        await mkdir(logs, { recursive: true });
        console.log('Preparando Godot. Espera a que se abra la partida.');
        published = await publish();
        const game = spawn(godot, [
            '--path', project, '--scene', 'res://scenes/net_lab/net_lab.tscn',
            '--log-file', join(state, 'host.log'), '--', '--host', '--pista-objetos', '--pista-diagnostico=' + logs,
        ], { stdio: 'ignore' });
        for (const server of servers.slice(1)) {
            console.log('Descarga inicial para el invitado: http://' + server.address().address + ':' + port + '/' + key + '/Jugar_como_invitado.cmd');
        }
        console.log('JSONL del host: ' + logs);
        console.log('Deja esta ventana abierta mientras juegan.');
        if (await exited(game) !== 0) throw new Error('Godot termino con error. Revisa host.log en ' + state);
    } finally {
        for (const server of servers) server.close();
    }
}

run().catch((error) => {
    console.error(error.code === 'EADDRINUSE' ? 'Ya hay una pista publicandose. Cerra primero esa partida.' : error.message);
    process.exitCode = 1;
});
