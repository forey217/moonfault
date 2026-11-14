import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { run_json } from '../_build/host/engine.mjs';

const f = x => `<float value="${x}"/>`;
const b = x => `<bool value="${x}"/>`;
const op = (name, ...xs) => `<${name}>${xs.join('')}</${name}>`;
const param = name => `<parameter name="${name}"/>`;
const doc = (expr, declarations = '') => `<opsa-mef><define-fault-tree name="T"><define-gate name="top"><basic-event name="a"/></define-gate></define-fault-tree><model-data><define-basic-event name="a">${expr}</define-basic-event>${declarations}</model-data></opsa-mef>`;
const call = request => JSON.parse(run_json(JSON.stringify(request)));
function probability(expr, declarations = '') {
  const r = call({xml: doc(expr, declarations), command: 'probability'});
  assert.equal(r.ok, true, JSON.stringify(r));
  return r.result;
}
function close(actual, expected) {
  assert(Number.isFinite(actual));
  const error = Math.abs(actual - expected);
  assert(error <= Math.max(1e-300, 2e-12 * Math.abs(expected)), `${actual} != ${expected}`);
}
function numeric(expr, expected) {
  // Normalize a known scalar result into the probability range without masking
  // relative errors (tiny values are compared directly in lifetime tests).
  const offset = Math.abs(expected) + 1;
  close(probability(op('div', op('add', expr, f(offset)), f(4 * offset))), (expected + offset) / (4 * offset));
}
const divisionByZero = op('div', f(1), f(0));

test('all MEF numerical operators match independent JavaScript Math results', async () => {
  const unary = {
    neg: x => -x, abs: Math.abs, acos: Math.acos, asin: Math.asin,
    atan: Math.atan, cos: Math.cos, cosh: Math.cosh, exp: Math.exp,
    log: Math.log, log10: Math.log10, sin: Math.sin, sinh: Math.sinh,
    tan: Math.tan, tanh: Math.tanh, sqrt: Math.sqrt, ceil: Math.ceil, floor: Math.floor,
  };
  let comparisons = 0;
  for (const [name, fn] of Object.entries(unary)) {
    for (const x of [.01,.2,.75,1]) { numeric(op(name, f(x)), fn(x)); comparisons++; }
  }
  numeric('<pi/>', Math.PI); comparisons++;
  const binary = {mod: (a,b) => a % b, pow: (a,b) => a ** b};
  for (const [name, fn] of Object.entries(binary)) {
    for (const [a,b] of [[.2,.3],[-.7,2],[.9,3]]) { numeric(op(name,f(a),f(b)),fn(a,b)); comparisons++; }
  }
  const folds = {
    add: xs => xs.reduce((a,b)=>a+b), sub: xs => xs.reduce((a,b)=>a-b),
    mul: xs => xs.reduce((a,b)=>a*b), div: xs => xs.reduce((a,b)=>a/b),
    min: xs => Math.min(...xs), max: xs => Math.max(...xs), mean: xs => xs.reduce((a,b)=>a+b)/xs.length,
  };
  for (const [name, fn] of Object.entries(folds)) {
    for (const xs of [[.2,.3],[.8,.1,.4],[.5,-.2,.8]]) { numeric(op(name,...xs.map(f)),fn(xs)); comparisons++; }
  }
  numeric(op('div',op('mean',f(1e308),f(1e308)),f(1e308)),1); comparisons++;
  close(probability(op('div', '<int value="4294967296"/>', f(8589934592))), .5); comparisons++;
  await mkdir('_build/reports',{recursive:true});
  await writeFile('_build/reports/expression-oracle.json', JSON.stringify({operators:27,comparisons,reference:'JavaScript Math, separate from MoonBit evaluator',passed:true},null,2));
});

test('conditional and Boolean expressions select branches lazily with structural validation', () => {
  close(probability(op('ite',b(true),f(.25),divisionByZero)),.25);
  close(probability(op('ite',b(false),divisionByZero,f(.75))),.75);
  close(probability(op('switch',op('case',b(false),divisionByZero),op('case',b(true),f(.4)),divisionByZero)),.4);
  close(probability(op('switch',op('case',b(false),f(.1)),f(.6))),.6);
  close(probability(op('switch',f(.7))),.7);
  close(probability(op('and',b(false),divisionByZero)),0);
  close(probability(op('or',b(true),divisionByZero)),1);
  const compare = {eq:(a,b)=>a===b,df:(a,b)=>a!==b,lt:(a,b)=>a<b,gt:(a,b)=>a>b,leq:(a,b)=>a<=b,geq:(a,b)=>a>=b};
  for (const [name,fn] of Object.entries(compare)) for(const [a,b] of [[.2,.3],[.2,.2],[.8,.4]]) close(probability(op(name,f(a),f(b))),Number(fn(a,b)));
  close(probability(op('not',b(false))),1);
  close(probability(op('and',b(true),op('not',b(false)))),1);
  const params = `<define-parameter name="mode" unit="int"><int value="2"/></define-parameter><define-parameter name="p"><switch><case><eq>${param('mode')}<int value="1"/></eq>${f(.1)}</case>${f(.2)}</switch></define-parameter>`;
  close(probability(param('p'),params),.2);
});

