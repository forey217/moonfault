# Analysis contract

A basic event set to true denotes failure. Distinct basic event IDs are independent Bernoulli variables, and repeated references share one variable. Gate outputs are not assumed independent. House events are constants, excluded from the prime literals and importance list. Cycles and unknown references, including in unused declarations, are rejected.

`compile` retains the flat AND/OR/vote API; `compile_logic` accepts nested formulas. The order is an exact permutation of basic-event IDs, or empty for lexical order. `overrides` changes probabilities and `forced` takes precedence, setting selected values to 0 or 1. Weighted BDD evaluation uses binary64 Shannon expansion without product truncation; rounding and underflow are possible.

## Risk importance

Let Q be the current top probability, p the effective probability of X, and Q1/Q0 the top probabilities with X set to failed/working. All other event probabilities stay fixed.

| Field | Definition |
| --- | --- |
| `birnbaum` | Q1 − Q0 |
| `fussell_vesely` | (Q − Q0) / Q, evaluated as p × (Q1 − Q0) / Q |
| `raw` | Q1 / Q |
| `rrw` | Q / Q0 |
| `scram_dif` | p × Q1 / Q, the SCRAM diagnosis factor |

SCRAM calls the normalized risk reduction `CIF` and the diagnosis factor `DIF`. We report both separately. For Q=0, FV and DIF are undefined. For RAW or RRW, a positive numerator over zero is infinite; 0/0 is undefined. A ratio outside binary64 with nonzero denominator has status overflow. A nonfinite status carries JSON null, never a silent zero. Negative Birnbaum/FV and worth ratios below one are preserved for nonmonotone functions.

## Prime families

A prime is a sufficient conjunction of signed literals for which deleting any literal loses sufficiency. It is structural and is unaffected by probability/forced-state changes. For cofactors F0 and F1 at x, primes omitting x come from F0 ∧ F1; remaining candidates add ¬x or x to the corresponding cofactor primes. Sorted subsumption removes nonminimal cubes. This returns consensus terms as well as terms from BDD paths. `[]` means false; `[[]]` means true.

The function is monotone exactly when all primes are positive. The legacy minimum-cut API rejects nonmonotone input; its JSON equivalent is null. The prime union bound sums cube probabilities (using 1−p for a negative literal) and clips at one. It is not the exact top probability.

Limits: 64 basic events, 256 house events, 256 gates, 64 operands, 20,000 formula occurrences, 128 UTF-16 units per ID and traversal depth 128. BDD and consensus work have per-phase 20,000-node and 2,000,000-apply budgets. Prime antichains allow 1..5,000 cubes, 4,000,000 subset checks and 250,000 cached cubes. Limit errors never stand for partial complete families.

Sources: [Bryant 1986](https://www.cs.cmu.edu/~bryant/pubdir/ieeetc86.pdf) for BDDs, [NRC risk worth report](https://www.nrc.gov/regulations-legislation/nureg-series-publications/publications-prepared-by-nrc-contractors/cr3385) and [risk reduction FV](https://www.nrc.gov/sites/default/files/doc_library/cdn/legacy/reading-rm/doc-collections/gen-comm/reg-issues/2002/ri200214s1.pdf), and [SCRAM importance analysis](https://github.com/rakhimov/scram/blob/0.16.2/src/importance_analysis.cc) for terminology and external comparisons. SCRAM is a separate test executable; no SCRAM source is shipped. The existing `wcx789ll/moon-reliability` library focuses on lifetime distributions; MoonFault analyzes Boolean combinations and exchanges fault-tree models.
