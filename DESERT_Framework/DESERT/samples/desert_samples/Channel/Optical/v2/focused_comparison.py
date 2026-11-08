#!/usr/bin/env python3
"""Small pilot and focused comparisons for the v2 exam-paper study.

This imports the existing v2 runner without changing its simulation model.
It only supplies explicitly listed parameter grids, stores the raw per-run
rows/logs, and writes compact four-panel comparison plots.
"""

from __future__ import annotations

import concurrent.futures
import math
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

import run_comparison_v2 as base


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "focused_results"


GRIDS = {
    "pilot": {
        "distance": [60, 70, 80, 90, 100, 110],
        "offered_load": [0.04, 0.05, 0.075, 0.1, 0.125, 0.15],
        "turbidity": [0.5, 0.6, 0.7, 0.8, 1.0, 1.2, 1.6, 2.0],
        "theta": [0.174, 0.262, 0.349, 0.524, 0.698],
    },
    "focused": {
        "distance": [65, 70, 75, 80, 85, 90, 95, 100, 105],
        "offered_load": [0.04, 0.05, 0.06, 0.075, 0.1, 0.125, 0.15,
                          0.2],
        "turbidity": [0.5, 0.6, 0.7, 0.8, 1.0, 1.2, 1.4, 1.6, 2.0],
        "theta": [0.174, 0.262, 0.349, 0.524, 0.698],
    },
}


def make_case(kind: str, value: float) -> dict:
    case = dict(base.BASE)
    case.update({
        "n_relays": 2,
        "total_distance": 50.0,
        "sweep": kind,
        "sweep_value": float(value),
    })
    if kind == "distance":
        case["total_distance"] = float(value)
    elif kind == "offered_load":
        case["cbr_period"] = float(value)
    elif kind == "turbidity":
        case["attenuation_scale"] = float(value) / 0.3
    elif kind == "theta":
        case["total_distance"] = 60.0
        case["optical_theta"] = float(value)
    else:
        raise ValueError(kind)
    return case


def run_phase(phase: str, repetitions: int, stop_time: float) -> pd.DataFrame:
    phase_dir = OUT / phase
    log_dir = phase_dir / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    jobs = []
    index = 0
    for kind, values in GRIDS[phase].items():
        for value in values:
            for technology in base.TECHNOLOGIES:
                for rngstream in range(1, repetitions + 1):
                    case = make_case(kind, value)
                    case.update({
                        "technology": technology,
                        "rngstream": rngstream,
                        "stop_time": stop_time,
                    })
                    jobs.append((index, case))
                    index += 1

    def execute(job):
        index, case = job
        log = log_dir / (
            f"{index:05d}_{case['technology']}_{case['sweep']}_"
            f"{case['sweep_value']:g}_rep{case['rngstream']:02d}.log")
        try:
            row = base.run_case(case["technology"], case, log)
            row.update({
                "phase": phase,
                "sweep": case["sweep"],
                "sweep_value": case["sweep_value"],
                "rngstream": case["rngstream"],
                "failed": False,
            })
        except Exception as exc:  # preserve failures for the audit trail
            row = {
                "phase": phase,
                "technology": case["technology"],
                "sweep": case["sweep"],
                "sweep_value": case["sweep_value"],
                "rngstream": case["rngstream"],
                "failed": True,
                "error": str(exc),
            }
        return index, row

    rows = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        futures = [pool.submit(execute, job) for job in jobs]
        for future in concurrent.futures.as_completed(futures):
            index, row = future.result()
            rows[index] = row
    df = pd.DataFrame([rows[i] for i in sorted(rows)])
    df.to_csv(phase_dir / "results.csv", index=False)
    print(f"{phase}: {len(df)} rows, {int(df.failed.sum())} failures")
    return df


def ci95(values: pd.Series) -> float:
    values = values.dropna()
    if len(values) <= 1:
        return 0.0
    return 2.262 * values.std(ddof=1) / math.sqrt(len(values))


def plot_phase(df: pd.DataFrame, phase: str) -> None:
    plot_dir = OUT / "plots"
    plot_dir.mkdir(parents=True, exist_ok=True)
    colors = {"acoustic": "tab:orange", "optical": "tab:blue",
              "beam_optical": "tab:green"}
    labels = {"acoustic": "Direct acoustic", "optical": "Optical",
              "beam_optical": "Beam optical"}
    for sweep in sorted(df.sweep.unique()):
        d = df[(df.sweep == sweep) & (~df.failed)].copy()
        if d.empty:
            continue
        fig, axes = plt.subplots(2, 2, figsize=(12, 8), dpi=140)
        specs = [("pdr", "PDR", 100.0),
                 ("goodput_bps", "Goodput (bit/s)", 1.0),
                 ("delay_mean_s", "Mean delay (ms)", 1000.0),
                 ("energy_per_bit_uj", "Energy (uJ/bit)", 1.0)]
        for ax, (metric, title, scale) in zip(axes.flat, specs):
            for technology in base.TECHNOLOGIES:
                g = d[d.technology == technology]
                grouped = g.groupby("sweep_value")[metric]
                x = np.array(sorted(grouped.groups))
                means = np.array([grouped.get_group(v).mean() * scale
                                  for v in x])
                errors = np.array([ci95(grouped.get_group(v)) * scale
                                   for v in x])
                ax.errorbar(x, means, yerr=errors, marker="o", capsize=3,
                            color=colors[technology], label=labels[technology])
            ax.set_title(title)
            ax.set_xlabel(sweep)
            ax.grid(True, linestyle=":", alpha=0.6)
            ax.legend(fontsize=8)
            if metric == "pdr":
                ax.set_ylim(-5, 105)
            if metric in ("delay_mean_s", "energy_per_bit_uj"):
                ax.set_yscale("symlog", linthresh=1e-3)
        fig.suptitle(f"v2 focused {phase}: {sweep}")
        fig.tight_layout()
        fig.savefig(plot_dir / f"{phase}_{sweep}.png", bbox_inches="tight")
        plt.close(fig)


def main() -> None:
    OUT.mkdir(exist_ok=True)
    pilot = run_phase("pilot", repetitions=2, stop_time=20.0)
    plot_phase(pilot, "pilot")
    focused = run_phase("focused", repetitions=10, stop_time=100.0)
    plot_phase(focused, "focused")


if __name__ == "__main__":
    main()
