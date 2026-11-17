#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export ROOT

python3 -m py_compile "$ROOT"/simulation/*.py

python3 - <<'PY'
import math
import os
import re
from pathlib import Path

import pandas as pd

root = Path(os.environ["ROOT"])
sim = root / "simulation"
final = sim / "data" / "final"
paper = root / "paper"
errors = []


def count_words(path: Path) -> int:
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"^#.*$", "", text, flags=re.MULTILINE)
    text = re.sub(r"[\[\]*_`$#]", " ", text)
    return len(re.findall(r"[A-Za-z][A-Za-z0-9.'’/-]*", text))


required = [
    sim / "run.py", sim / "core.py", sim / "distance.py",
    sim / "turbidity.py", sim / "diagnostic.py", sim / "wind.py",
    sim / "ambient.py", sim / "replication.py", sim / "load.py",
    sim / "robustness.py", sim / "beam_check.py", sim / "energy.py",
    sim / "paper.py", sim / "scenarios" / "acoustic_direct.tcl",
    sim / "scenarios" / "optical_chain.tcl",
    sim / "scenarios" / "acoustic_chain.tcl",
    final / "distance_runs.csv", final / "distance_summary.csv",
    final / "calibration.csv", final / "turbidity_summary.csv",
    final / "wind_runs.csv", final / "wind_summary.csv",
    final / "wind_step_runs.csv", final / "wind_step_summary.csv",
    final / "load_runs.csv", final / "load_summary.csv",
    final / "replication_runs.csv", final / "replication_summary.csv",
    final / "ambient_summary.csv",
    final / "guard_summary.csv", final / "hop_margin_summary.csv",
    final / "beam_check.csv",
    final / "energy_sensitivity.csv", final / "energy_crossovers.csv",
    final / "diagnostic_runs.csv", final / "diagnostic_summary.csv",
    final / "main_results.csv", final / "diagnostic_results.csv",
    final / "parameters.csv",
    paper / "abstract.typ", paper / "paper.typ", paper / "reproduce.typ",
    paper / "abstract_claims.csv", root / "README.md",
    root / "docs" / "EXPERIMENT.md",
]
for path in required:
    if not path.exists() or path.stat().st_size == 0:
        errors.append(f"missing or empty: {path.relative_to(root)}")

abstract = paper / "abstract.typ"
draft = paper / "paper.typ"
abstract_words = count_words(abstract)
draft_words = count_words(draft)
if not 180 <= abstract_words <= 250:
    errors.append(f"abstract word count out of range: {abstract_words}")
if not 2500 <= draft_words <= 3500:
    errors.append(f"draft word count out of range: {draft_words}")

abstract_text = abstract.read_text(encoding="utf-8")
if "0.586" in abstract_text or "0.682" in abstract_text:
    errors.append("diagnostic acoustic PDR leaked into abstract")
if "acoustic equal-hop diagnostic" not in abstract_text:
    errors.append("abstract does not state diagnostic exclusion")

claims = pd.read_csv(paper / "abstract_claims.csv")
main = pd.read_csv(final / "main_results.csv")
params = pd.read_csv(final / "parameters.csv").set_index(
    "parameter")["value"].astype(str)

for _, claim in claims.iterrows():
    display = str(claim.display)
    if display not in abstract_text:
        errors.append(f"abstract missing display value: {display}")
    source = str(claim.source_table)
    source_path = root / source
    if not source_path.exists():
        errors.append(f"claim source missing: {source}")
        continue
    if source.endswith("parameters.csv"):
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
            errors.append(f"missing main row for {claim.claim_id}")
            continue
        row = row.iloc[0]
        if claim.metric == "pdr_percent":
            expected = row["pdr_mean"] * 100.0
        elif claim.metric == "pdr_ci95_percent":
            expected = row["pdr_ci95"] * 100.0
        elif claim.metric in row.index:
            expected = row[claim.metric]
        else:
            errors.append(f"unknown metric: {claim.metric}")
            continue
    value = float(claim.value)
    if not math.isfinite(expected) or not math.isfinite(value):
        errors.append(f"non-finite claim: {claim.claim_id}")
    elif abs(value - expected) > max(1e-6, abs(expected) * 1e-5):
        errors.append(f"claim mismatch: {claim.claim_id}")

draft_text = draft.read_text(encoding="utf-8").lower()
for section in ("abstract", "introduction", "simulation model and method",
                "results", "discussion and limitations", "conclusion",
                "references", "reproducibility"):
    if section not in draft_text:
        errors.append(f"draft missing section: {section}")
for phrase in ("diagnostic only", "unresolved", "analytical", "unique modems"):
    if phrase not in draft_text:
        errors.append(f"draft missing phrase: {phrase}")

figures = [
    "fig_main_distance.png", "fig_chain_diagnostic.png",
    "fig_regime_maps.png", "fig_hop_hardware.png",
    "fig_energy_sensitivity.png",
]
for name in figures:
    if name not in draft_text:
        errors.append(f"draft does not reference figure: {name}")
    if not (paper / "figures" / name).exists():
        errors.append(f"paper figure missing: {name}")
if draft_text.count("caption:") < 6:
    errors.append("draft has fewer than six captions")

main_results = pd.read_csv(final / "main_results.csv")
diagnostic_results = pd.read_csv(final / "diagnostic_results.csv")
if set(main_results.technology) != {"acoustic", "optical"}:
    errors.append("headline results contain a non-headline technology")
if set(diagnostic_results.technology) != {"acoustic_chain"}:
    errors.append("diagnostic results contain an unexpected technology")
if (diagnostic_results.series_role != "diagnostic_only").any():
    errors.append("diagnostic series role is wrong")

cal = pd.read_csv(final / "calibration.csv").drop_duplicates("water_c")
if sorted(cal.water_c.tolist()) != [0.1, 0.3, 0.5, 0.8, 1.2, 2.19]:
    errors.append("calibration table is incomplete")
if not (final / "turbidity_summary.csv").exists():
    errors.append("turbidity summary missing")

wind = pd.read_csv(final / "wind_summary.csv")
if set(wind.technology) != {"acoustic"}:
    errors.append("wind summary contains a non-acoustic technology")
if sorted(wind.windspeed.unique()) != [0.0, 5.0, 10.0, 15.0, 20.0]:
    errors.append("wind speeds are incomplete")
if set(wind.distance_m) != {500.0, 1000.0, 1500.0}:
    errors.append("wind distances are incomplete")

beam = pd.read_csv(final / "beam_check.csv")
if set(beam.beam_mode) != {0, 1}:
    errors.append("beam check does not contain both modes")
if not beam.identical_to_plain.all():
    errors.append("beam mode differs from plain mode in the check")

load = pd.read_csv(final / "load_summary.csv")
if set(load.technology) != {"acoustic", "optical"}:
    errors.append("load summary technology set is wrong")
if len(load) != 20:
    errors.append(f"load summary has {len(load)} rows, expected 20")

ambient = pd.read_csv(final / "ambient_summary.csv")
if len(ambient) != 6:
    errors.append(f"ambient summary has {len(ambient)} rows, expected 6")
if sorted(ambient.equivalent_depth.unique()) != ["10m", "20m", "5m"]:
    errors.append("ambient summary depth set is wrong")

guard = pd.read_csv(final / "guard_summary.csv")
if len(guard) != 3:
    errors.append(f"guard summary has {len(guard)} rows, expected 3")
margin = pd.read_csv(final / "hop_margin_summary.csv")
if len(margin) != 3:
    errors.append(f"hop-margin summary has {len(margin)} rows, expected 3")

wind_step = pd.read_csv(final / "wind_step_summary.csv")
if len(wind_step) != 10:
    errors.append(f"wind step has {len(wind_step)} rows, expected 10")

if errors:
    print("FAIL")
    print("\n".join(errors))
    raise SystemExit(1)
print(f"PASS: consolidated study and paper ({abstract_words} abstract words, "
      f"{draft_words} draft words)")
PY
