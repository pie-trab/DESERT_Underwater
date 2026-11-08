#!/usr/bin/env python3
"""Milestone 1: fairer distance-scaled acoustic/optical comparison."""

from __future__ import annotations

import concurrent.futures
import argparse
import math
import time
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

import run_comparison_v2 as base


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "results_m1"
DISTANCES = (50.0, 100.0, 200.0, 300.0, 500.0, 750.0, 1000.0, 1500.0)
TECHNOLOGIES = ("acoustic", "optical")
OPTICAL_HOP_M = 20.0
CBR_PERIOD_S = 5.0
PILOT_REPETITIONS = 2
MAIN_REPETITIONS = 10
PILOT_STOP_S = 20.0
MAIN_STOP_S = 100.0


def make_case(technology: str, distance: float, repetition: int,
              stop_time: float) -> dict:
    case = dict(base.BASE)
    if technology == "optical":
        hops = int(math.ceil(distance / OPTICAL_HOP_M))
        n_relays = hops - 1
        hop_length = distance / hops
    else:
        hops = 1
        n_relays = 0
        hop_length = distance
    case.update({
        "technology": technology,
        "n_relays": n_relays,
        "total_distance": distance,
        "hop_count_expected": hops,
        "hop_length_expected": hop_length,
        "modems_expected": 2 if technology == "acoustic" else 2 * hops,
        "cbr_period": CBR_PERIOD_S,
        "stop_time": stop_time,
        "rngstream": repetition,
        "sweep": "distance_m1",
        "sweep_value": distance,
    })
    return case


def run_grid(out_dir: Path, repetitions: int, stop_time: float) -> pd.DataFrame:
    log_dir = out_dir / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    jobs = []
    index = 0
    for distance in DISTANCES:
        for technology in TECHNOLOGIES:
            for repetition in range(1, repetitions + 1):
                jobs.append((index, make_case(technology, distance,
                                               repetition, stop_time)))
                index += 1

    def execute(job):
        idx, case = job
        log = log_dir / (
            f"{idx:05d}_{case['technology']}_D{case['total_distance']:g}"
            f"_rep{case['rngstream']:02d}.log")
        started = time.monotonic()
        try:
            row = base.run_case(case["technology"], case, log)
            row.update({
                "sweep": case["sweep"],
                "sweep_value": case["sweep_value"],
                "rngstream": case["rngstream"],
                "expected_hops": case["hop_count_expected"],
                "expected_hop_length_m": case["hop_length_expected"],
                "modems": case["modems_expected"],
                "conservation_residual": (
                    row["sent_packets"] - row["delivered_packets"]
                    - row["queue_drops_total"] - row["queue_final_total"]
                    - row["phy_lost_packets"]),
                "runtime_s": time.monotonic() - started,
                "failed": False,
            })
        except Exception as exc:
            row = {
                "technology": case["technology"],
                "sweep": case["sweep"],
                "sweep_value": case["sweep_value"],
                "rngstream": case["rngstream"],
                "n_relays": case["n_relays"],
                "hop_count": case["hop_count_expected"],
                "expected_hops": case["hop_count_expected"],
                "expected_hop_length_m": case["hop_length_expected"],
                "modems": case["modems_expected"],
                "failed": True,
                "error": str(exc),
                "runtime_s": time.monotonic() - started,
            }
        return idx, row

    rows = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        futures = [pool.submit(execute, job) for job in jobs]
        for future in concurrent.futures.as_completed(futures):
            idx, row = future.result()
            rows[idx] = row
    df = pd.DataFrame([rows[i] for i in sorted(rows)])
    df.to_csv(out_dir / "results.csv", index=False)
    print(f"{out_dir.name}: {len(df)} rows, {int(df.failed.sum())} failures")
    return df


