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
for (const name of (await readdir('examples/mef')).filter(n => n.endsWith('.xml')).sort()) {
  const xml = await readFile(`examples/mef/${name}`, 'utf8');
  const result = JSON.parse(run_json(JSON.stringify({ xml })));
  const normalized = JSON.parse(run_json(JSON.stringify({ xml, command: 'mef_export' })));
  if (!result.ok || !normalized.ok) throw Error(`${name}: ${result.error ?? normalized.error}`);
  const stem = name.slice(0, -4);
  await writeFile(`_build/reports/${stem}-mef.json`, JSON.stringify(result, null, 2) + '\n');
  await writeFile(`_build/reports/${stem}.normalized.xml`, normalized.result);
  console.log(`${name}: analyzed and exported`);
}
