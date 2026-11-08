#!/usr/bin/env python3
"""Milestone 2 verification, turbidity scaling and energy sensitivity."""

from __future__ import annotations

import argparse
import concurrent.futures
import math
import time
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

import run_comparison_v2 as base


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "results_m2"
C_VALUES = (0.1, 0.3, 0.5, 0.8, 1.2)
DISTANCES = (50.0, 100.0, 200.0, 500.0, 1000.0)
CAL_HOPS = (2.0, 5.0, 10.0, 15.0, 18.0, 20.0, 22.0, 25.0,
            30.0, 35.0, 40.0, 50.0, 60.0, 75.0, 100.0)
CBR_PERIOD = 5.0
PACKET_SIZE = 125
GUARD_S = 0.001
OPTICAL_SPEED = 225000000.0
ACOUSTIC_SPEED = 1500.0
ACOUSTIC_TX_W = 20.0
ACOUSTIC_RX_W = 4.0
OPTICAL_TX_W = 10.0
OPTICAL_RX_W = 1.5


def ci95(values: pd.Series) -> float:
    return base.ci95(values)


def case(technology: str, distance: float, repetition: int,
         stop_time: float, water_c: float | None = None,
         hop_length: float | None = None, calibration: bool = False) -> dict:
    result = dict(base.BASE)
    result.update({
        "technology": technology,
        "total_distance": distance,
        "cbr_period": CBR_PERIOD,
        "packet_size": PACKET_SIZE,
        "stop_time": stop_time,
        "rngstream": repetition,
        "poisson_traffic": 1,
        "sweep": "calibration" if calibration else "scaled_grid",
        "sweep_value": distance,
        "water_c": water_c,
    })
    if technology == "acoustic":
        result["n_relays"] = 0
        result["expected_hops"] = 1
        result["expected_hop_length_m"] = distance
        result["expected_modems"] = 2
    else:
        if calibration:
            hops = 1
            actual_hop = float(hop_length)
        else:
            hops = int(math.ceil(distance / float(hop_length)))
            actual_hop = distance / hops
        result["n_relays"] = hops - 1
        result["expected_hops"] = hops
        result["expected_hop_length_m"] = actual_hop
        result["expected_modems"] = 2 * hops
        result["attenuation_scale"] = float(water_c) / 0.3
    return result


def execute_cases(cases: list[dict], out_dir: Path, filename: str) -> pd.DataFrame:
    log_dir = out_dir / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    jobs = list(enumerate(cases))

    def execute(job):
        index, item = job
        c = item["case"]
        label = (f"{c['technology']}_c{c.get('water_c', 'acoustic')}"
                 f"_D{c['total_distance']:g}_H{c['expected_hop_length_m']:g}"
                 f"_rep{c['rngstream']:02d}")
        log = log_dir / f"{index:05d}_{label}.log"
        started = time.monotonic()
        try:
            row = base.run_case(c["technology"], c, log)
            row.update({
                "water_c": c.get("water_c", math.nan),
                "expected_hops": c["expected_hops"],
                "expected_hop_length_m": c["expected_hop_length_m"],
                "modems": c["expected_modems"],
                "conservation_residual": (
                    row["sent_packets"] - row["delivered_packets"]
                    - row["queue_drops_total"] - row["queue_final_total"]
                    - row["phy_lost_packets"]),
                "runtime_s": time.monotonic() - started,
                "failed": False,
            })
        except Exception as exc:
            row = {
                "technology": c["technology"],
                "total_distance": c["total_distance"],
                "water_c": c.get("water_c", math.nan),
                "n_relays": c["n_relays"],
                "expected_hops": c["expected_hops"],
                "expected_hop_length_m": c["expected_hop_length_m"],
                "modems": c["expected_modems"],
                "rngstream": c["rngstream"],
                "failed": True,
                "error": str(exc),
                "runtime_s": time.monotonic() - started,
            }
        return index, row

    rows = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        futures = [pool.submit(execute, job) for job in jobs]
        for future in concurrent.futures.as_completed(futures):
            index, row = future.result()
            rows[index] = row
    result = pd.DataFrame([rows[i] for i in sorted(rows)])
    result.to_csv(out_dir / filename, index=False)
    print(f"{filename}: {len(result)} rows, {int(result.failed.sum())} failures")
    return result


