import { readFile, writeFile } from 'node:fs/promises';
import { run_json } from '../_build/host/engine.mjs';
const usage = `MoonFault:
  node scripts/cli.mjs <request.json|-> [--out result.json]
  node scripts/cli.mjs mef-analyze <model.xml|-> [--top Tree.Gate] [--out result.json]
  node scripts/cli.mjs mef-inspect <model.xml|-> [--out result.json]
  node scripts/cli.mjs mef-export <model.xml|request.json> [--out model.xml]`;
const argv = process.argv.slice(2);
if (argv.includes('--help')) {
  console.log(usage);
  process.exit(0);
}
const command = ['mef-analyze', 'mef-inspect', 'mef-export'].includes(argv[0]) ? argv.shift() : null;
const input = argv.shift();
const options = new Map();
while (argv.length) {
  const key = argv.shift();
  const value = argv.shift();
  if (!value || options.has(key) || (key !== '--out' && !(key === '--top' && command === 'mef-analyze'))) {
    console.error(usage); process.exit(64);
  }
  options.set(key, value);
}
if (!input) { console.error(usage); process.exit(64); }
try {
  let raw = '';
  if (input === '-') { process.stdin.setEncoding('utf8'); for await (const chunk of process.stdin) raw += chunk; }
  else raw = await readFile(input, 'utf8');
  raw = raw.replace(/^\uFEFF/u, '');
  let request = raw;
  if (command === 'mef-export' && raw.trimStart().startsWith('{')) {
    try { request = JSON.stringify({ ...JSON.parse(raw), command: 'mef_export' }); }
    catch { request = raw; }
  } else if (command) {
    request = JSON.stringify({ xml: raw, command: { 'mef-analyze': 'analyze', 'mef-inspect': 'mef_inspect', 'mef-export': 'mef_export' }[command], top: options.get('--top') });
  }
  const result = JSON.parse(run_json(request));
  const output = command === 'mef-export' && result.ok ? result.result : JSON.stringify(result, null, 2) + '\n';
  if (options.has('--out') && (command !== 'mef-export' || result.ok)) await writeFile(options.get('--out'), output, { encoding: 'utf8', flag: 'wx' });
  else if (command === 'mef-export' && !result.ok) process.stderr.write(output);
  else process.stdout.write(output);
  if (!result.ok) process.exitCode = 2;
} catch (error) { console.error(error.message); process.exitCode = 1; }
