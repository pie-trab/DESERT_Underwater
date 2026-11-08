#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export ROOT

"$ROOT/checks/milestone4.sh"

python3 - <<'PY'
import math
import os
import re
from pathlib import Path

import pandas as pd

root = Path(os.environ["ROOT"])
m5 = root / "results_m5"
paper = m5 / "manuscript"
abstract_path = paper / "abstract.typ"
paper_path = paper / "paper.typ"
errors = []


def count_words(path: Path) -> int:
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"^#.*$", "", text, flags=re.MULTILINE)
    text = re.sub(r"[\[\]*_`$#]", " ", text)
    return len(re.findall(r"[A-Za-z][A-Za-z0-9.'’/-]*", text))


required = [
    abstract_path,
    paper_path,
    paper / "abstract_claims.csv",
    m5 / "REPRODUCE.typ",
    root / "M5_FINDINGS.typ",
]
for path in required:
    if not path.exists() or path.stat().st_size == 0:
        errors.append(f"missing or empty: {path.relative_to(root)}")

abstract_words = count_words(abstract_path)
paper_words = count_words(paper_path)
if not 180 <= abstract_words <= 250:
    errors.append(f"abstract word count out of range: {abstract_words}")
if not 2500 <= paper_words <= 3500:
    errors.append(f"paper draft word count out of range: {paper_words}")

abstract = abstract_path.read_text(encoding="utf-8")
if "0.586" in abstract or "0.682" in abstract:
    errors.append("acoustic-chain diagnostic PDR leaked into abstract")
if "acoustic equal-hop diagnostic" not in abstract:
    errors.append("abstract does not state the acoustic-chain exclusion")

claims = pd.read_csv(paper / "abstract_claims.csv")
main = pd.read_csv(root / "results_m4" / "paper" / "main_results.csv")
params = pd.read_csv(
    root / "results_m4" / "paper" / "parameters.csv"
).set_index("parameter")["value"].astype(str)

for _, claim in claims.iterrows():
    display = str(claim.display)
    if display not in abstract:
        errors.append(f"abstract does not contain display value: {display}")
    if claim.source_table.endswith("parameters.csv"):
        if claim.metric not in params:
            errors.append(f"unknown parameter claim: {claim.metric}")
            continue
        expected = float(params[claim.metric])
    else:
        row = main[
            (main.technology == claim.technology)
            & (main.distance_m == float(claim.distance_m))
        ]
        if len(row) != 1:
            errors.append(f"missing M4 row for {claim.claim_id}")
            continue
        row = row.iloc[0]
        if claim.metric == "pdr_percent":
            expected = row["pdr_mean"] * 100.0
        elif claim.metric == "pdr_ci95_percent":
            expected = row["pdr_ci95"] * 100.0
        elif claim.metric in row.index:
            expected = row[claim.metric]
        else:
            errors.append(f"unknown M4 metric: {claim.metric}")
            continue
    value = float(claim.value)
    if not math.isfinite(expected) or not math.isfinite(value):
        errors.append(f"non-finite claim: {claim.claim_id}")
    elif abs(value - expected) > max(1e-6, abs(expected) * 1e-5):
        errors.append(
            f"claim mismatch: {claim.claim_id} {value} vs {expected}")

draft = paper_path.read_text(encoding="utf-8").lower()
for section in (
        "abstract", "introduction", "simulation model and method", "results",
        "discussion and limitations", "conclusion", "references",
        "reproducibility"):
    if section not in draft:
        errors.append(f"paper draft missing section: {section}")
for phrase in ("diagnostic only", "unresolved", "analytical", "unique modems"):
    if phrase not in draft:
        errors.append(f"paper draft missing phrase: {phrase}")

figures = [
    "fig_main_distance.png", "fig_chain_diagnostic.png",
    "fig_regime_maps.png", "fig_hop_hardware.png",
    "fig_energy_sensitivity.png",
]
for name in figures:
    if name not in draft:
        errors.append(f"paper draft does not reference figure: {name}")
    if not (root / "results_m4" / "paper" / name).exists():
        errors.append(f"referenced figure missing: {name}")
if draft.count("caption:") < 6:
    errors.append("paper draft has fewer than six figure/table captions")

if errors:
    print("FAIL")
    print("\n".join(errors))
    raise SystemExit(1)
print(f"PASS: milestone 5 final manuscript ({abstract_words} abstract words, "
      f"{paper_words} draft words)")
PY

git -C "$ROOT" rev-parse --show-toplevel >/dev/null 2>&1 || {
    echo "FAIL: not a git work tree"
    exit 1
}
for path in results_m1 results_m2 results_m3 results_m4 results_current_baseline focused_results; do
    if ! git -C "$ROOT" diff --quiet -- "$ROOT/$path"; then
        echo "FAIL: protected result directory modified: $path"
        exit 1
    fi
done
