#!/usr/bin/env python3
"""High-replication validation for the long-distance headline cells."""

from __future__ import annotations

import core
import distance


DISTANCES = (1000.0, 1500.0)
REPETITIONS = 25
STOP_TIME = 100.0


def run() -> None:
    cases = [distance.make_case(technology, d, r, STOP_TIME)
             for d in DISTANCES
             for technology in ("acoustic", "optical")
             for r in range(1, REPETITIONS + 1)]
    raw = core.execute_cases(cases, core.RAW / "replication", "results.csv")
    raw.to_csv(core.FINAL / "replication_runs.csv", index=False)
    summary = core.summarize(raw)
    summary.to_csv(core.FINAL / "replication_summary.csv", index=False)
    columns = ["technology", "distance_m", "repetitions", "pdr_mean",
               "pdr_ci95", "delay_mean_s_mean", "delay_mean_s_ci95",
               "energy_per_bit_uj_mean"]
    print(summary[columns].to_string(index=False))


if __name__ == "__main__":
    run()
