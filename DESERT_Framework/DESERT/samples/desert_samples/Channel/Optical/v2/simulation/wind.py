#!/usr/bin/env python3
"""Acoustic wind-speed sensitivity around the direct-link baseline."""

from __future__ import annotations

import math

import core


DISTANCES = (500.0, 1000.0, 1500.0)
DISTANCES_STEP = (1500.0,)
WINDSPEEDS = (0.0, 5.0, 10.0, 15.0, 20.0)
WINDSPEEDS_STEP = tuple(float(w) for w in range(5, 15))
PHASE = {"pilot": (2, 20.0), "main": (10, 100.0),
         "step": (10, 100.0)}


def make_case(distance: float, windspeed: float, repetition: int,
              stop_time: float) -> dict:
    case = dict(core.BASE)
    case.update({
        "technology": "acoustic",
        "total_distance": distance,
        "n_relays": 0,
        "hop_count": 1,
        "hop_length": distance,
        "water_c": math.nan,
        "windspeed": windspeed,
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
    step = phase == "step"
    distances = DISTANCES_STEP if step else DISTANCES
    speeds = WINDSPEEDS_STEP if step else WINDSPEEDS
    cases = [make_case(d, w, r, stop_time)
             for d in distances
             for w in speeds
             for r in range(1, repetitions + 1)]
    raw = core.execute_cases(cases, core.RAW / "wind" / phase, "results.csv")
    if phase in ("main", "step"):
        suffix = "_step" if step else ""
        raw.to_csv(core.FINAL / f"wind{suffix}_runs.csv", index=False)
        summary = core.summarize(raw)
        summary.to_csv(core.FINAL / f"wind{suffix}_summary.csv", index=False)
    print(f"wind {phase}: {len(raw)} runs")
