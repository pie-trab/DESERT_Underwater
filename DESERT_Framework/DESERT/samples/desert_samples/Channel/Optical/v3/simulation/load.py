#!/usr/bin/env python3
"""Offered-load sweep: acoustic baseline and single/dual-head optical chains."""

from __future__ import annotations

import core
import distance


DISTANCES = (1000.0, 1500.0)
CBR_PERIODS = (5.0, 2.0, 1.0, 0.5, 0.2, 0.1)
REPETITIONS = 10
STOP_TIME = 100.0


def run() -> None:
    cases = []
    for period in CBR_PERIODS:
        for d in DISTANCES:
            for technology in ("acoustic", "optical", "optical_dual"):
                for r in range(1, REPETITIONS + 1):
                    case = distance.make_case(technology, d, r, STOP_TIME)
                    case["cbr_period"] = period
                    cases.append(case)
    raw = core.execute_cases(cases, core.RAW / "load", "results.csv")
    raw.to_csv(core.FINAL / "load_runs.csv", index=False)
    summary = core.summarize(raw)
    summary.to_csv(core.FINAL / "load_summary.csv", index=False)
    columns = ["technology", "topology", "distance_m", "cbr_period",
               "repetitions", "pdr_mean", "goodput_bps_mean",
               "delay_mean_s_mean", "energy_per_bit_uj_mean",
               "unique_modems"]
    print(summary[columns].to_string(index=False))


if __name__ == "__main__":
    run()
