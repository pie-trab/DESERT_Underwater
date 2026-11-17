#!/usr/bin/env python3
"""Analytical energy comparison: single-head versus dual-head optical."""

from __future__ import annotations

import pandas as pd

import core

TX_W = 10.0
RX_W = 1.5
IDLE_SCENARIOS = (0.0, 0.5, 1.5, 3.0)
POWER_SCALES = (0.5, 1.0, 1.5)


def run() -> None:
    runs = pd.read_csv(core.FINAL / "distance_runs.csv")
    runs = runs[(~runs.failed) & (runs.technology.isin(
        ("optical", "optical_dual")))]
    rows = []
    for (technology, topology, distance), group in runs.groupby(
            ["technology", "topology", "total_distance"]):
        delivered_bits = (group.delivered_packets * group.packet_size * 8.0)
        total_bits = delivered_bits.sum()
        if total_bits <= 0:
            continue
        tx_events = group.tx_events.sum()
        rx_events = group.rx_events.sum()
        airtime = group.timing_airtime_s.mean()
        modems = group.unique_modems.iloc[0]
        mission = core.BASE["stop_time"] - core.BASE["start_time"]
        for scale in POWER_SCALES:
            active = ((tx_events * TX_W * scale + rx_events * RX_W * scale)
                      * airtime / total_bits * 1e6)
            for idle_w in IDLE_SCENARIOS:
                idle = modems * idle_w * mission / total_bits * 1e6
                rows.append({
                    "technology": technology,
                    "topology": topology,
                    "distance_m": distance,
                    "unique_modems": modems,
                    "power_scale": scale,
                    "idle_w_per_modem": idle_w,
                    "tx_w": TX_W * scale,
                    "rx_w": RX_W * scale,
                    "energy_active_uj_per_bit": active,
                    "energy_idle_uj_per_bit": idle,
                    "energy_total_uj_per_bit": active + idle,
                })
    table = pd.DataFrame(rows)
    table.to_csv(core.FINAL / "energy_sensitivity.csv", index=False)

    baseline = table[(table.power_scale == 1.0)
                     & (table.idle_w_per_modem == 1.5)]
    print(baseline[["technology", "topology", "distance_m", "unique_modems",
                    "energy_active_uj_per_bit", "energy_idle_uj_per_bit",
                    "energy_total_uj_per_bit"]].to_string(index=False))


if __name__ == "__main__":
    run()