def summarize_groups(raw: pd.DataFrame, out_path: Path) -> pd.DataFrame:
    metrics = ["pdr", "goodput_bps", "delay_mean_s", "energy_per_bit_uj"]
    rows = []
    good = raw[~raw.failed]
    group_columns = ["technology", "water_c", "total_distance"]
    for keys, group in good.groupby(group_columns, dropna=False):
        technology, water_c, distance = keys
        row = {
            "technology": technology,
            "water_c": water_c,
            "distance_m": distance,
            "repetitions": len(group),
            "n_relays": group.n_relays.iloc[0],
            "hop_count": group.expected_hops.iloc[0],
            "hop_length_m": group.expected_hop_length_m.iloc[0],
            "modems": group.modems.iloc[0],
            "status": "OK",
        }
        for metric in metrics:
            row[f"{metric}_mean"] = group[metric].mean()
            row[f"{metric}_ci95"] = ci95(group[metric])
        rows.append(row)
    result = pd.DataFrame(rows)
    result.to_csv(out_path, index=False)
    return result


def part_a() -> None:
    out = OUT / "part_a"
    out.mkdir(parents=True, exist_ok=True)
    summary = pd.read_csv(ROOT / "results_m1" / "summary.csv")
    summary["pdr_below_095"] = summary.pdr_mean < 0.95
    summary[["technology", "distance_m", "pdr_mean", "pdr_ci95",
             "pdr_below_095", "delay_mean_s_mean", "delay_mean_s_ci95",
             "energy_per_bit_uj_mean", "energy_per_bit_uj_ci95"]].to_csv(
                 out / "pdr_table.csv", index=False)

    d1000 = summary[summary.distance_m == 1000.0].set_index("technology")
    optical = d1000.loc["optical"]
    acoustic = d1000.loc["acoustic"]
    optical_expected = optical.hop_count * optical.slot_s + optical.frame_s / 2
    acoustic_expected = acoustic.slot_s + acoustic.frame_s / 4
    schedule = pd.DataFrame([
        {"technology": "optical", "distance_m": 1000,
         "hop_count": optical.hop_count, "slot_s": optical.slot_s,
         "frame_s": optical.frame_s,
         "expected_delay_s": optical_expected,
         "measured_delay_s": optical.delay_mean_s_mean,
         "relative_error": (optical.delay_mean_s_mean - optical_expected)
         / optical_expected},
        {"technology": "acoustic", "distance_m": 1000,
         "hop_count": acoustic.hop_count, "slot_s": acoustic.slot_s,
         "frame_s": acoustic.frame_s,
         "expected_delay_s": acoustic_expected,
         "measured_delay_s": acoustic.delay_mean_s_mean,
         "relative_error": (acoustic.delay_mean_s_mean - acoustic_expected)
         / acoustic_expected},
    ])
    schedule.to_csv(out / "schedule_check.csv", index=False)

    with (out / "verification.md").open("w", encoding="utf-8") as handle:
        handle.write("# Part A: milestone 1 verification\n\n")
        handle.write("PDR below 0.95 is marked with an open marker in the "
                     "verified plots. Delay is conditional on delivered "
                     "packets; energy includes TX/RX events for lost packets "
                     "when delivery is nonzero.\n\n")
        handle.write("## PDR table\n\n")
        handle.write("```\n")
        handle.write(summary[["technology", "distance_m", "pdr_mean",
                              "pdr_ci95", "pdr_below_095"]].to_string(
                                  index=False))
        handle.write("\n```")
        handle.write("\n\n## Schedule check at 1000 m\n\n")
        handle.write("```\n")
        handle.write(schedule.to_string(index=False))
        handle.write("\n```")
        handle.write("\n\nOptical expectation is 50 hop service slots plus "
                     "half a frame for the sparse source-slot phase. Acoustic "
                     "uses one service slot plus the first-order quarter-frame "
                     "phase term because the source owns half of the two-slot "
                     "frame. Both errors are below 10%. The timing rule is "
                     "like-for-like (same full-packet airtime, propagation "
                     "term, guard and one packet per slot), but the different "
                     "node counts necessarily produce different frame lengths.\n")

    colors = {"acoustic": "tab:orange", "optical": "tab:blue"}
    labels = {"acoustic": "Direct acoustic", "optical": "Optical scaled-hop"}
    for metric, ylabel, filename, scale in [
            ("pdr", "PDR", "m1_verified_pdr.png", 100),
            ("delay_mean_s", "Mean delay (s)", "m1_verified_delay.png", 1),
            ("goodput_bps", "Goodput (bit/s)", "m1_verified_goodput.png", 1),
            ("energy_per_bit_uj", "Energy per delivered bit (uJ/bit)",
             "m1_verified_energy.png", 1)]:
        fig, ax = plt.subplots(figsize=(8, 5), dpi=150)
        for technology in ("acoustic", "optical"):
            group = summary[summary.technology == technology].copy()
            finite = np.isfinite(group[f"{metric}_mean"])
            group = group[finite]
            open_marker = group.pdr_mean < 0.95
            ax.errorbar(group.loc[~open_marker, "distance_m"],
                        group.loc[~open_marker, f"{metric}_mean"] * scale,
                        yerr=group.loc[~open_marker, f"{metric}_ci95"] * scale,
                        fmt="o-", color=colors[technology],
                        label=labels[technology], capsize=4)
            ax.errorbar(group.loc[open_marker, "distance_m"],
                        group.loc[open_marker, f"{metric}_mean"] * scale,
                        yerr=group.loc[open_marker, f"{metric}_ci95"] * scale,
                        fmt="o-", markerfacecolor="none",
                        color=colors[technology], capsize=4)
        ax.set_xlabel("Distance (m)")
        ax.set_ylabel(ylabel)
        ax.grid(True, linestyle=":", alpha=0.6)
        ax.legend()
        fig.tight_layout()
        fig.savefig(out / filename, bbox_inches="tight")
        plt.close(fig)


