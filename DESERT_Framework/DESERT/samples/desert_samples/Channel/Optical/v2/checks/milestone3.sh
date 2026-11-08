#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
export ROOT

"$ROOT/checks/milestone1.sh"
"$ROOT/checks/milestone2.sh"

python3 - <<'PY'
import math
import os
from pathlib import Path

import numpy as np
import pandas as pd

root = Path(os.environ["ROOT"])
out = root / "results_m3"
distances = [50.0, 100.0, 200.0, 500.0, 1000.0, 1500.0]
errors = []
info = []

for phase in ("pilot", "main"):
    raw_path = out / phase / "results.csv"
    summary_path = out / phase / "summary.csv"
    if not raw_path.exists() or not summary_path.exists():
        errors.append(f"missing {phase} results")
        continue
    raw = pd.read_csv(raw_path)
    summary = pd.read_csv(summary_path)
    if raw.failed.any():
        errors.append(f"{phase}: failed runs present")
    if not raw.conservation_residual.fillna(1).eq(0).all():
        errors.append(f"{phase}: conservation residual is not zero")
    if raw.timing_slot_s.isna().any():
        errors.append(f"{phase}: missing slot values")
    if raw.timing_airtime_s.isna().any():
        errors.append(f"{phase}: missing airtime values")
    if raw.timing_frame_s.isna().any():
        errors.append(f"{phase}: missing frame values")
    for _, row in raw.iterrows():
        hops = int(math.ceil(row.total_distance / 20.0))
        if row.n_relays != hops - 1:
            errors.append(f"{phase}: relay formula mismatch at {row.total_distance}")
        if row.hop_count != hops:
            errors.append(f"{phase}: hop count mismatch at {row.total_distance}")
        if row.unique_modems != hops + 1:
            errors.append(f"{phase}: unique modem mismatch at {row.total_distance}")
        if row.link_endpoint_modems != 2 * hops:
            errors.append(f"{phase}: link-endpoint modem mismatch at {row.total_distance}")
        expected_hop = row.total_distance / hops
        if abs(row.hop_length - expected_hop) > 1e-9:
            errors.append(f"{phase}: hop length mismatch at {row.total_distance}")
    if sorted(summary.distance_m.unique()) != distances:
        errors.append(f"{phase}: distance set mismatch")
    if (summary.delay_mean_s_mean == 0).any():
        errors.append(f"{phase}: delay stored as numeric zero")
    if (summary.energy_per_bit_uj_mean == 0).any():
        errors.append(f"{phase}: energy stored as numeric zero")
    for _, row in summary.iterrows():
        if row.pdr_mean == 0:
            if not math.isnan(row.delay_mean_s_mean):
                errors.append(f"{phase}: zero-delivery delay is not NaN")
            if not math.isnan(row.energy_per_bit_uj_mean):
                errors.append(f"{phase}: zero-delivery energy is not NaN")
    info.append(f"{phase}: {len(raw)} runs, zero failures")

raw = pd.read_csv(out / "main" / "results.csv")
summary = pd.read_csv(out / "main" / "summary.csv")
for _, row in raw.iterrows():
    bits = row.delivered_packets * row.packet_size * 8.0
    expected = ((row.tx_events * 20.0 + row.rx_events * 4.0)
                * row.timing_airtime_s / bits * 1e6)
    if not np.isfinite(expected):
        errors.append("acoustic energy is undefined in a delivered run")
    elif abs(expected - row.energy_per_bit_uj) > 1e-6 * max(1, abs(expected)):
        errors.append("acoustic energy does not match saved counters")

first_log = sorted((out / "main" / "logs").glob("*.log"))[0]
text = first_log.read_text(encoding="utf-8")
if "EFFECTIVE acoustic_chain:" not in text:
    errors.append("effective acoustic-chain line missing")
if "phy_class=Module/UW/PHYSICAL" not in text:
    errors.append("acoustic chain is not using Module/UW/PHYSICAL")
if "channel_class=Module/UnderwaterChannel" not in text:
    errors.append("acoustic chain is not using UnderwaterChannel")

paper = out / "paper"
assets = [
    "fig_distance.png", "fig_regime_maps.png", "fig_hop_hardware.png",
    "fig_energy_sensitivity.png", "parameters.csv", "main_results.csv",
    "claims_and_caveats.md",
]
for name in assets:
    path = paper / name
    if not path.exists() or path.stat().st_size == 0:
        errors.append(f"missing paper asset {name}")

params = pd.read_csv(paper / "parameters.csv").set_index("parameter")["value"]
expected_params = {
    "acoustic_bitrate": "20768",
    "optical_bitrate": "1000000",
    "clear_water_c": "0.3",
    "optical_hop_clear_water": "20",
    "tdma_guard": "0.001",
    "tdma_packets_per_slot": "1",
    "payload": "125",
    "seeds": "10",
}
for key, value in expected_params.items():
    if key not in params or str(params[key]) != value:
        errors.append(f"parameter freeze mismatch: {key}")

results = pd.read_csv(paper / "main_results.csv")
if sorted(results.distance_m.unique()) != distances:
    errors.append("paper distance table mismatch")
for _, row in results.iterrows():
    if row.technology in ("optical", "acoustic_chain"):
        if row.unique_modems != row.hop_count + 1:
            errors.append("paper unique modem count is not hops+1")
    elif row.technology == "acoustic":
        if row.unique_modems != 2:
            errors.append("direct acoustic modem count is not 2")
    if row.delay_mean_s_mean == 0 or row.energy_per_bit_uj_mean == 0:
        errors.append("paper table contains numeric zero for undefined metric")

# The ideal pipeline is a lower bound; measured delay includes slot/queueing.
d1000 = summary[summary.distance_m == 1000.0].iloc[0]
ideal = d1000.hop_count * d1000.slot_s
if not np.isfinite(d1000.delay_mean_s_mean) or d1000.delay_mean_s_mean < ideal:
    errors.append("acoustic-chain measured delay is below the ideal pipeline")
info.append(
    f"1000 m acoustic-chain ideal pipeline {ideal:.3f} s, "
    f"measured {d1000.delay_mean_s_mean:.3f} s")

if errors:
    print("FAIL")
    print("\n".join(errors))
    raise SystemExit(1)
for line in info:
    print("INFO", line)
print("PASS: milestone 3 acoustic chain, paper assets, conservation, and accounting")
PY
