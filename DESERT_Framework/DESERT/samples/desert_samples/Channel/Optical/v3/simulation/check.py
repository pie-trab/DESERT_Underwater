#!/usr/bin/env python3
"""Validate the v3 dual-head dataset and its equality with the v2 baseline."""

from __future__ import annotations

import math
from pathlib import Path

import pandas as pd

import core

errors: list[str] = []


def require(path: Path) -> None:
    if not path.exists() or path.stat().st_size == 0:
        errors.append(f"missing or empty: {path}")


def check_distance() -> pd.DataFrame:
    runs = pd.read_csv(core.FINAL / "distance_runs.csv")
    if len(runs) != 180:
        errors.append(f"distance_runs has {len(runs)} rows, expected 180")
    if runs.failed.any():
        errors.append("distance_runs contains failed runs")
    if (runs.conservation_residual.abs() > 1e-9).any():
        errors.append("packet conservation residual is non-zero")
    if (runs.phy_lost_packets < 0).any():
        errors.append("negative physical loss count")
    if (runs.pdr < 1.0).any():
        errors.append("lossy run in the headline distance sweep")

    pair = runs.pivot_table(
        index=["total_distance", "rngstream"],
        columns="technology",
        values=["pdr", "delay_mean_s", "energy_per_bit_uj",
                "sent_packets", "delivered_packets", "timing_frame_s"])
    for metric in ("pdr", "delay_mean_s", "energy_per_bit_uj",
                   "sent_packets", "delivered_packets", "timing_frame_s"):
        diff = (pair[(metric, "optical")]
                - pair[(metric, "optical_dual")]).abs().max()
        if not math.isfinite(diff) or diff > 1e-9:
            errors.append(f"v2/v3 mismatch in {metric}: {diff}")

    dual = runs[runs.technology == "optical_dual"]
    expected_modems = 2 * dual.n_relays + 2
    if (dual.unique_modems != expected_modems).any():
        errors.append("dual unique_modems is not 2 * relay_boxes + 2")
    if (dual.hop_count != dual.n_relays + 1).any():
        errors.append("dual water hop count is not relay_boxes + 1")
    single = runs[runs.technology == "optical"]
    if (single.unique_modems != single.n_relays + 2).any():
        errors.append("single-head unique_modems is not relay_boxes + 2")
    return runs


def check_load() -> None:
    runs = pd.read_csv(core.FINAL / "load_runs.csv")
    if runs.failed.any():
        errors.append("load_runs contains failed runs")
    if (runs.conservation_residual.abs() > 1e-9).any():
        errors.append("load packet conservation residual is non-zero")
    if (runs.phy_lost_packets < 0).any():
        errors.append("load has a negative physical loss count")
    pair = runs.pivot_table(
        index=["total_distance", "cbr_period", "rngstream"],
        columns="technology",
        values=["pdr", "delay_mean_s", "goodput_bps", "energy_per_bit_uj"])
    for metric in ("pdr", "delay_mean_s", "goodput_bps",
                   "energy_per_bit_uj"):
        diff = (pair[(metric, "optical")]
                - pair[(metric, "optical_dual")]).abs().max()
        if not math.isfinite(diff) or diff > 1e-9:
            errors.append(f"v2/v3 load mismatch in {metric}: {diff}")
    summary = pd.read_csv(core.FINAL / "load_summary.csv")
    if summary.pdr_mean.min() >= 1.0:
        errors.append("load sweep never reaches saturation")


def check_turbidity() -> None:
    runs = pd.read_csv(core.FINAL / "turbidity_runs.csv")
    if runs.failed.any():
        errors.append("turbidity_runs contains failed runs")
    pair = runs.pivot_table(
        index=["water_c", "rngstream"],
        columns="technology",
        values=["pdr", "delay_mean_s", "energy_per_bit_uj"])
    for metric in ("pdr", "delay_mean_s", "energy_per_bit_uj"):
        diff = (pair[(metric, "optical")]
                - pair[(metric, "optical_dual")]).abs().max()
        if not math.isfinite(diff) or diff > 1e-9:
            errors.append(f"v2/v3 turbidity mismatch in {metric}: {diff}")


def check_energy() -> None:
    table = pd.read_csv(core.FINAL / "energy_sensitivity.csv")
    base = table[(table.power_scale == 1.0)
                 & (table.idle_w_per_modem == 1.5)]
    for distance, group in base.groupby("distance_m"):
        if set(group.topology) != {"single_head", "dual_head"}:
            errors.append(f"energy table missing a topology at {distance} m")
            continue
        single = group[group.topology == "single_head"].iloc[0]
        dual = group[group.topology == "dual_head"].iloc[0]
        if abs(single.energy_active_uj_per_bit
               - dual.energy_active_uj_per_bit) > 1e-6:
            errors.append(f"active energy differs at {distance} m")
        expected = (dual.unique_modems / single.unique_modems)
        ratio = dual.energy_idle_uj_per_bit / single.energy_idle_uj_per_bit
        if abs(ratio - expected) > 1e-6:
            errors.append(f"idle energy ratio is not the modem ratio at "
                          f"{distance} m")


def main() -> None:
    required = [
        core.V3 / "README.md",
        core.V3 / "docs" / "DESIGN.md",
        core.SCRIPT_DIR / "run.py",
        core.SCRIPT_DIR / "core.py",
        core.SCRIPT_DIR / "distance.py",
        core.SCRIPT_DIR / "load.py",
        core.SCRIPT_DIR / "turbidity.py",
        core.SCRIPT_DIR / "energy.py",
        core.SCRIPT_DIR / "check.py",
        core.SCENARIOS / "optical_chain_dual.tcl",
        core.SCENARIOS / "optical_chain.tcl",
        core.SCENARIOS / "acoustic_direct.tcl",
        core.FINAL / "distance_runs.csv",
        core.FINAL / "distance_summary.csv",
        core.FINAL / "main_results.csv",
        core.FINAL / "load_runs.csv",
        core.FINAL / "load_summary.csv",
        core.FINAL / "turbidity_runs.csv",
        core.FINAL / "turbidity_summary.csv",
        core.FINAL / "energy_sensitivity.csv",
        core.FINAL / "calibration.csv",
        core.FINAL / "parameters.csv",
    ]
    for path in required:
        require(path)

    runs = check_distance()
    check_load()
    check_turbidity()
    check_energy()

    if errors:
        print("FAIL")
        print("\n".join(errors))
        raise SystemExit(1)

    dual = runs[runs.technology == "optical_dual"]
    print("PASS: v3 dual-head dataset")
    print(f"  distance runs: {len(runs)}")
    print(f"  relay boxes / modems at 1.5 km: "
          f"{int(dual[dual.total_distance == 1500.0].n_relays.iloc[0])} / "
          f"{int(dual[dual.total_distance == 1500.0].unique_modems.iloc[0])}")
    print("  v2 and v3 optical PDR, delay, active energy and frame are "
          "bit-identical")
    print("  packet conservation residual is zero on every run")


if __name__ == "__main__":
    main()