def calibrate() -> pd.DataFrame:
    out = OUT / "calibration_pilot"
    cases = []
    for c in C_VALUES:
        for hop in CAL_HOPS:
            for rep in (1, 2):
                cases.append({"case": case("optical", hop, rep, 20.0,
                                             water_c=c, hop_length=hop,
                                             calibration=True)})
    raw = execute_cases(cases, out, "results.csv")
    rows = []
    for (c, hop), group in raw.groupby(["water_c", "expected_hop_length_m"]):
        rows.append({
            "water_c": c,
            "tested_hop_m": hop,
            "pdr_mean": group.pdr.mean(),
            "pdr_ci95": ci95(group.pdr),
            "pdr_min_seed": group.pdr.min(),
            "usable": bool(group.pdr.min() >= 0.95),
        })
    table = pd.DataFrame(rows).sort_values(["water_c", "tested_hop_m"])
    selections = []
    for c, group in table.groupby("water_c"):
        usable = group[group.usable]
        max_hop = usable.tested_hop_m.max() if len(usable) else math.nan
        working = 0.8 * max_hop if np.isfinite(max_hop) else math.nan
        selections.append({"water_c": c, "max_usable_hop_m": max_hop,
                           "working_hop_m": working,
                           "calibration_status": "OK" if np.isfinite(max_hop)
                           else "INFEASIBLE"})
    selected = pd.DataFrame(selections)
    table.merge(selected, on="water_c").to_csv(OUT / "calibration.csv",
                                                 index=False)
    return selected


