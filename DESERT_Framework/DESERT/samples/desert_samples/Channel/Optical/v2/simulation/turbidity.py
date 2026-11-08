#!/usr/bin/env python3
"""Turbidity calibration and distance-scaled optical relays."""

from __future__ import annotations

import math

import pandas as pd

import core


C_VALUES = (0.1, 0.3, 0.5, 0.8, 1.2)
DISTANCES = (50.0, 100.0, 200.0, 500.0, 1000.0)
CAL_HOPS = (2.0, 5.0, 10.0, 15.0, 18.0, 20.0, 22.0, 25.0,
            30.0, 35.0, 40.0, 50.0, 60.0, 75.0, 100.0)
PHASE = {"pilot": (2, 20.0), "main": (10, 100.0)}


def optical_case(distance: float, hop_length: float, n_relays: int,
                 water_c: float, repetition: int, stop_time: float,
                 hop_count: int) -> dict:
    case = dict(core.BASE)
    case.update({
        "technology": "optical",
        "total_distance": distance,
        "n_relays": n_relays,
        "hop_count": hop_count,
        "hop_length": hop_length,
        "water_c": water_c,
        "attenuation_scale": water_c / 0.3,
        "cbr_period": core.BASE["cbr_period"],
        "packet_size": core.BASE["packet_size"],
        "depth": core.BASE["depth"],
        "stop_time": stop_time,
        "rngstream": repetition,
        "poisson_traffic": 1,
    })
    return case


def acoustic_case(distance: float, repetition: int, stop_time: float) -> dict:
    case = dict(core.BASE)
    case.update({
        "technology": "acoustic",
        "total_distance": distance,
        "n_relays": 0,
        "hop_count": 1,
        "hop_length": distance,
        "water_c": math.nan,
        "cbr_period": core.BASE["cbr_period"],
        "packet_size": core.BASE["packet_size"],
        "depth": core.BASE["depth"],
        "stop_time": stop_time,
        "rngstream": repetition,
        "poisson_traffic": 1,
    })
    return case


def calibrate() -> None:
    cases = []
    for c in C_VALUES:
        for hop in CAL_HOPS:
            for repetition in (1, 2):
                cases.append(optical_case(
                    hop, hop, 0, c, repetition, 20.0, 1))
    raw = core.execute_cases(
        cases, core.RAW / "turbidity" / "calibration", "results.csv")
    rows = []
    for (c, hop), group in raw.groupby(
            ["water_c", "hop_length"], dropna=False):
        rows.append({
            "water_c": c,
            "tested_hop_m": hop,
            "pdr_mean": group.pdr.mean(),
            "pdr_ci95": core.ci95(group.pdr),
            "pdr_min_seed": group.pdr.min(),
            "usable": bool(group.pdr.min() >= 0.95),
        })
    table = pd.DataFrame(rows).sort_values(["water_c", "tested_hop_m"])
    selected = []
    for c, group in table.groupby("water_c"):
        usable = group[group.usable]
        max_hop = usable.tested_hop_m.max() if len(usable) else math.nan
        working = 0.8 * max_hop if math.isfinite(max_hop) else math.nan
        selected.append({
            "water_c": c,
            "max_usable_hop_m": max_hop,
            "working_hop_m": working,
            "calibration_status": "OK" if math.isfinite(max_hop)
            else "INFEASIBLE",
        })
    selected = pd.DataFrame(selected)
    table.merge(selected, on="water_c").to_csv(
        core.FINAL / "calibration.csv", index=False)
    print(f"turbidity calibration: {len(raw)} runs")


def grid(phase: str) -> None:
    repetitions, stop_time = PHASE[phase]
    calibration = pd.read_csv(
        core.FINAL / "calibration.csv").drop_duplicates("water_c")
    out_dir = core.RAW / "turbidity" / phase

    acoustic_cases = [acoustic_case(d, r, stop_time)
                      for d in DISTANCES
                      for r in range(1, repetitions + 1)]
    acoustic = core.execute_cases(acoustic_cases, out_dir / "acoustic",
                                  "results.csv")
    optical_cases = []
    infeasible = []
    seen = set()
    for _, cal in calibration.iterrows():
        c = float(cal.water_c)
        working = float(cal.working_hop_m)
        for distance in DISTANCES:
            if not math.isfinite(working) or working < 2.0:
                key = (c, distance)
                if key not in seen:
                    infeasible.append((c, distance, "working hop below 2 m"))
                    seen.add(key)
                continue
            hops = int(math.ceil(distance / working))
            if hops > 100:
                key = (c, distance)
                if key not in seen:
                    infeasible.append((c, distance, "more than 100 hops"))
                    seen.add(key)
                continue
            for repetition in range(1, repetitions + 1):
                optical_cases.append(optical_case(
                    distance, distance / hops, hops - 1, c, repetition,
                    stop_time, hops))
    optical = core.execute_cases(optical_cases, out_dir / "optical",
                                 "results.csv")

    if phase != "main":
        return

    acoustic_summary = core.summarize(acoustic)
    acoustic_summary["water_c"] = math.nan
    acoustic_summary["reused_acoustic"] = True
    duplicated = []
    for c in C_VALUES:
        part = acoustic_summary.copy()
        part["water_c"] = c
        duplicated.append(part)
    acoustic_summary = pd.concat(duplicated, ignore_index=True)
    optical_summary = core.summarize(optical)
    optical_summary["reused_acoustic"] = False
    summary = pd.concat([acoustic_summary, optical_summary],
                        ignore_index=True)
    for c, distance, reason in infeasible:
        cal = calibration[calibration.water_c == c].iloc[0]
        summary = pd.concat([summary, pd.DataFrame([{
            "technology": "optical",
            "water_c": c,
            "distance_m": distance,
            "repetitions": 0,
            "n_relays": math.nan,
            "hop_count": math.nan,
            "hop_length_m": cal.working_hop_m,
            "unique_modems": math.nan,
            "link_endpoint_modems": math.nan,
            "status": "INFEASIBLE",
            "reason": reason,
            "reused_acoustic": False,
        }])], ignore_index=True)
    summary.to_csv(core.FINAL / "turbidity_summary.csv", index=False)
    pd.concat([acoustic, optical], ignore_index=True).to_csv(
        core.FINAL / "turbidity_runs.csv", index=False)
    print(f"turbidity {phase}: {len(optical_cases) + len(acoustic_cases)} runs")
