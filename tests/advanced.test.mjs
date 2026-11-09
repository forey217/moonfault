import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { run_json } from '../_build/host/engine.mjs';
const run = x => JSON.parse(run_json(JSON.stringify(x)));
const result = x => { const r = run(x); assert(r.ok, JSON.stringify(r)); return r.result; };
const close = (a, b) => assert(Math.abs(a-b) <= 1e-12 * Math.max(1, Math.abs(b)), `${a} != ${b}`);
const op = (kind, ...args) => ({ kind, args });
const ids = ['a','b','c'];
const model = formula => ({ events: ids.map((id,i) => ({ id, probability: [0.15,0.35,0.55][i] })), gates: [{ id: 'top', formula }], top:'top' });
const terms = p => p.map(x => x.map(l => `${l.failed?'+':'-'}${l.event}`).sort().join(',')).sort();
function assignment(mask, i) { return (mask & (1 << i)) !== 0; }
function evalTable(table, mask) { return (table & (1 << mask)) !== 0; }
function expectedPrimes(table) {
  function implies(cube) {
    return Array.from({ length: 8 }, (_, i) => i).every(mask => !cube.every((v, i) => v === 0 || (v === 1) === assignment(mask, i)) || evalTable(table, mask));
  }
  const primes = [];
  for (let a = -1; a <= 1; a++) for (let b = -1; b <= 1; b++) for (let c = -1; c <= 1; c++) {
    const cube = [a,b,c];
    if (implies(cube) && cube.every((v,i) => v===0 || !implies(cube.map((w,j)=>i===j?0:w)))) primes.push(cube.flatMap((v,i) => v === 0 ? [] : [{ event: ids[i], failed: v === 1 }]));
  }
  return primes;
}
function weighted(table, weights) {
  let sum = 0;
  for (let mask = 0; mask < 8; mask++) if (evalTable(table, mask)) sum += weights.reduce((p,q,i)=>p*(assignment(mask,i)?q:1-q),1);
  return sum;
}
function ratio(metric, n, d, unbounded = false) {
  if (d === 0) assert.deepEqual(metric, { status: unbounded && n > 0 ? 'infinite' : 'undefined', value: null });
  else { assert.equal(metric.status, 'finite'); close(metric.value, n/d); }
}
test('all 256 three-variable Boolean functions agree with independent cube and probability oracles', async () => {
  let checked = 0;
  for (let table=0; table<256; table++) {
    const clauses = [];
    for (let mask=0; mask<8; mask++) if (evalTable(table,mask)) clauses.push(op('and', ...ids.map((id,i)=>assignment(mask,i)?id:op('not',id))));
    const m = model(clauses.length ? op('or',...clauses) : false);
    const weights = m.events.map(e=>e.probability);
    const q = weighted(table,weights);
    const answer = result({ model:m, order: table % 2 ? ['c','b','a'] : ['a','b','c'] });
    const primes = expectedPrimes(table);
    assert.deepEqual(terms(answer.prime_implicants), terms(primes), `truth table ${table}`);
    assert.equal(answer.logic_class, primes.some(xs=>xs.some(l=>!l.failed)) ? 'nonmonotone' : 'monotone');
    if (answer.logic_class === 'nonmonotone') { assert.equal(answer.minimal_cut_sets,null); assert.equal(answer.cut_union_bound,null); }
    close(answer.probability,q);
    assert(answer.prime_union_bound+1e-12>=q);
    for (const row of answer.importance) {
      const i=ids.indexOf(row.event), q0=weighted(table,weights.map((p,j)=>j===i?0:p)), q1=weighted(table,weights.map((p,j)=>j===i?1:p));
      close(row.birnbaum,q1-q0); close(row.if_working,q0); close(row.if_failed,q1);
      ratio(row.fussell_vesely,q-q0,q); ratio(row.raw,q1,q,true); ratio(row.rrw,q,q0,true); ratio(row.scram_dif,weights[i]*q1,q);
      checked++;
    }
  }
  await mkdir('_build/reports',{recursive:true});
  await writeFile('_build/reports/signed-prime-oracle.json', JSON.stringify({ functions:256, assignmentChecks:2048, candidateCubes:6912, importanceRows:checked, method:'independent ternary-cube minimality and full truth-table probability', passed:true },null,2));
});

test('consensus prime survives even when no simple BDD path spells it out', () => {
  const m=model(op('or',op('and','a','b'),op('and',op('not','a'),'c')));
  const r=result({model:m});
  assert.deepEqual(terms(r.prime_implicants), ['+a,+b','+b,+c','+c,-a']);
  assert.equal(run({model:m,max_prime_implicants:2}).code,'limit');
  assert.equal(run({model:m,command:'importance',max_prime_implicants:2}).ok,true);
});

