# JSON and CLI

The MoonBit `run_json` API and compiled JS export accept the same JSON input. Choose exactly one:

- `model`: `{events:[{id,probability}], houses?:[{id,value}], gates:[...], top}`. Gates are `{id,kind,inputs}` (legacy) or `{id,formula}`. A formula is an ID string, a Boolean, or `{kind,args:[...]}`. Operators: and/or/not/xor/iff/imply/nand/nor/vote/atleast/cardinality. Use `threshold` for vote/atleast, `min` and `max` for cardinality.
- `xml`: an Open-PSA MEF document string. Optional `top` selects a qualified gate ID or unique short name. `probabilities` binds explicit probabilities to MEF basic-event IDs. Use the full dotted ID for scoped events.

Optional `order`, `overrides`, `forced` are defined in [contract.md](contract.md). `max_prime_implicants` bounds qualitative enumeration (default 5000; old alias `max_cut_sets`). JSON input is limited to 3,000,000 UTF-16 units, XML to 1,000,000.

| Command | Result |
| --- | --- |
| `analyze` (default) | Probability, signed primes, union bound, importance rows, and cut sets for monotone models |
| `probability` | Numeric result without enumerating primes |
| `importance` | Factor rows without enumerating primes |
| `prime_implicants` | Array of conjunctions of `{event,failed}` literals |
| `mef_inspect` | XML candidate top gates and missing probability IDs |
| `mef_export` | Normalized XML. For JSON models optional `tree_name` defaults to MoonFault. |

Success is `{ok:true,result:...}`; error is `{ok:false,code,error}`. Ratio values are `{status,value}`. CLI success with `mef-export` emits XML directly. UTF-8 stdin uses `-`. Output paths are created exclusively; exits 0 (computed), 2 (invalid model), 1 (host IO), or 64 (usage).

```sh
node scripts/cli.mjs request.json
node scripts/cli.mjs mef-inspect examples/mef/scoped-switch.xml
node scripts/cli.mjs mef-analyze examples/mef/scoped-switch.xml --top Network.top
node scripts/cli.mjs mef-export examples/mef/scoped-switch.xml --out normalized.xml
```
