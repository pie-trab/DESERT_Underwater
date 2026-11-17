#!/usr/bin/env python3
"""Optical guard-time and hop-margin sensitivity at 1,000 m."""

from __future__ import annotations

import math

import pandas as pd

import core


DISTANCE = 1000.0
BASE_HOP = 20.0
GUARDS = (0.0001, 0.001, 0.005)
MARGINS = (0.8, 0.9, 1.0)
MAX_HOP = 25.0
REPETITIONS = 10
STOP_TIME = 100.0


def make_case(hop: float, repetition: int, guard: float = 0.001,
              tag: str = "") -> dict:
    hops = int(math.ceil(DISTANCE / hop))
    case = dict(core.BASE)
    case.update({
        "technology": "optical",
        "total_distance": DISTANCE,
        "n_relays": hops - 1,
        "hop_count": hops,
        "hop_length": DISTANCE / hops,
        "water_c": core.BASE["attenuation_c"],
        "attenuation_scale": 1.0,
        "optical_guard": guard,
        "cbr_period": core.BASE["cbr_period"],
        "packet_size": core.BASE["packet_size"],
        "depth": core.BASE["depth"],
        "stop_time": STOP_TIME,
        "rngstream": repetition,
        "poisson_traffic": 1,
        "tag": tag,
    })
    return case


def summarize(raw: pd.DataFrame, group: str) -> pd.DataFrame:
    good = raw[~raw.failed].copy()
    rows = []
    for key, part in good.groupby(group, dropna=False):
        rows.append({
            group: key,
            "repetitions": len(part),
            "hop_length_m": part.hop_length.iloc[0],
            "unique_modems": part.unique_modems.iloc[0],
            "frame_s": part.timing_frame_s.iloc[0],
            "ceiling_bps": 1000.0 / part.timing_frame_s.iloc[0],
            "pdr_mean": part.pdr.mean(),
            "pdr_ci95": core.ci95(part.pdr),
            "delay_mean_s": part.delay_mean_s.mean(),
            "delay_ci95_s": core.ci95(part.delay_mean_s),
            "energy_per_bit_uj": part.energy_per_bit_uj.mean(),
        })
    return pd.DataFrame(rows).sort_values(group)


def run() -> None:
    guard_cases = [make_case(BASE_HOP, r, guard=g, tag=f"guard{g:g}")
                   for g in GUARDS
                   for r in range(1, REPETITIONS + 1)]
    guard_raw = core.execute_cases(
        guard_cases, core.RAW / "guard", "results.csv")
    guard = summarize(guard_raw, "optical_guard")
    guard.to_csv(core.FINAL / "guard_summary.csv", index=False)
    print("GUARD")
    print(guard.to_string(index=False))

    margin_cases = [make_case(MAX_HOP * m, r, tag=f"margin{m:g}")
                    for m in MARGINS
                    for r in range(1, REPETITIONS + 1)]
    margin_raw = core.execute_cases(
        margin_cases, core.RAW / "hop_margin", "results.csv")
    margin = summarize(margin_raw, "hop_length")
    margin["margin"] = margin.hop_length_m / MAX_HOP
    margin.to_csv(core.FINAL / "hop_margin_summary.csv", index=False)
    print("HOP MARGIN")
    print(margin.to_string(index=False))


if __name__ == "__main__":
    run()
