#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export ROOT

python3 - <<'PY'
import math
import os
from pathlib import Path

import pandas as pd

root = Path(os.environ["ROOT"])
distances = [50.0, 100.0, 200.0, 300.0, 500.0, 750.0, 1000.0, 1500.0]
hop_m = 20.0
errors = []

for phase in ("pilot", "main"):
    out = root / "results_m1" / phase if phase == "pilot" \
        else root / "results_m1"
    raw_path = out / "results.csv"
    summary_path = out / "summary.csv"
    if not raw_path.exists() or not summary_path.exists():
        errors.append(f"missing {phase} result files")
        continue
    raw = pd.read_csv(raw_path)
    summary = pd.read_csv(summary_path)
    if raw["failed"].any():
        errors.append(f"{phase}: failed runs present")
    if not raw["conservation_residual"].fillna(1).eq(0).all():
        errors.append(f"{phase}: conservation residual is not zero")
    if not raw["timing_slot_s"].notna().all():
        errors.append(f"{phase}: missing derived slot values")
    if not raw["timing_airtime_s"].notna().all():
        errors.append(f"{phase}: missing derived airtime values")
    if not raw["timing_propagation_s"].notna().all():
        errors.append(f"{phase}: missing propagation values")
    if not raw["timing_frame_s"].notna().all():
        errors.append(f"{phase}: missing frame values")
    for _, row in raw[raw.technology == "optical"].iterrows():
        expected_hops = int(math.ceil(row.sweep_value / hop_m))
        if row.n_relays != expected_hops - 1:
            errors.append(f"{phase}: relay formula mismatch at D={row.sweep_value}")
        if row.hop_count != expected_hops:
            errors.append(f"{phase}: hop count mismatch at D={row.sweep_value}")
        if row.modems != 2 * expected_hops:
            errors.append(f"{phase}: modem formula mismatch at D={row.sweep_value}")
    for _, row in raw[raw.technology == "acoustic"].iterrows():
        if row.modems != 2:
            errors.append(f"{phase}: acoustic modem count mismatch")
    for _, row in summary.iterrows():
        if row.pdr_mean == 0:
            if not math.isnan(row.delay_mean_s_mean):
                errors.append(f"{phase}: zero-delivery delay is not NaN")
            if not math.isnan(row.energy_per_bit_uj_mean):
                errors.append(f"{phase}: zero-delivery energy is not NaN")
    if (summary["delay_mean_s_mean"] == 0).any():
        errors.append(f"{phase}: delay summary contains numeric zero")
    if (summary["energy_per_bit_uj_mean"] == 0).any():
        errors.append(f"{phase}: energy summary contains numeric zero")
    if sorted(summary.distance_m.unique()) != distances:
        errors.append(f"{phase}: distance set mismatch")

if errors:
    print("FAIL")
    print("\n".join(errors))
    raise SystemExit(1)
print("PASS: milestone 1 timing, relay scaling, NaN handling, and conservation")
PY