def summarize(df: pd.DataFrame, out_dir: Path) -> pd.DataFrame:
    rows = []
    good = df[~df.failed]
    metrics = ["pdr", "goodput_bps", "delay_mean_s", "energy_per_bit_uj"]
    for (technology, distance), group in good.groupby(
            ["technology", "sweep_value"]):
        row = {
            "technology": technology,
            "distance_m": distance,
            "repetitions": len(group),
            "n_relays": group.n_relays.iloc[0],
            "hop_count": group.hop_count.iloc[0],
            "hop_length_m": group.expected_hop_length_m.iloc[0],
            "modems": group.modems.iloc[0],
            "modems_ci95": 0.0,
            "slot_s": group.timing_slot_s.iloc[0],
            "airtime_s": group.timing_airtime_s.iloc[0],
            "propagation_s": group.timing_propagation_s.iloc[0],
            "frame_s": group.timing_frame_s.iloc[0],
        }
        for metric in metrics:
            values = group[metric]
            row[f"{metric}_mean"] = values.mean()
            row[f"{metric}_std"] = values.std(ddof=1)
            row[f"{metric}_ci95"] = base.ci95(values)
        rows.append(row)
    summary = pd.DataFrame(rows).sort_values(["distance_m", "technology"])
    summary.to_csv(out_dir / "summary.csv", index=False)
    return summary


def plot_metric(summary: pd.DataFrame, metric: str, ylabel: str,
                filename: str) -> None:
    fig, ax = plt.subplots(figsize=(8, 5), dpi=150)
    colors = {"acoustic": "tab:orange", "optical": "tab:blue"}
    labels = {"acoustic": "Direct acoustic", "optical": "Optical scaled-hop"}
    for technology in TECHNOLOGIES:
        group = summary[summary.technology == technology]
        finite = np.isfinite(group[f"{metric}_mean"])
        group = group[finite]
        ax.errorbar(group.distance_m, group[f"{metric}_mean"],
                    yerr=group[f"{metric}_ci95"], marker="o", capsize=4,
                    linewidth=1.5, color=colors[technology],
                    label=labels[technology])
    ax.set_xlabel("Source-destination distance (m)")
    ax.set_ylabel(ylabel)
    ax.grid(True, linestyle=":", alpha=0.6)
    ax.legend()
    fig.tight_layout()
    fig.savefig(OUT / filename, bbox_inches="tight")
    plt.close(fig)


def plot_hardware(summary: pd.DataFrame) -> None:
    fig, ax = plt.subplots(figsize=(8, 5), dpi=150)
    colors = {"acoustic": "tab:orange", "optical": "tab:blue"}
    labels = {"acoustic": "Direct acoustic", "optical": "Optical scaled-hop"}
    for technology in TECHNOLOGIES:
        group = summary[summary.technology == technology]
        ax.errorbar(group.distance_m, group.modems,
                    yerr=group.modems_ci95, marker="o", capsize=4,
                    color=colors[technology], label=labels[technology])
    ax.set_xlabel("Source-destination distance (m)")
    ax.set_ylabel("Modems per scenario")
    ax.set_yticks(sorted(summary.modems.unique()))
    ax.grid(True, linestyle=":", alpha=0.6)
    ax.legend()
    fig.tight_layout()
    fig.savefig(OUT / "hardware_count_vs_distance.png", bbox_inches="tight")
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run milestone 1.")
    parser.add_argument("--pilot-only", action="store_true")
    parser.add_argument("--main-only", action="store_true")
    args = parser.parse_args()
    if args.pilot_only and args.main_only:
        parser.error("--pilot-only and --main-only are mutually exclusive")
    OUT.mkdir(exist_ok=True)
    if not args.main_only:
        pilot_dir = OUT / "pilot"
        pilot = run_grid(pilot_dir, PILOT_REPETITIONS, PILOT_STOP_S)
        summarize(pilot, pilot_dir)
        print("pilot maximum run time (s):", pilot.runtime_s.max())
    if not args.pilot_only:
        main = run_grid(OUT, MAIN_REPETITIONS, MAIN_STOP_S)
        summary = summarize(main, OUT)
        plot_metric(summary, "delay_mean_s", "Mean delay (s)",
                    "delay_vs_distance.png")
        plot_metric(summary, "goodput_bps", "Goodput (bit/s)",
                    "goodput_vs_distance.png")
        plot_metric(summary, "energy_per_bit_uj",
                    "Energy per delivered bit (uJ/bit)",
                    "energy_per_bit_vs_distance.png")
        plot_hardware(summary)
        print("maximum run time (s):", main.runtime_s.max())


if __name__ == "__main__":
    main()