test('time distributions agree with closed forms over parameter grids and extreme inputs', async () => {
  let comparisons=0;
  for(const rate of [0,1e-20,1e-8,.001,.5,2]) for(const time of [0,1,10,1000]) {
    close(probability(op('exponential',f(rate),f(time))),-Math.expm1(-rate*time)); comparisons++;
  }
  for(const gamma of [0,.2,1]) for(const lambda of [0,.01,1]) for(const mu of [0,.02,2]) for(const time of [0,.01,10,100]) {
    const rate=lambda+mu;
    // Independent rearrangement: interpolate initial and equilibrium failure.
    const expected=rate===0?gamma:gamma+(lambda/rate-gamma)*(-Math.expm1(-rate*time));
    // Avoid cancellation in the reference near zero for recovering components.
    const stable=gamma*Math.exp(-rate*time)+(rate===0?0:lambda/rate)*(-Math.expm1(-rate*time));
    assert(Math.abs(expected-stable)<1e-14);
    close(probability(op('GLM',...[gamma,lambda,mu,time].map(f))),stable); comparisons++;
  }
  for(const scale of [.1,10,100]) for(const shape of [.5,1,2]) for(const shift of [0,5]) for(const time of [0,1,5,20]) {
    const expected=time<=shift?0:-Math.expm1(-(((time-shift)/scale)**shape));
    close(probability(op('Weibull',...[scale,shape,shift,time].map(f))),expected); comparisons++;
  }
  close(probability(op('exponential',f(1e-20),f(1))),1e-20);
  close(probability(op('exponential',f(1e308),f(1e308))),1);
  close(probability(op('GLM',...[.3,1e308,1e308,0].map(f))),.3);
  close(probability(op('GLM',...[.3,1e308,1e308,1].map(f))),.5);
  for(const [scale,shape,time] of [[1e300,.1,1e-300],[1e-300,.001,1e300],[1e300,.1,1e-20]]) {
    const expected=-Math.expm1(-Math.exp(shape*(Math.log(time)-Math.log(scale))));
    close(probability(op('Weibull',...[scale,shape,0,time].map(f))),expected);
  }
  comparisons+=7;
  await mkdir('_build/reports',{recursive:true});
  await writeFile('_build/reports/lifetime-oracle.json', JSON.stringify({comparisons,functions:['exponential','GLM','Weibull'],passed:true},null,2));
});

test('invalid operations, dead-branch syntax, cycles, units and intermediate overflow are rejected', () => {
  const invalid = [
    '<pi><float value="1"/></pi>',op('pow',f(1)),op('add',f(.2)),op('sqrt',f(-1)),op('log',f(0)),
    op('mod',f(1),f(0)),op('acos',f(2)),op('pow',f(-1),f(.5)),
    op('mul',f(1e308),f(1e308),f(0)), // previously could mask overflow with later arithmetic
    op('div',f(1e308),f(1e-308),f(1e308)),
    op('ite',f(.5),f(.1),f(.2)),
    op('ite',b(true),f(.2),'<unknown/>'),
    op('ite',b(true),f(.2),param('missing')),
    op('ite',b(true),f(.2),'<int value="1.5"/>'),
    op('switch',op('case',b(true),f(.2))),
    op('switch',f(.2),f(.3)),op('switch'),
    op('exponential',f(-1),f(1)),op('exponential',f(1),f(-1)),
    op('GLM',...[2,.1,.2,1].map(f)),op('GLM',...[.2,-1,.2,1].map(f)),
    op('Weibull',...[0,1,0,1].map(f)),op('Weibull',...[1,0,0,1].map(f)),
    '<int value="9007199254740993"/>','<int value="1e2"/>',
  ];
  for(const expr of invalid) { const r=call({xml:doc(expr)}); assert.equal(r.code,'invalid',expr+JSON.stringify(r)); }
  const declarations=[
    `<define-parameter name="p">${op('ite',b(true),f(.2),param('p'))}</define-parameter>`,
    `<define-parameter name="p" unit="int">${f(.25)}</define-parameter>`,
    `<define-parameter name="p" unit="bool">${f(2)}</define-parameter>`,
  ];
  for(const d of declarations) assert.equal(call({xml:doc(param('p'),d)}).code,'invalid');
});

test('extended expressions preserve original model syntax and results on XML round trip', () => {
  const xml=doc(op('ite',op('lt',f(.1),f(.2)),op('exponential',f(.001),f(100)),op('Weibull',...[10,2,0,5].map(f))));
  const before=call({xml}); assert.equal(before.ok,true);
  const exported=call({xml,command:'mef_export'}); assert.equal(exported.ok,true);
  assert.match(exported.result,/<exponential>/); assert.match(exported.result,/<Weibull>/);
  assert.deepEqual(call({xml:exported.result}),before);
});

test('published lifetime scenario matches independent component and system probabilities', async () => {
  const xml=await readFile('examples/mef/lifetime.xml','utf8');
  const r=call({xml}); assert.equal(r.ok,true,JSON.stringify(r));
  const power=-Math.expm1(-.0002*100);
  const pump=.01*Math.exp(-.051*100)+.001/.051*(-Math.expm1(-.051*100));
  const wear=-Math.expm1(-(((100-10)/1000)**2));
  close(r.result.probability,1-(1-power)*(1-pump)*(1-wear));
  const exported=call({xml,command:'mef_export'}); assert.equal(exported.ok,true);
  assert.deepEqual(call({xml:exported.result}),r);
  await writeFile('_build/reports/lifetime-scenario.json',JSON.stringify({components:{power,pump,wear},probability:r.result.probability,passed:true},null,2));
});
