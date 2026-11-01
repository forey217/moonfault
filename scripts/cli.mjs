import { readFile, writeFile } from 'node:fs/promises';
import { run_json } from '../_build/host/engine.mjs';
const args = process.argv.slice(2);
if (args.includes('--help')) {
  console.log('node scripts/cli.mjs <request.json|-> [--out result.json]\nAll matching/reservation decisions run in MoonBit. Host only reads and writes JSON.');
  process.exit(0);
}
if (args.length !== 1 && !(args.length === 3 && args[1] === '--out')) {
  console.error('Usage: node scripts/cli.mjs <request.json|-> [--out result.json]'); process.exit(64);
}
try {
  let raw = '';
  if (args[0] === '-') { process.stdin.setEncoding('utf8'); for await (const chunk of process.stdin) raw += chunk; }
  else raw = await readFile(args[0], 'utf8');
  const result = JSON.parse(run_json(raw));
  const output = JSON.stringify(result, null, 2) + '\n';
  if (args[1] === '--out') await writeFile(args[2], output, { encoding: 'utf8', flag: 'wx' });
  else process.stdout.write(output);
  if (!result.ok) process.exitCode = 2;
} catch (error) { console.error(error.message); process.exitCode = 1; }