test('all XML examples preserve probabilities, signed primes and metadata after import/export', async () => {
  for (const [name,p] of [['shared-power',0.02245],['consensus',0.34],['scoped-switch',0.0882]]) {
    const xml=await readFile(`examples/mef/${name}.xml`,'utf8');
    const before=result({xml});
    close(before.probability,p);
    const normalized=result({xml,command:'mef_export'});
    assert.deepEqual(result({xml:normalized}),before);
    if(name==='scoped-switch') { assert.match(normalized,/主链路 &amp; 备用链路/); assert.match(normalized,/name="case" value="scoped"/); }
  }
});

test('nested MEF operators and multiple top selection preserve Boolean semantics', () => {
  const clauses = `<define-gate name="xorTop"><xor><event name="a" type="basic-event"/><basic-event name="b"/></xor></define-gate>
  <define-gate name="implyTop"><imply><basic-event name="a"/><basic-event name="b"/></imply></define-gate>
  <define-gate name="iffTop"><iff><basic-event name="a"/><basic-event name="b"/></iff></define-gate>
  <define-gate name="nandTop"><nand><basic-event name="a"/><basic-event name="b"/></nand></define-gate>
  <define-gate name="norTop"><nor><basic-event name="a"/><basic-event name="b"/></nor></define-gate>
  <define-gate name="exactTop"><cardinality min="1" max="1"><basic-event name="a"/><basic-event name="b"/></cardinality></define-gate>
  <define-gate name="voteTop"><atleast min="1"><basic-event name="a"/><basic-event name="b"/></atleast></define-gate>`;
  const xml=`<opsa-mef><define-fault-tree name="Test">${clauses}</define-fault-tree><model-data><define-basic-event name="a"><float value="0.2"/></define-basic-event><define-basic-event name="b"><float value="0.3"/></define-basic-event></model-data></opsa-mef>`;
  assert.equal(result({xml,command:'mef_inspect'}).top_events.length,7);
  assert.match(run({xml}).error,/multiple top/);
  for(const [top,p] of [['xorTop',.38],['implyTop',.86],['iffTop',.62],['nandTop',.94],['norTop',.56],['exactTop',.38],['voteTop',.44]]) close(result({xml,top}).probability,p);
});

test('invalid XML semantics and unsafe XML constructs return diagnostics', () => {
  const envelope=(logic, data='')=>`<opsa-mef><define-fault-tree name="T">${logic}</define-fault-tree>${data}</opsa-mef>`;
  const gate=s=>`<define-gate name="top">${s}</define-gate>`;
  const ref='<basic-event name="a"/>';
  const samples=[
    '<!DOCTYPE opsa-mef SYSTEM "file:///does-not-exist">'+envelope(gate('<constant value="true"/>')),
    '<!DOCTYPE opsa-mef [<!ENTITY x "test">]>'+envelope(gate('<constant value="true"/>')),
    envelope(gate('<gate name="top"/>')),
    envelope(gate('<not><constant value="true"/><constant value="false"/></not>')),
    envelope(gate('<atleast min="2"><constant value="true"/></atleast>')),
    envelope(gate('<event name="h" type="basic-event"/>')+'<define-house-event name="h"/>'),
    envelope(gate('<gate name="hidden"/>')+'<define-component name="C" role="private"><define-gate name="hidden"><constant value="true"/></define-gate></define-component>'),
    envelope(gate(ref),'<model-data><define-basic-event name="a"><exponential><float value="0.2"/></exponential></define-basic-event></model-data>'),
    envelope(gate(ref),'<model-data><define-basic-event name="a"><parameter name="p"/></define-basic-event><define-parameter name="p"><parameter name="p"/></define-parameter></model-data>'),
    envelope(gate(ref),'<model-data><define-basic-event name="a"><float value="1.01"/></define-basic-event></model-data>'),
    envelope(gate('<constant value="true"/>')+'<include href="external.xml"/>'),
    '<opsa-mef xmlns="urn:unknown"><define-fault-tree name="T"/></opsa-mef>',
  ];
  for(const xml of samples) assert.equal(run({xml}).code,'invalid',xml);
});

test('export and analyze CLI round-trip pure XML without overwriting a file', async () => {
  const p=spawnSync(process.execPath,['scripts/cli.mjs','mef-export','examples/nonmonotone.json'],{encoding:'utf8'});
  assert.equal(p.status,0,p.stderr); assert.match(p.stdout,/^<\?xml/);
  const q=spawnSync(process.execPath,['scripts/cli.mjs','mef-analyze','-'],{input:p.stdout,encoding:'utf8'});
  assert.equal(q.status,0,q.stderr); assert.equal(JSON.parse(q.stdout).result.prime_implicants.length,3);
  const bad=spawnSync(process.execPath,['scripts/cli.mjs','mef-export','-'],{input:'<bad/>',encoding:'utf8'});
  assert.equal(bad.status,2); assert.equal(bad.stdout,'');
});
