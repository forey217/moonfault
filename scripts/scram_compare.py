"""Integration oracle: installed SCRAM CLI, not its source or a simulated result."""
import json
import math
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
REPORTS = ROOT / "_build" / "reports"
REPORTS.mkdir(parents=True, exist_ok=True)


def run(args):
    completed = subprocess.run(args, cwd=ROOT, text=True, encoding="utf-8", capture_output=True)
    if completed.returncode:
        raise AssertionError(f"{args} exited {completed.returncode}:\n{completed.stderr}\n{completed.stdout}")
    return completed.stdout


def compare(actual, expected):
    # SCRAM's XML reporter serializes finite floating numbers with rounded decimal text.
    if not math.isclose(actual, expected, rel_tol=1e-5, abs_tol=1e-9):
        raise AssertionError(f"SCRAM mismatch: {actual} vs {expected}")


def prime_signature(products):
    return sorted(tuple(sorted((lit["event"], lit["failed"]) for lit in product)) for product in products)


def parse_product(product):
    for literal in product:
        if literal.tag == "not":
            child = literal.find("basic-event")
            if child is None:
                raise AssertionError("unexpected negative SCRAM literal")
            yield {"event": child.attrib["name"], "failed": False}
        elif literal.tag == "basic-event":
            yield {"event": literal.attrib["name"], "failed": True}
        else:
            raise AssertionError(f"unexpected SCRAM literal {literal.tag}")


version = run(["scram", "--version"]).strip()
evidence = []
for case, source, top, alias in [
    ("shared-power", "examples/mef/shared-power.xml", None, {}),
    ("consensus", "examples/mef/consensus.xml", None, {}),
    ("scoped-switch", "examples/mef/scoped-switch.xml", None, {}),
    ("redundant-storage", "examples/redundant-storage.json", None, {}),
    ("exponential", "examples/mef/exponential.xml", None, {}),
]:
    normalized = REPORTS / f"{case}.scram-input.xml"
    normalized.write_text(run(["node", "scripts/cli.mjs", "mef-export", source]), encoding="utf-8", newline="\n")
    args = ["node", "scripts/cli.mjs", "mef-analyze", str(normalized)]
    if top is not None:
        args.extend(["--top", top])
    actual = json.loads(run(args))["result"]
    report = REPORTS / f"{case}.scram-report.xml"
    run(["scram", "--validate", str(normalized)])
    run(["scram", "--bdd", "--prime-implicants", "--probability", "true", "--importance", "true", "-o", str(report), str(normalized)])
    root = ET.parse(report).getroot()
    products = root.findall("./results/sum-of-products")
    if len(products) != 1:
        raise AssertionError(f"{case}: expected one SCRAM top, got {len(products)}")
    product = products[0]
    compare(actual["probability"], float(product.attrib["probability"]))
    expected = [list(parse_product(item)) for item in product.findall("product")]
    actual_terms = [[{**lit, "event": alias.get(lit["event"], lit["event"])} for lit in xs] for xs in actual["prime_implicants"]]
    if prime_signature(actual_terms) != prime_signature(expected):
        raise AssertionError(f"{case}: signed primes differ: {actual_terms} vs {expected}")
    risks = {alias.get(row["event"], row["event"]): row for row in actual["importance"]}
    rows = root.findall("./results/importance/basic-event")
    if not rows:
        raise AssertionError(f"{case}: SCRAM has no importance results")
    for row in rows:
        attr = row.attrib
        risk = risks[attr["name"]]
        compare(risk["birnbaum"], float(attr["MIF"]))
        for key, other in [("fussell_vesely", "CIF"), ("scram_dif", "DIF"), ("raw", "RAW"), ("rrw", "RRW")]:
            if risk[key]["status"] != "finite":
                raise AssertionError(f"{case}: fixture should have finite {key}")
            compare(risk[key]["value"], float(attr[other]))
    evidence.append({"fixture": case, "topProbability": actual["probability"], "primes": len(expected), "importanceRows": len(rows), "passed": True})
    print(f"{case}: SCRAM parsed export; probability, signed primes, and {len(rows)} importance rows agree")
(REPORTS / "scram-interop.json").write_text(json.dumps({"tool": version, "cases": evidence, "passed": True}, indent=2) + "\n", encoding="utf-8")
