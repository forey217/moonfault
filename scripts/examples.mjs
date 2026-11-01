import { readdir, readFile, mkdir, writeFile } from 'node:fs/promises';
import { run_json } from '../_build/host/engine.mjs';
await mkdir('_build/reports', { recursive: true });
for (const name of (await readdir('examples')).filter(n => n.endsWith('.json')).sort()) {
 const request = JSON.parse(await readFile(`examples/${name}`, 'utf8'));
 const result = JSON.parse(run_json(JSON.stringify(request)));
 if (!result.ok) throw Error(`${name}: ${result.error}`);
 await writeFile(`_build/reports/${name}`, JSON.stringify(result, null, 2) + '\n');
 console.log(`${name}: verified; output in _build/reports/${name}`);
}
