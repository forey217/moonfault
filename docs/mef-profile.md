# Open-PSA MEF 2.0 static profile

This document describes the shipped **0.3.0** API, not the final project scope. Full MEF 2.0 support is the delivery target in the [implementation and acceptance plan](mef-roadmap.md). Features listed as unsupported below remain unimplemented today; the plan does not change runtime behavior or certify conformance.

Sources: [Fault Tree Layer](https://open-psa.github.io/mef/mef/fault_tree_layer.html) and [Stochastic Layer](https://open-psa.github.io/mef/mef/stochastic_layer.html). MoonFault covers static Boolean model exchange, with fixed probabilities evaluated from explicit scalar expressions.

| Construct | Behavior |
| --- | --- |
| `opsa-mef`, `define-fault-tree`, `define-component`, `model-data` | Multiple trees, nested components, public/private roles, global declarations and explicit top selection |
| `define-gate`, `define-basic-event`, `define-house-event` | Forward references; house default false; explicit probability required before numerical analysis |
| Typed and untyped event references | Local scope, full dotted path, unique public short name; typed mismatch rejected |
| Boolean formulae | Pass-through, constant, and/or/not/xor/iff/nand/nor/imply/atleast/cardinality |
| Static expressions | float, exact binary64 int, bool, parameters, 27 numerical operations, Boolean/conditional expressions and three lifetime functions; see [expression contract](expressions.md) |
| Labels and attributes | Retained when re-emitting the normalized document |

Identifiers are case-sensitive Unicode NCName-style names with dots reserved for scope. Duplicate declarations and public names are rejected. Unreferenced defined gates are listed as candidate tops; choose one explicitly if there are several. The normalized export retains scope, metadata and semantic operands; it does not retain comments, XML declaration/DOCTYPE bytes or formatting. The typed `export_mef` writes a flat model with the selected top and reachable gates and will wrap a basic/house top in a pass-through gate.

A bare opsa-mef DOCTYPE is accepted. DTD subsets, external identifiers and custom entities are prohibited. XML has no file/network resolver. Parsing uses [Milky2018/xml@0.5.0](https://mooncakes.io/docs/Milky2018/xml@0.5.0), Apache-2.0; the MEF mapping and validation are MoonFault code.

Unsupported: implicit undeclared events, external includes, event trees, dynamic gates, implicit mission-time context, periodic-test, random deviates, CCF groups, substitutions, external programs and dimensioned parameters. Unsupported semantic elements cause an error. SCRAM can enforce a narrower operator or arity policy than MEF 2.0; the interoperability report identifies the actual cases checked.
