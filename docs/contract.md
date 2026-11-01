# Contract and algorithm sources

## Model

Event=true means that basic event has failed. Every ID denotes exactly one variable. Different basic event IDs are independent Bernoulli variables; no statistical independence between compound gate outputs is assumed. The model is a coherent AND/OR/k-of-n DAG. Each direct input list is nonempty and duplicate-free; shared references through different subgates are valid. Cycles and unknown references are rejected even in unreachable gates. Unused valid basic events remain visible with zero top-event importance.

Gate voting means at least k Boolean input functions are true. Common descendants are handled by the shared Boolean representation. Binary64 probability evaluation follows Shannon expansion `(1-p)*low+p*high`; results are subject to ordinary floating point rounding. The top event may be a basic event.

`forced` fixes variables as interventions. For importance of X the tool evaluates X=true and X=false while retaining all OTHER forced states; an existing forced state for X is replaced for those two counterfactuals. Birnbaum importance is their difference. These are not inferred observational correlations.

Minimal cut sets describe the ORIGINAL Boolean top event, regardless of probabilities, overrides or forced states. They are not minimalized again after conditioning. `cut_union_bound` evaluates those original cuts under the current independent/forced probabilities, sums their products and caps at one. It is an upper bound, not the exact top probability. Gate functions remain available through probability-only requests if cut enumeration exceeds budget.

## Limits

1..64 events, at most 256 gates, 1..64 direct inputs per gate, depth <=128, IDs 1..128 UTF-16 units. Default lexical variable order or a caller-provided exact permutation. BDD terminal nodes count toward a 20,000-node budget; at most 2,000,000 apply calls. Cut-set budget 1..5,000 per intermediate antichain, at most 2,000,000 subset checks. Exceeding any budget raises Limit. No partial success or hidden gate approximation. This is an in-memory moderate-size library; large fault trees can exceed these limits.

## Sources and ecosystem distinction

- Randal E. Bryant, *Graph-Based Algorithms for Boolean Function Manipulation* (1986), author-hosted paper: https://www.cs.cmu.edu/~bryant/pubdir/ieeetc86.pdf . Reference for reduction, variable order and apply. The implementation is original MoonBit code, not a port of a third-party source tree.
- `wcx789ll/moon-reliability` (https://github.com/wcx789ll/moon-reliability) describes lifetime-distribution analysis. MoonFault instead evaluates Boolean combinations of shared failures, cut sets and structural importance. It does not replace lifetime fitting.
- MoonBit core collections/json/debug are reused; no alternative JSON parser or general-purpose graph package is introduced.

No dynamic fault-tree standard, external certification or real-world failure data accuracy is claimed.
