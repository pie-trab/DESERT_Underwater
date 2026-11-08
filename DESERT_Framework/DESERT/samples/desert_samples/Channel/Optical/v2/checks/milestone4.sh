#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export ROOT

"$ROOT/checks/milestone1.sh"
"$ROOT/checks/milestone2.sh"
"$ROOT/checks/milestone3.sh"

python3 - <<'PY'
import os
from pathlib import Path

import pandas as pd

root = Path(os.environ["ROOT"])
out = root / "results_m4"
paper = out / "paper"
distances = [50.0, 100.0, 200.0, 500.0, 1000.0, 1500.0]
errors = []

assets = [
    "fig_main_distance.png", "fig_chain_diagnostic.png",
    "fig_regime_maps.png", "fig_hop_hardware.png",
    "fig_energy_sensitivity.png", "main_results.csv", "main_results.md",
    "diagnostic_results.csv", "diagnostic_results.md", "parameters.csv",
    "parameters.md", "paper_summary.md", "claims_and_caveats.md",
]
for name in assets:
    path = paper / name
    if not path.exists() or path.stat().st_size == 0:
        errors.append(f"missing or empty paper asset: {name}")

main = pd.read_csv(paper / "main_results.csv")
diagnostic = pd.read_csv(paper / "diagnostic_results.csv")
if set(main.technology) != {"acoustic", "optical"}:
    errors.append("headline results include a non-headline technology")
if set(diagnostic.technology) != {"acoustic_chain"}:
    errors.append("diagnostic results do not contain exactly the acoustic chain")
if "acoustic_chain" in set(main.technology):
    errors.append("acoustic chain leaked into headline results")
if sorted(main.distance_m.unique()) != distances:
    errors.append("headline distance grid mismatch")
if sorted(diagnostic.distance_m.unique()) != distances:
    errors.append("diagnostic distance grid mismatch")
if not (diagnostic.series_role == "diagnostic_only").all():
    errors.append("diagnostic series role is not diagnostic_only")
if diagnostic.artifact_note.isna().any():
    errors.append("diagnostic artifact note missing")
if not ((diagnostic.pdr_mean < 0.95).any()):
    errors.append("diagnostic table does not expose the low-PDR artifact")

for _, row in main.iterrows():
    if row.technology == "acoustic":
        if row.unique_modems != 2:
            errors.append("direct acoustic modem count is not 2")
    elif row.unique_modems != row.hop_count + 1:
        errors.append("optical unique modem count is not hops+1")
    if row.delay_mean_s_mean == 0 or row.energy_per_bit_uj_mean == 0:
        errors.append("headline table stores undefined metric as zero")

for _, row in diagnostic.iterrows():
    if row.unique_modems != row.hop_count + 1:
        errors.append("diagnostic unique modem count is not hops+1")
    if row.delay_mean_s_mean == 0 or row.energy_per_bit_uj_mean == 0:
        errors.append("diagnostic table stores undefined metric as zero")

params = pd.read_csv(paper / "parameters.csv").set_index("parameter")["value"]
expected = {
    "acoustic_bitrate": "20768",
    "optical_bitrate": "1000000",
    "clear_water_c": "0.3",
    "optical_hop_clear_water": "20",
    "tdma_guard": "0.001",
    "tdma_packets_per_slot": "1",
    "payload": "125",
    "seeds": "10",
}
for key, value in expected.items():
    if key not in params or str(params[key]) != value:
        errors.append(f"parameter freeze mismatch: {key}")

text = (paper / "paper_summary.md").read_text(encoding="utf-8").lower()
for phrase in ("diagnostic only", "unresolved", "direct acoustic", "optical"):
    if phrase not in text:
        errors.append(f"paper summary missing phrase: {phrase}")
claims = (paper / "claims_and_caveats.md").read_text(encoding="utf-8").lower()
for phrase in ("diagnostic only", "artifact", "excluded"):
    if phrase not in claims:
        errors.append(f"claims file missing phrase: {phrase}")

for name in ("REPRODUCE.md", "M4_FINDINGS.md"):
    path = out / name if name == "REPRODUCE.md" else root / name
    if not path.exists() or path.stat().st_size == 0:
        errors.append(f"missing final document: {name}")

if errors:
    print("FAIL")
    print("\n".join(errors))
    raise SystemExit(1)
print("PASS: milestone 4 final paper package")
PY

git -C "$ROOT" rev-parse --show-toplevel >/dev/null 2>&1 || {
    echo "FAIL: not a git work tree"
    exit 1
}
for path in results_m1 results_m2 results_m3 results_current_baseline focused_results; do
    if ! git -C "$ROOT" diff --quiet -- "$ROOT/$path"; then
        echo "FAIL: protected result directory modified: $path"
        exit 1
    fi
done
