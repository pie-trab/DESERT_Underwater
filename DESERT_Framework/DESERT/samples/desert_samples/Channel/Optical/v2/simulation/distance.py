#!/usr/bin/env python3
"""Distance sweep: direct acoustic versus distance-scaled optical."""

from __future__ import annotations

import math

import core


DISTANCES = (50.0, 100.0, 200.0, 500.0, 1000.0, 1500.0)
OPTICAL_HOP_M = 20.0
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
    if technology == "optical":
        hops = int(math.ceil(distance / OPTICAL_HOP_M))
        case["n_relays"] = hops - 1
        case["hop_count"] = hops
        case["hop_length"] = distance / hops
    else:
        case["n_relays"] = 0
        case["hop_count"] = 1
        case["hop_length"] = distance
    return case


def run(phase: str) -> None:
    repetitions, stop_time = PHASE[phase]
    cases = []
    for distance in DISTANCES:
        for technology in ("acoustic", "optical"):
            for repetition in range(1, repetitions + 1):
                cases.append(make_case(technology, distance, repetition,
                                       stop_time))
    out_dir = core.RAW / "distance" / phase
    raw = core.execute_cases(cases, out_dir, "results.csv")
    if phase == "main":
        raw.to_csv(core.FINAL / "distance_runs.csv", index=False)
        summary = core.summarize(raw)
        summary.to_csv(core.FINAL / "distance_summary.csv", index=False)
    print(f"distance {phase}: {len(raw)} runs")
