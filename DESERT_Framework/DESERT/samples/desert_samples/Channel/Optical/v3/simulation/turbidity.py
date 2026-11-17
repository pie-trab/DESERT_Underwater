#!/usr/bin/env python3
"""Turbidity check for the dual-head chain.

The single-link calibration is PHY-level and therefore identical to v2; this
stage copies v2's calibration table and reruns the 1,000 m chain at the three
representative turbidity values with both optical node models.
"""

from __future__ import annotations

import math
import shutil

import pandas as pd

import core

C_VALUES = (0.1, 0.3, 0.5)
DISTANCE = 1000.0
REPETITIONS = 5
STOP_TIME = 100.0


def ensure_calibration() -> pd.DataFrame:
    target = core.FINAL / "calibration.csv"
    if not target.exists():
        source = core.V3.parent / "v2" / "simulation" / "data" / "final" / "calibration.csv"
        if not source.exists():
            raise FileNotFoundError(
                "v2 calibration.csv not found; run v2 turbidity calibration")
        shutil.copyfile(source, target)
    return pd.read_csv(target).drop_duplicates("water_c")


def make_case(technology: str, water_c: float, working_hop: float,
              repetition: int) -> dict:
    hops = int(math.ceil(DISTANCE / working_hop))
    case = dict(core.BASE)
    case.update({
        "technology": technology,
        "total_distance": DISTANCE,
        "n_relays": hops - 1,
        "hop_count": hops,
        "hop_length": DISTANCE / hops,
        "water_c": water_c,
        "attenuation_scale": water_c / 0.3,
        "cbr_period": core.BASE["cbr_period"],
        "packet_size": core.BASE["packet_size"],
        "depth": core.BASE["depth"],
        "stop_time": STOP_TIME,
        "rngstream": repetition,
        "poisson_traffic": 1,
    })
    return case


def run() -> None:
    calibration = ensure_calibration()
    cases = []
    for _, cal in calibration.iterrows():
        c = float(cal.water_c)
        if c not in C_VALUES:
            continue
        working = float(cal.working_hop_m)
        for technology in ("optical", "optical_dual"):
            for r in range(1, REPETITIONS + 1):
                cases.append(make_case(technology, c, working, r))
    raw = core.execute_cases(cases, core.RAW / "turbidity", "results.csv")
    raw.to_csv(core.FINAL / "turbidity_runs.csv", index=False)
    summary = core.summarize(raw)
    summary.to_csv(core.FINAL / "turbidity_summary.csv", index=False)
    columns = ["technology", "topology", "water_c", "distance_m",
               "hop_length_m", "hop_count", "unique_modems", "pdr_mean",
               "delay_mean_s_mean", "energy_per_bit_uj_mean"]
    print(summary[columns].to_string(index=False))


if __name__ == "__main__":
    run()
