#!/usr/bin/env python3
"""Acoustic equal-hop diagnostic chain."""

from __future__ import annotations

import math

import core


DISTANCES = (50.0, 100.0, 200.0, 500.0, 1000.0, 1500.0)
OPTICAL_HOP_M = 20.0
PHASE = {"pilot": (2, 20.0), "main": (10, 100.0)}


def make_case(distance: float, repetition: int, stop_time: float) -> dict:
    hops = int(math.ceil(distance / OPTICAL_HOP_M))
    case = dict(core.BASE)
    case.update({
        "technology": "acoustic_chain",
        "total_distance": distance,
        "n_relays": hops - 1,
        "hop_count": hops,
        "hop_length": distance / hops,
        "water_c": math.nan,
        "cbr_period": core.BASE["cbr_period"],
        "packet_size": core.BASE["packet_size"],
        "depth": core.BASE["depth"],
        "stop_time": stop_time,
        "rngstream": repetition,
        "poisson_traffic": 1,
    })
    return case


def run(phase: str) -> None:
    repetitions, stop_time = PHASE[phase]
    cases = [make_case(d, r, stop_time)
             for d in DISTANCES
             for r in range(1, repetitions + 1)]
    raw = core.execute_cases(cases, core.RAW / "diagnostic" / phase,
                             "results.csv")
    if phase == "main":
        raw.to_csv(core.FINAL / "diagnostic_runs.csv", index=False)
        summary = core.summarize(raw)
        summary["artifact_note"] = (
            "PDR losses localize to the first hop; mechanism unresolved")
        summary.to_csv(core.FINAL / "diagnostic_summary.csv", index=False)
    print(f"diagnostic {phase}: {len(raw)} runs")
