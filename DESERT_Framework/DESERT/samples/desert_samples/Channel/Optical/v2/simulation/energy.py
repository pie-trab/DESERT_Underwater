#!/usr/bin/env python3
"""Analytical energy sensitivity from saved distance-run counters."""

from __future__ import annotations

import math

import pandas as pd

import core


ACOUSTIC_TX_W = 20.0
ACOUSTIC_RX_W = 4.0
OPTICAL_TX_W = 10.0
OPTICAL_RX_W = 1.5


def energy_value(row, tx_w: float, rx_w: float) -> float:
    delivered_bits = row.delivered_packets * row.packet_size * 8.0
    if delivered_bits <= 0 or not math.isfinite(row.timing_airtime_s):
        return math.nan
    return ((row.tx_events * tx_w + row.rx_events * rx_w)
            * row.timing_airtime_s / delivered_bits * 1e6)


def run() -> pd.DataFrame:
    raw = pd.read_csv(core.FINAL / "distance_runs.csv")
    rows = []
    for _, row in raw.iterrows():
        if row.technology == "acoustic":
            tx, rx = ACOUSTIC_TX_W, ACOUSTIC_RX_W
        else:
            tx, rx = OPTICAL_TX_W, OPTICAL_RX_W
        f = row.total_distance / 1000.0
        alpha = (0.11 * 50**2 / (1 + 50**2)
                 + 44 * 50**2 / (4100 + 50**2)
                 + 2.75e-4 * 50**2 + 0.003)
        scaled_tx = (ACOUSTIC_TX_W * (row.total_distance / 50.0) ** 2
                     * 10 ** (alpha * (f - 0.05) / 10.0))
        rows.append({
            "technology": row.technology,
            "distance_m": row.total_distance,
            "baseline_uj_bit": energy_value(row, tx, rx),
            "band_min_uj_bit": energy_value(row, tx * 0.5, rx * 0.5),
            "band_max_uj_bit": energy_value(row, tx * 1.5, rx * 1.5),
            "scaled_acoustic_uj_bit": (
                energy_value(row, scaled_tx, rx)
                if row.technology == "acoustic" else math.nan),
            "tx_events": row.tx_events,
            "rx_events": row.rx_events,
            "airtime_s": row.timing_airtime_s,
            "delivered_packets": row.delivered_packets,
        })
    data = pd.DataFrame(rows)
    grouped = []
    for (technology, distance), group in data.groupby(
            ["technology", "distance_m"]):
        item = {"technology": technology, "distance_m": distance}
        for column in ("baseline_uj_bit", "band_min_uj_bit",
                       "band_max_uj_bit", "scaled_acoustic_uj_bit"):
            item[f"{column}_mean"] = group[column].mean()
            item[f"{column}_ci95"] = core.ci95(group[column])
        grouped.append(item)
    result = pd.DataFrame(grouped).sort_values(["distance_m", "technology"])
    result.to_csv(core.FINAL / "energy_sensitivity.csv", index=False)

    def crossover(a: pd.Series, b: pd.Series, distances: pd.Series):
        delta = (a - b).to_numpy()
        x = distances.to_numpy()
        for i in range(len(x) - 1):
            if delta[i] == 0:
                return float(x[i])
            if delta[i] * delta[i + 1] < 0:
                return float(x[i] + (x[i + 1] - x[i])
                             * (-delta[i]) / (delta[i + 1] - delta[i]))
        return None

    pivot = result.pivot(index="distance_m", columns="technology")
    distances = pivot.index.to_series()
    cases = {
        "baseline": (pivot["baseline_uj_bit_mean"]["acoustic"],
                     pivot["baseline_uj_bit_mean"]["optical"]),
        "band_acoustic_min_optical_max": (
            pivot["band_min_uj_bit_mean"]["acoustic"],
            pivot["band_max_uj_bit_mean"]["optical"]),
        "band_acoustic_max_optical_min": (
            pivot["band_max_uj_bit_mean"]["acoustic"],
            pivot["band_min_uj_bit_mean"]["optical"]),
        "scaled_acoustic": (
            pivot["scaled_acoustic_uj_bit_mean"]["acoustic"],
            pivot["baseline_uj_bit_mean"]["optical"]),
    }
    cross = []
    for name, (acoustic, optical_) in cases.items():
        value = crossover(acoustic, optical_, distances)
        cross.append({
            "case": name,
            "crossover_distance_m": value,
            "result": "none in swept range" if value is None else "interpolated",
        })
    pd.DataFrame(cross).to_csv(core.FINAL / "energy_crossovers.csv",
                               index=False)
    print(f"energy sensitivity: {len(result)} points")
    return result
