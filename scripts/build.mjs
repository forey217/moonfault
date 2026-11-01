import { spawnSync } from 'node:child_process';
import { copyFile, mkdir, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../', import.meta.url));
const result = spawnSync('moon', ['build', '--target', 'js', '--release', 'cmd/engine'], { cwd: root, stdio: 'inherit' });
if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status ?? 1);
const candidates = ['_build/js/release/build/cmd/engine/engine.js', '_build/js/release/build/forey217/moonfault/cmd/engine/engine.js'];
let source;
for (const p of candidates) { try { await stat(join(root, p)); source = join(root, p); break; } catch {} }
if (!source) throw Error('Compiled engine not found');
await mkdir(join(root, '_build/host'), { recursive: true });
await copyFile(source, join(root, '_build/host/engine.mjs'));
console.log('MoonFault engine ready');