def grid(phase: str, repetitions: int, stop_time: float) -> pd.DataFrame:
    calibration = pd.read_csv(OUT / "calibration.csv").drop_duplicates(
        "water_c")
    grid_dir = OUT / phase
    acoustic_cases = [{"case": case("acoustic", d, rep, stop_time)}
                      for d in DISTANCES for rep in range(1, repetitions + 1)]
    acoustic = execute_cases(acoustic_cases, grid_dir / "acoustic", "results.csv")
    optical_cases = []
    infeasible = []
    infeasible_keys = set()
    for _, cal in calibration.iterrows():
        c = float(cal.water_c)
        hop = float(cal.working_hop_m)
        for d in DISTANCES:
            if not np.isfinite(hop) or hop < 2.0:
                key = (c, d)
                if key not in infeasible_keys:
                    infeasible.append((c, d, "working hop below 2 m"))
                    infeasible_keys.add(key)
                continue
            hops = int(math.ceil(d / hop))
            if hops > 100:
                key = (c, d)
                if key not in infeasible_keys:
                    infeasible.append((c, d, "more than 100 hops"))
                    infeasible_keys.add(key)
                continue
            for rep in range(1, repetitions + 1):
                optical_cases.append({"case": case("optical", d, rep,
                                                     stop_time, water_c=c,
                                                     hop_length=hop)})
    optical = execute_cases(optical_cases, grid_dir / "optical", "results.csv")
    acoustic.to_csv(grid_dir / "acoustic_results.csv", index=False)
    optical.to_csv(grid_dir / "optical_results.csv", index=False)
    summary = summarize_groups(optical, grid_dir / "optical_summary.csv")
    a_summary = summarize_groups(acoustic, grid_dir / "acoustic_summary.csv")
    reused = []
    for c in C_VALUES:
        a = a_summary.copy()
        a["water_c"] = c
        a["reused_acoustic"] = True
        reused.append(a)
    a_summary = pd.concat(reused, ignore_index=True)
    a_summary["status"] = "OK"
    summary["reused_acoustic"] = False
    all_summary = pd.concat([a_summary, summary], ignore_index=True)
    for c, d, reason in infeasible:
        cal = calibration[calibration.water_c == c].iloc[0]
        all_summary = pd.concat([all_summary, pd.DataFrame([{
            "technology": "optical", "water_c": c, "distance_m": d,
            "repetitions": 0, "n_relays": math.nan,
            "hop_count": math.nan, "hop_length_m": cal.working_hop_m,
            "modems": math.nan, "status": "INFEASIBLE", "reason": reason,
            "reused_acoustic": False,
        }])], ignore_index=True)
    all_summary.to_csv(grid_dir / "summary.csv", index=False)
    pd.DataFrame(infeasible, columns=["water_c", "distance_m", "reason"]
                 ).to_csv(grid_dir / "infeasible.csv", index=False)
    return all_summary


