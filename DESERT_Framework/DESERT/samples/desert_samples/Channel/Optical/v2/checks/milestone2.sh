#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export ROOT

python3 - <<'PY'
import math
import os
from pathlib import Path

import numpy as np
import pandas as pd

root = Path(os.environ["ROOT"])
out = root / "results_m2"
c_values = [0.1, 0.3, 0.5, 0.8, 1.2]
distances = [50.0, 100.0, 200.0, 500.0, 1000.0]
errors = []

calibration = pd.read_csv(out / "calibration.csv")
selected = calibration.drop_duplicates("water_c")
if sorted(selected.water_c.tolist()) != c_values:
    errors.append("calibration c table is incomplete")
if not np.allclose(selected.working_hop_m,
                   0.8 * selected.max_usable_hop_m):
    errors.append("working hop is not 80% of the selected hop")
if selected.max_usable_hop_m.isna().any():
    errors.append("a calibration water type has no usable hop")

for phase in ("grid_pilot", "main"):
    phase_dir = out / phase
    acoustic = pd.read_csv(phase_dir / "acoustic_results.csv")
    optical = pd.read_csv(phase_dir / "optical_results.csv")
    summary = pd.read_csv(phase_dir / "summary.csv")
    for frame, label in ((acoustic, "acoustic"), (optical, "optical")):
        if frame.failed.any():
            errors.append(f"{phase}: {label} failures")
        if not frame.conservation_residual.fillna(1).eq(0).all():
            errors.append(f"{phase}: {label} conservation residual")
    for _, row in optical.iterrows():
        working = selected[selected.water_c == row.water_c].iloc[0].working_hop_m
        hops = math.ceil(row.total_distance / working)
        if row.n_relays != hops - 1 or row.expected_hops != hops:
            errors.append(f"{phase}: relay formula mismatch")
        if row.modems != 2 * hops:
            errors.append(f"{phase}: modem formula mismatch")
    if sorted(summary.distance_m.unique()) != distances:
        errors.append(f"{phase}: distance grid mismatch")
    for _, row in summary.iterrows():
        if row.pdr_mean == 0:
            if not math.isnan(row.delay_mean_s_mean):
                errors.append(f"{phase}: undefined delay encoded as zero")
            if not math.isnan(row.energy_per_bit_uj_mean):
                errors.append(f"{phase}: undefined energy encoded as zero")
        if row.status == "INFEASIBLE" and row.repetitions != 0:
            errors.append(f"{phase}: infeasible case was simulated")

energy = pd.read_csv(out / "energy_sensitivity.csv")
for col in ("baseline_uj_bit_mean", "band_min_uj_bit_mean",
            "band_max_uj_bit_mean"):
    if energy[col].isna().any():
        errors.append(f"energy case missing {col}")

m1 = pd.read_csv(root / "results_m1" / "results.csv")
valid = m1[m1.delivered_packets > 0].copy()
valid["recomputed"] = ((valid.tx_events * valid.apply(
    lambda r: 20.0 if r.technology == "acoustic" else 10.0, axis=1)
    + valid.rx_events * valid.apply(
        lambda r: 4.0 if r.technology == "acoustic" else 1.5, axis=1))
    * valid.timing_airtime_s
    / (valid.delivered_packets * valid.packet_size * 8) * 1e6)
check = valid.groupby(["technology", "total_distance"]).recomputed.mean()
stored = energy.pivot(index="distance_m", columns="technology")
for (technology, distance), value in check.items():
    actual = stored.loc[distance, ("baseline_uj_bit_mean", technology)]
    if abs(value - actual) > 1e-6 * max(1.0, abs(value)):
        errors.append(f"energy recomputation mismatch at {technology}/{distance}")

if errors:
    print("FAIL")
    print("\n".join(errors))
    raise SystemExit(1)
print("PASS: milestone 2 calibration, relay scaling, NaN handling, conservation, and energy recomputation")
PY
