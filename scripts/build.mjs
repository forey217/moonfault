import { spawnSync } from 'node:child_process';
import { copyFile, mkdir, stat } from 'node:fs/promises';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = fileURLToPath(new URL('../', import.meta.url));
const target = join(root, '_build', 'host-compiler');
const result = spawnSync('moon', ['build', '--target-dir', target, '--target', 'js', '--release', 'cmd/engine'], { cwd: root, stdio: 'inherit' });
if (result.error) throw result.error;
if (result.status !== 0) process.exit(result.status ?? 1);
const candidates = ['js/release/build/cmd/engine/engine.js', 'js/release/build/forey217/moonfault/cmd/engine/engine.js'];
const found = [];
for (const p of candidates) {
  const path = join(target, p);
  try { found.push({ path, mtime: (await stat(path)).mtimeMs }); } catch (e) { if (e.code !== 'ENOENT') throw e; }
}
found.sort((a, b) => b.mtime - a.mtime);
if (!found.length) throw Error('Compiled engine not found');
await mkdir(join(root, '_build/host'), { recursive: true });
await copyFile(found[0].path, join(root, '_build/host/engine.mjs'));
console.log('MoonFault engine ready');
