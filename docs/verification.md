# Verification

MoonBit `0.10.15+943464bfa`, Moon `0.1.20261012` and Node.js 24. The workspace contains 19 MoonBit tests including two public-API consumer tests. CI checks JS, Wasm GC, Wasm and Linux native. Eleven Node test groups cover 240 seeded coherent DAGs and all 256 three-variable Boolean functions. The signed reference independently examines 6,912 ternary cubes for sufficiency/deletion minimality and compares 768 risk rows against complete assignment summation. It also checks consensus terms, bit 63, zero denominators, negative importance, resource budgets and MEF validity/round trips.

`npm run verify` regenerates the reports. `python3 scripts/scram_compare.py` invokes the independent SCRAM executable installed in Linux CI. It validates MoonFault's XML output and compares top probability, signed products, Birnbaum, FV (SCRAM CIF), DIF, RAW and RRW. CI uploads the actual SCRAM XML and `scram-interop.json`. Decimal comparisons allow SCRAM's XML output rounding; the exhaustive signed oracle uses 1e-12 tolerance.

Tests demonstrate the declared static profile. They do not certify all MEF models or real-world input data.