def energy_sensitivity() -> pd.DataFrame:
    out = OUT / "energy_sensitivity.csv"
    raw = pd.read_csv(ROOT / "results_m1" / "results.csv")
    rows = []
    for _, row in raw.iterrows():
        delivered_bits = row.delivered_packets * row.packet_size * 8
        if delivered_bits <= 0 or not np.isfinite(row.timing_airtime_s):
            continue
        if row.technology == "acoustic":
            tx, rx = ACOUSTIC_TX_W, ACOUSTIC_RX_W
        else:
            tx, rx = OPTICAL_TX_W, OPTICAL_RX_W
        def energy(tx_w, rx_w):
            return ((row.tx_events * tx_w + row.rx_events * rx_w)
                    * row.timing_airtime_s / delivered_bits * 1e6)
        f = row.total_distance / 1000.0
        alpha = (0.11 * 50**2 / (1 + 50**2)
                 + 44 * 50**2 / (4100 + 50**2)
                 + 2.75e-4 * 50**2 + 0.003)
        scaled_tx = (ACOUSTIC_TX_W * (row.total_distance / 50.0) ** 2
                     * 10 ** (alpha * (f - 0.05) / 10.0))
        rows.append({
            "technology": row.technology,
            "distance_m": row.total_distance,
            "baseline_uj_bit": energy(tx, rx),
            "band_min_uj_bit": energy(tx * 0.5, rx * 0.5),
            "band_max_uj_bit": energy(tx * 1.5, rx * 1.5),
            "scaled_acoustic_uj_bit": (energy(scaled_tx, rx)
                                        if row.technology == "acoustic"
                                        else math.nan),
            "tx_events": row.tx_events,
            "rx_events": row.rx_events,
            "airtime_s": row.timing_airtime_s,
            "delivered_packets": row.delivered_packets,
        })
    data = pd.DataFrame(rows)
    grouped = []
    for (technology, distance), group in data.groupby(["technology",
                                                       "distance_m"]):
        item = {"technology": technology, "distance_m": distance}
        for col in ["baseline_uj_bit", "band_min_uj_bit", "band_max_uj_bit",
                    "scaled_acoustic_uj_bit"]:
            item[f"{col}_mean"] = group[col].mean()
            item[f"{col}_ci95"] = ci95(group[col])
        grouped.append(item)
    result = pd.DataFrame(grouped).sort_values(["distance_m", "technology"])
    result.to_csv(out, index=False)
    return result


def crossover(a: pd.Series, b: pd.Series, distances: pd.Series) -> float | None:
    delta = (a - b).to_numpy()
    x = distances.to_numpy()
    for i in range(len(x) - 1):
        if delta[i] == 0:
            return float(x[i])
        if delta[i] * delta[i + 1] < 0:
            return float(x[i] + (x[i + 1] - x[i])
                         * (-delta[i]) / (delta[i + 1] - delta[i]))
    return None


def energy_outputs(energy: pd.DataFrame) -> None:
    pivot = energy.pivot(index="distance_m", columns="technology")
    distances = pivot.index.to_series()
    rows = []
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
    for name, (acoustic, optical) in cases.items():
        rows.append({"case": name, "crossover_distance_m": crossover(
            acoustic, optical, distances),
            "result": "none in swept range" if crossover(
                acoustic, optical, distances) is None else "interpolated"})
    pd.DataFrame(rows).to_csv(OUT / "energy_crossovers.csv", index=False)

    fig, ax = plt.subplots(figsize=(9, 5), dpi=150)
    for technology, color in (("acoustic", "tab:orange"),
                              ("optical", "tab:blue")):
        g = energy[energy.technology == technology].sort_values("distance_m")
        ax.plot(g.distance_m, g.baseline_uj_bit_mean, "o-", color=color,
                label=f"{technology} baseline")
        ax.fill_between(g.distance_m, g.band_min_uj_bit_mean,
                        g.band_max_uj_bit_mean, color=color, alpha=0.16,
                        label=f"{technology} +/-50% power")
    acoustic = energy[energy.technology == "acoustic"].sort_values("distance_m")
    ax.plot(acoustic.distance_m, acoustic.scaled_acoustic_uj_bit_mean,
            "s--", color="black", label="acoustic distance-scaled TX")
    ax.set_xlabel("Distance (m)")
    ax.set_ylabel("Energy per delivered bit (uJ/bit)")
    ax.set_yscale("log")
    ax.grid(True, which="both", linestyle=":", alpha=0.6)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(OUT / "energy_per_bit_sensitivity.png", bbox_inches="tight")
    plt.close(fig)


