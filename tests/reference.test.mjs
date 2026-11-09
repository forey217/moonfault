import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { run_json } from '../_build/host/engine.mjs';
const run = x => JSON.parse(run_json(JSON.stringify(x)));
let seed = 280651;
const rand = n => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
const close = (a, b) => assert(Math.abs(a - b) < 1e-11, `${a} != ${b}`);
function truth(model, mask) {
  const values = new Map(model.events.map((e, i) => [e.id, !!(mask & (1 << i))]));
  for (const g of model.gates) {
    const xs = g.inputs.map(id => values.get(id));
    values.set(g.id, g.kind === 'and' ? xs.every(Boolean) : g.kind === 'or' ? xs.some(Boolean) : xs.filter(Boolean).length >= g.threshold);
  }
  return values.get(model.top);
}
function probability(model, overrides = {}, forced = {}) {
  let p = 0;
  for (let mask = 0; mask < (1 << model.events.length); mask++) {
    if (!truth(model, mask)) continue;
    let weight = 1;
    model.events.forEach((e, i) => {
      const q = Object.hasOwn(forced, e.id) ? +forced[e.id] : overrides[e.id] ?? e.probability;
      weight *= mask & (1 << i) ? q : 1 - q;
    });
    p += weight;
  }
  return p;
}
function cuts(model) {
  const result = [];
  for (let mask = 0; mask < (1 << model.events.length); mask++) {
    if (!truth(model, mask)) continue;
    let minimal = true;
    for (let i = 0; i < model.events.length; i++) if (mask & (1 << i) && truth(model, mask ^ (1 << i))) minimal = false;
    if (minimal) result.push(model.events.filter((_, i) => mask & (1 << i)).map(e => e.id).sort());
  }
  return result.sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));
}
const canonical = xs => xs.map(x => [...x].sort()).sort((a, b) => JSON.stringify(a).localeCompare(JSON.stringify(b)));

test('240 shared-event DAGs match complete truth-table probability, cuts and interventions', async () => {
  let assignments = 0, checkedImportances = 0;
  for (let i = 0; i < 240; i++) {
    const events = Array.from({ length: 1 + rand(7) }, (_, j) => ({ id: `e${j}`, probability: rand(101) / 100 }));
    const known = events.map(e => e.id), gates = [];
    for (let j = 0; j < 1 + rand(7); j++) {
      const inputs = [...new Set(Array.from({ length: 1 + rand(Math.min(4, known.length)) }, () => known[rand(known.length)]))];
      const kind = ['and', 'or', 'vote'][rand(3)];
      const g = { id: `g${j}`, kind, inputs, threshold: 1 + rand(inputs.length) };
      gates.push(g); known.push(g.id);
    }
    const model = { events, gates, top: gates.at(-1).id };
    const answer = run({ model }); assert(answer.ok, JSON.stringify(answer));
    close(answer.result.probability, probability(model));
    assert.deepEqual(canonical(answer.result.minimal_cut_sets), cuts(model));
    assert(answer.result.cut_union_bound + 1e-12 >= answer.result.probability);
    for (const importance of answer.result.importance) {
      const high = probability(model, {}, { [importance.event]: true });
      const low = probability(model, {}, { [importance.event]: false });
      close(importance.if_failed, high); close(importance.if_working, low); close(importance.birnbaum, high - low); checkedImportances++;
    }
    const overrides = { [events[0].id]: 0.37 }, forced = { [events.at(-1).id]: false };
    const whatIf = run({ model, overrides, forced, order: events.map(e => e.id).reverse() }); assert(whatIf.ok);
    close(whatIf.result.probability, probability(model, overrides, forced));
    assert.deepEqual(canonical(whatIf.result.minimal_cut_sets), cuts(model));
    assignments += 1 << events.length;
  }
  await mkdir('_build/reports', { recursive: true });
  await writeFile('_build/reports/truth-table-oracle.json', JSON.stringify({ seed: 280651, models: 240, truthAssignmentsPerPass: assignments, checkedImportances, passed: true, reference: 'independent full assignment enumeration with direct AND/OR/threshold semantics; no BDD implementation' }, null, 2));
});

test('invalid unreachable cycle, duplicate input and unsupported gate produce errors', () => {
  const events = [{ id: 'a', probability: 0.1 }];
  for (const model of [
    { events, gates: [{ id: 'unused', kind: 'and', inputs: ['unused'] }], top: 'a' },
    { events, gates: [{ id: 'top', kind: 'vote', threshold: 2, inputs: ['a', 'a'] }], top: 'top' },
    { events, gates: [{ id: 'top', kind: 'priority', inputs: ['a'] }], top: 'top' },
  ]) assert.equal(run({ model }).code, 'invalid');
});

test('cut set budget raises an explicit error while probability-only evaluation remains available', () => {
  const model = { events: Array.from({ length: 6 }, (_, i) => ({ id: `e${i}`, probability: 0.1 })), gates: [{ id: 'top', kind: 'vote', threshold: 3, inputs: ['e0', 'e1', 'e2', 'e3', 'e4', 'e5'] }], top: 'top' };
  assert.equal(run({ model, max_cut_sets: 2 }).code, 'limit');
  assert.equal(run({ model, command: 'probability' }).ok, true);
});

test('three supplied examples assert shared-power, quorum and repair scenarios', async () => {
  for (const name of ['shared-power', 'redundant-storage', 'deployment']) {
    const input = JSON.parse(await readFile(`examples/${name}.json`, 'utf8'));
    const result = run(input); assert(result.ok);
    close(result.result.probability, probability(input.model, input.overrides, input.forced));
    assert.deepEqual(canonical(result.result.minimal_cut_sets), cuts(input.model));
  }
});

test('CLI reads stdin and malformed JSON exits with code 2', () => {
  const input = JSON.stringify({ model: { events: [{ id: 'a', probability: 0.1 }], gates: [], top: 'a' } });
  const p = spawnSync(process.execPath, ['scripts/cli.mjs', '-'], { input, encoding: 'utf8' });
  assert.equal(p.status, 0); assert.equal(JSON.parse(p.stdout).result.probability, 0.1);
  assert.equal(spawnSync(process.execPath, ['scripts/cli.mjs', '-'], { input: '{', encoding: 'utf8' }).status, 2);
});
