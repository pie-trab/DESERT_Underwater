#!/usr/bin/env python3
"""Check whether the beam-pattern/LUT mode changes the v2 distance results."""

from __future__ import annotations

import math

import numpy as np
import pandas as pd

import core


DISTANCES = (100.0, 500.0, 1000.0, 1500.0)
BEAM_MODES = (0, 1)
REPETITIONS = 3
STOP_TIME = 100.0


def make_case(distance: float, beam_mode: int, repetition: int) -> dict:
    hops = int(math.ceil(distance / 20.0))
    case = dict(core.BASE)
    case.update({
        "technology": "optical",
        "total_distance": distance,
        "n_relays": hops - 1,
        "hop_count": hops,
        "hop_length": distance / hops,
        "water_c": core.BASE["attenuation_c"],
        "attenuation_scale": 1.0,
        "beam_mode": beam_mode,
        "cbr_period": core.BASE["cbr_period"],
        "packet_size": core.BASE["packet_size"],
        "depth": core.BASE["depth"],
        "stop_time": STOP_TIME,
        "rngstream": repetition,
        "poisson_traffic": 1,
    })
    return case


def run() -> None:
    cases = [make_case(d, b, r)
             for d in DISTANCES
             for b in BEAM_MODES
             for r in range(1, REPETITIONS + 1)]
    raw = core.execute_cases(cases, core.RAW / "beam_check", "results.csv")
    good = raw[~raw.failed].copy()
    summary = good.groupby(["total_distance", "beam_mode"], as_index=False).agg(
        repetitions=("rngstream", "count"),
        hop_count=("hop_count", "first"),
        unique_modems=("unique_modems", "first"),
        pdr_mean=("pdr", "mean"),
        delay_mean_s=("delay_mean_s", "mean"),
        energy_per_bit_uj=("energy_per_bit_uj", "mean"),
    )
    pivot = summary.pivot(index="total_distance", columns="beam_mode")
    summary["delta_pdr"] = summary.apply(
        lambda row: abs(row.pdr_mean
                        - pivot.loc[row.total_distance, ("pdr_mean", 0)]),
        axis=1)
    summary["delta_delay_s"] = summary.apply(
        lambda row: abs(row.delay_mean_s
                        - pivot.loc[row.total_distance, ("delay_mean_s", 0)]),
        axis=1)
    summary["identical_to_plain"] = (
        (summary.delta_pdr < 1e-12)
        & (summary.delta_delay_s < 1e-12))
    summary.to_csv(core.FINAL / "beam_check.csv", index=False)
    print(summary.to_string(index=False))


if __name__ == "__main__":
    run()