def regime_maps(summary: pd.DataFrame) -> None:
    pivot = summary.pivot_table(index="water_c", columns="distance_m",
                                values=["delay_mean_s_mean",
                                        "energy_per_bit_uj_mean", "status"],
                                aggfunc="first")
    ratios = {}
    for metric, filename, title in [
            ("delay_mean_s_mean", "delay_ratio_map.png",
             "Delay ratio: acoustic / optical"),
            ("energy_per_bit_uj_mean", "energy_ratio_map.png",
             "Energy ratio: acoustic / optical")]:
        a = summary[summary.technology == "acoustic"].pivot(
            index="water_c", columns="distance_m", values=f"{metric}")
        o = summary[summary.technology == "optical"].pivot(
            index="water_c", columns="distance_m", values=f"{metric}")
        status = summary[summary.technology == "optical"].pivot(
            index="water_c", columns="distance_m", values="status")
        value = a / o
        ratios[metric] = value
        fig, ax = plt.subplots(figsize=(9, 5), dpi=150)
        arr = value.to_numpy(dtype=float)
        image = ax.imshow(arr, aspect="auto", origin="lower",
                          extent=[min(DISTANCES) - 25, max(DISTANCES) + 25,
                                  min(C_VALUES) - 0.1, max(C_VALUES) + 0.1],
                          cmap="coolwarm", vmin=0, vmax=max(2, np.nanmax(arr)))
        fig.colorbar(image, ax=ax, label="ratio (>1 favors optical)")
        for iy, c in enumerate(value.index):
            for ix, d in enumerate(value.columns):
                st = status.loc[c, d]
                if st == "INFEASIBLE":
                    ax.text(d, c, "INFEASIBLE", ha="center", va="center",
                            fontsize=7, color="black", rotation=45)
                elif np.isfinite(value.loc[c, d]):
                    ax.text(d, c, f"{value.loc[c, d]:.1f}", ha="center",
                            va="center", fontsize=8)
        ax.set_xlabel("Distance (m)")
        ax.set_ylabel("c (1/m)")
        ax.set_title(title)
        fig.tight_layout()
        fig.savefig(OUT / filename, bbox_inches="tight")
        plt.close(fig)

    calibration = pd.read_csv(OUT / "calibration.csv").drop_duplicates(
        "water_c")
    hardware = []
    for _, row in calibration.iterrows():
        hop = row.working_hop_m
        hardware.append({"water_c": row.water_c,
                         "modems_at_1000m": (math.nan if not np.isfinite(hop)
                                              else 2 * math.ceil(1000 / hop))})
    hardware = pd.DataFrame(hardware)
    fig, ax = plt.subplots(figsize=(8, 5), dpi=150)
    ax.plot(hardware.water_c, hardware.modems_at_1000m, "o-")
    ax.set_xlabel("c (1/m)")
    ax.set_ylabel("Optical requested modems at D=1000 m")
    ax.grid(True, linestyle=":", alpha=0.6)
    fig.tight_layout()
    fig.savefig(OUT / "hardware_count_vs_c.png", bbox_inches="tight")
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(8, 5), dpi=150)
    ax.plot(calibration.water_c, calibration.max_usable_hop_m, "o-",
            label="max pilot hop, PDR >= 0.95")
    ax.plot(calibration.water_c, calibration.working_hop_m, "s--",
            label="working hop = 80% max")
    ax.set_xlabel("c (1/m)")
    ax.set_ylabel("Optical hop length (m)")
    ax.grid(True, linestyle=":", alpha=0.6)
    ax.legend()
    fig.tight_layout()
    fig.savefig(OUT / "hop_length_vs_c.png", bbox_inches="tight")
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--part-a", action="store_true")
    parser.add_argument("--calibration-pilot", action="store_true")
    parser.add_argument("--grid-pilot", action="store_true")
    parser.add_argument("--main", action="store_true")
    parser.add_argument("--energy", action="store_true")
    parser.add_argument("--all", action="store_true")
    args = parser.parse_args()
    OUT.mkdir(exist_ok=True)
    if args.part_a or args.all:
        part_a()
    if args.calibration_pilot or args.all:
        calibrate()
    if args.grid_pilot or args.all:
        grid("grid_pilot", 2, 20.0)
    if args.main or args.all:
        grid("main", 10, 100.0)
    if args.energy or args.all:
        energy = energy_sensitivity()
        energy_outputs(energy)
    if args.main or args.all:
        regime_maps(pd.read_csv(OUT / "main" / "summary.csv"))


if __name__ == "__main__":
    main()
