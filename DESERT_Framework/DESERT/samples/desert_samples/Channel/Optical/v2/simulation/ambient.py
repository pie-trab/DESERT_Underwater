#!/usr/bin/env python3
"""Ambient-light pilot for the plain optical PHY.

The LUT gives E0(depth).  The PHY takes an ambient photocurrent Il, so this
pilot uses Il = E0 * S * Ar for the 5 m, 10 m and 20 m LUT values.
"""

from __future__ import annotations

import math

import pandas as pd

import core


HOPS = (20.0, 25.0)
IL_VALUES = {
    "5m": 7.895e-6,
    "10m": 4.915e-7,
    "20m": 1.934e-9,
}
REPETITIONS = 10
STOP_TIME = 100.0


def make_case(hop: float, il: float, repetition: int) -> dict:
    case = dict(core.BASE)
    case.update({
        "technology": "optical",
        "total_distance": hop,
        "n_relays": 0,
        "hop_count": 1,
        "hop_length": hop,
        "water_c": core.BASE["attenuation_c"],
        "attenuation_scale": 1.0,
        "optical_il": il,
        "cbr_period": core.BASE["cbr_period"],
        "packet_size": core.BASE["packet_size"],
        "depth": core.BASE["depth"],
        "stop_time": STOP_TIME,
        "rngstream": repetition,
        "poisson_traffic": 1,
    })
    return case


def run() -> None:
    cases = [make_case(hop, il, r)
             for hop in HOPS
             for il in IL_VALUES.values()
             for r in range(1, REPETITIONS + 1)]
    raw = core.execute_cases(cases, core.RAW / "ambient", "results.csv")
    good = raw[~raw.failed].copy()
    rows = []
    for (hop, il), group in good.groupby(["total_distance", "optical_il"],
                                         dropna=False):
        label = next(name for name, value in IL_VALUES.items()
                     if math.isclose(value, il, rel_tol=1e-6))
        rows.append({
            "hop_m": hop,
            "il_a": il,
            "equivalent_depth": label,
            "repetitions": len(group),
            "pdr_mean": group.pdr.mean(),
            "pdr_ci95": core.ci95(group.pdr),
            "delay_mean_s": group.delay_mean_s.mean(),
            "delay_ci95_s": core.ci95(group.delay_mean_s),
            "energy_per_bit_uj": group.energy_per_bit_uj.mean(),
            "energy_ci95_uj": core.ci95(group.energy_per_bit_uj),
        })
    summary = pd.DataFrame(rows).sort_values(["hop_m", "il_a"])
    summary.to_csv(core.FINAL / "ambient_summary.csv", index=False)
    print(summary.to_string(index=False))


if __name__ == "__main__":
    run()
