#!/usr/bin/env python3
"""Distance sweep: acoustic direct, v2 single-head optical, v3 dual-head."""

from __future__ import annotations

import math

import core

DISTANCES = (50.0, 100.0, 200.0, 500.0, 1000.0, 1500.0)
OPTICAL_HOP_M = 20.0
TECHNOLOGIES = ("acoustic", "optical", "optical_dual")
PHASE = {"pilot": (2, 20.0), "main": (10, 100.0)}


def make_case(technology: str, distance: float, repetition: int,
              stop_time: float) -> dict:
    case = dict(core.BASE)
    case.update({
        "technology": technology,
        "total_distance": distance,
        "cbr_period": core.BASE["cbr_period"],
        "packet_size": core.BASE["packet_size"],
        "depth": core.BASE["depth"],
        "stop_time": stop_time,
        "rngstream": repetition,
        "poisson_traffic": 1,
        "water_c": math.nan,
        "attenuation_scale": 1.0,
    })
    if technology == "acoustic":
        case["n_relays"] = 0
        case["hop_count"] = 1
        case["hop_length"] = distance
    else:
        hops = int(math.ceil(distance / OPTICAL_HOP_M))
        case["n_relays"] = hops - 1
        case["hop_count"] = hops
        case["hop_length"] = distance / hops
    return case


def run(phase: str) -> None:
    repetitions, stop_time = PHASE[phase]
    cases = []
    for distance in DISTANCES:
        for technology in TECHNOLOGIES:
            for repetition in range(1, repetitions + 1):
                cases.append(make_case(technology, distance, repetition,
                                       stop_time))
    out_dir = core.RAW / "distance" / phase
    raw = core.execute_cases(cases, out_dir, "results.csv")
    if phase == "main":
        core.FINAL.mkdir(parents=True, exist_ok=True)
        raw.to_csv(core.FINAL / "distance_runs.csv", index=False)
        summary = core.summarize(raw)
        summary.to_csv(core.FINAL / "distance_summary.csv", index=False)
        main = build_main_results(summary)
        main.to_csv(core.FINAL / "main_results.csv", index=False)
        print(main.to_string(index=False))
    print(f"distance {phase}: {len(raw)} runs")


def build_main_results(summary) -> "pandas.DataFrame":
    """One row per technology and distance with the headline metrics."""
    import pandas as pd

    rows = []
    for distance in DISTANCES:
        block = summary[summary.distance_m == distance]
        for technology in TECHNOLOGIES:
            row = block[block.technology == technology]
            if row.empty:
                continue
            r = row.iloc[0]
            # The summary already carries active, idle (powered modem count)
            # and total energy on the same basis for both optical topologies.
            active = r.energy_per_bit_uj_mean
            idle = r.energy_idle_uj_per_bit_mean
            total = r.energy_total_uj_per_bit_mean
            rows.append({
                "distance_m": distance,
                "technology": technology,
                "topology": r.topology,
                "repetitions": r.repetitions,
                "relay_boxes": r.relay_boxes,
                "water_hops": r.hop_count,
                "physical_nodes": r.physical_nodes,
                "unique_modems": r.unique_modems,
                "hop_length_m": r.hop_length_m,
                "frame_s": r.frame_s,
                "pdr": r.pdr_mean,
                "pdr_ci95": r.pdr_ci95,
                "delay_s": r.delay_mean_s_mean,
                "delay_ci95": r.delay_mean_s_ci95,
                "goodput_bps": r.goodput_bps_mean,
                "energy_active_uj_per_bit": active,
                "energy_idle_uj_per_bit": idle,
                "energy_total_uj_per_bit": total,
            })
    return pd.DataFrame(rows)
