# Verification

Pinned implementation toolchain: MoonBit `0.10.15+943464bfa`, Moon `0.1.20261012`. Host tools: Node.js 24. No npm runtime or test dependencies.

The workspace has 11 registered MoonBit tests: 10 library groups and one independent public-API consumer group. Tests cover shared events, gate semantics, invalid/cyclic DAGs including unreachable gates, input aliasing, interventions, importance, cut antichains and budget rejection. Local JS, Wasm GC and Wasm runs pass. GitHub CI additionally runs Linux native, using the same test suite.

Five Node test groups include 240 deterministic random DAGs (seed 280651) with up to seven events. The reference directly enumerates every Boolean assignment, evaluates gate truth values, sums Bernoulli weights and removes every nonminimal satisfying set. It does not use BDDs. Each model also checks variable-order invariance, interventions, event importance and the cut union bound. Three worked examples and CLI error codes are asserted.

Reproduce with `npm run verify`; inspect `_build/reports/truth-table-oracle.json` and the three example reports. CI uploads these records as an artifact. This is finite evidence, not exhaustive certification of every possible input. Comparisons use absolute tolerance 1e-11 for independent binary64 summation orders.

The cut cache is additionally bounded to 1,000,000 stored event indices across all memoized antichains. Arithmetic-independent graph, node and work limits are described in contract.md. No incomplete enumeration is reported as complete.
