# MEF expressions in 0.3.0

Reference: [MEF 2.0 stochastic layer, sections 5.2 and 5.3](https://open-psa.github.io/mef/mef/stochastic_layer.html). These operations are evaluated when importing a document; the resulting probabilities feed the existing static Boolean analysis. This is not event-tree execution, distribution sampling, a time-series solver or full stochastic-layer conformance.

## Supported operations

- All 27 numerical operation names in table 5.1: neg, add, sub, mul, div, pi, abs, acos, asin, atan, cos, cosh, exp, log, log10, mod, pow, sin, sinh, tan, tanh, sqrt, ceil, floor, min, max, mean.
- Boolean operations: and, or, not; eq, df, lt, gt, leq, geq.
- Conditional operations: ite and switch with zero or more case pairs followed by a default expression. Only the selected value branch is evaluated. Boolean and/or also short-circuit.
- Probability built-ins with explicit numerical arguments: exponential(rate, time), GLM(initial probability, failure rate, repair rate, time), Weibull(scale, shape, shift, time).

Numeric variadic operations and and/or require at least two arguments, following the prose table. The RNC uses `expression+`, which also admits one; this discrepancy is explicit, and the implementation follows the table. `switch` requires a default even when every case appears exhaustive.

All branches are checked for supported constructs, syntax, references and parameter cycles before evaluation. Thus a division-by-zero expression in an unselected branch need not be evaluated, but an unknown reference or malformed expression there is still invalid. Parameters are also evaluated independently as declared definitions, including unused definitions; this behavior is not a general lazy parameter language.

## Value and numerical contract

Values use binary64, retaining the 0.2.0 convention that Boolean values map to 0/1. A condition or logical operand must be exactly 0 or 1; arbitrary nonzero numbers are not implicitly true. Parameter declarations with unit `bool` require 0/1; `int` requires an integral value within ±(2^53−1). This is an explicit value-conversion policy, not a claim of complete typed/unit-aware MEF semantics.

Integer literals accept a sign and decimal digits, including values beyond Int32, and reject values outside the exact binary64 integer range. Float literals, evaluated operands and arithmetic fold intermediates must be finite. Division/modulo by zero and invalid function domains return an error. `mod` uses the signed remainder convention (the sign follows the dividend). Mean scales operands before summation to avoid unnecessary overflow. Ordinary rounding, underflow and cancellation still apply; no arbitrary precision is claimed.

Rates and times in the three built-ins must be nonnegative; GLM's initial probability is in [0,1], Weibull scale and shape are strictly positive. Arguments must use mutually consistent units supplied by the caller. `system-mission-time`, dimensioned parameter units and reference-unit conversion are not yet supported. The example names its explicit duration parameter but does not implement the standard mission-time context.

Exponential uses `-expm1(-rate*time)` to retain small probabilities. GLM uses a stable mixture of the initial and equilibrium probabilities, handles zero rates, and avoids overflowing the rate ratio. Weibull returns zero at/before its nonnegative shift; logarithmic scaling handles overflow/underflow of the time/scale ratio. Saturated exposure yields probability one rather than a nonfinite error. These are single-time probability evaluations, not dynamic gates or repair histories.

Periodic-test, external functions, random deviates, event-state tests, CCF and event trees remain planned work in the [complete implementation plan](mef-roadmap.md).

## Reproduce

```sh
moon update
npm run verify
node scripts/cli.mjs mef-analyze examples/mef/lifetime.xml
```

The lifetime example combines an explicit duration, a stress-dependent rate, an exponential component, a repairable GLM component and a shifted Weibull component. Its independently computed component and top probabilities are written to `_build/reports/lifetime-scenario.json`. Expression and lifetime reference results are in `expression-oracle.json` and `lifetime-oracle.json`. The SCRAM comparison additionally checks the exponential example, within the shared supported syntax.
