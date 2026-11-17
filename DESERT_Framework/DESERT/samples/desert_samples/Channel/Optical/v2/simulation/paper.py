#!/usr/bin/env python3
"""Build the final paper tables and figures from consolidated data."""

from __future__ import annotations

import math
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

import core


DISTANCES = (50.0, 100.0, 200.0, 500.0, 1000.0, 1500.0)
COLORS = {"acoustic": "tab:orange", "acoustic_chain": "tab:brown",
          "optical": "tab:blue"}
LABELS = {"acoustic": "Direct acoustic",
          "acoustic_chain": "Acoustic equal-hop chain (diagnostic)",
          "optical": "Optical scaled-hop chain"}
STYLES = {"acoustic": "s-", "acoustic_chain": "d--", "optical": "o-"}


def build_tables() -> tuple[pd.DataFrame, pd.DataFrame]:
    distance = pd.read_csv(core.FINAL / "distance_runs.csv")
    diagnostic = pd.read_csv(core.FINAL / "diagnostic_runs.csv")
    distance = distance[
        distance.technology.isin(("acoustic", "optical"))
        & distance.total_distance.isin(DISTANCES)
    ]
    main = core.summarize(distance)
    main.to_csv(core.FINAL / "distance_summary.csv", index=False)
    diag = core.summarize(diagnostic)
    columns = ["technology", "distance_m", "repetitions", "hop_count",
               "unique_modems", "link_endpoint_modems", "pdr_mean",
               "pdr_ci95", "delay_mean_s_mean", "delay_mean_s_ci95",
               "energy_per_bit_uj_mean", "energy_per_bit_uj_ci95",
               "pdr_below_095"]
    main = main[columns].copy()
    main["series_role"] = "headline"
    diag = diag[columns].copy()
    diag["series_role"] = "diagnostic_only"
    diag["artifact_note"] = (
        "PDR losses localize to the first hop; mechanism unresolved")
    main.to_csv(core.FINAL / "main_results.csv", index=False)
    diag.to_csv(core.FINAL / "diagnostic_results.csv", index=False)
    tables = core.PAPER / "tables"
    tables.mkdir(parents=True, exist_ok=True)
    main.to_csv(tables / "main_results.csv", index=False)
    diag.to_csv(tables / "diagnostic_results.csv", index=False)
    params = pd.read_csv(core.FINAL / "parameters.csv")
    params.to_csv(tables / "parameters.csv", index=False)
    calibration = pd.read_csv(core.FINAL / "calibration.csv")
    calibration.to_csv(tables / "calibration.csv", index=False)
    return main, diag


def plot_series(table: pd.DataFrame, path: Path, title: str,
                technologies: tuple[str, ...], note: str | None = None) -> None:
    specs = [
        ("pdr_mean", "pdr_ci95", "PDR (%)", 100.0, False),
        ("delay_mean_s_mean", "delay_mean_s_ci95", "Mean delay (s)", 1.0, True),
        ("energy_per_bit_uj_mean", "energy_per_bit_uj_ci95",
         "Energy per delivered bit (uJ/bit)", 1.0, True),
        ("unique_modems", None, "Unique modems", 1.0, False),
    ]
    fig, axes = plt.subplots(2, 2, figsize=(12, 8), dpi=160)
    for ax, (metric, ci_metric, ylabel, scale, logy) in zip(axes.flat, specs):
        for technology in technologies:
            group = table[table.technology == technology].sort_values(
                "distance_m")
            y = group[metric] * scale
            if metric == "unique_modems":
                ax.plot(group.distance_m, y, STYLES[technology],
                        color=COLORS[technology], label=LABELS[technology])
                continue
            below = group.pdr_below_095.astype(bool)
            normal = ~below
            ax.errorbar(group.loc[normal, "distance_m"], y[normal],
                        yerr=group.loc[normal, ci_metric] * scale,
                        fmt=STYLES[technology], color=COLORS[technology],
                        label=LABELS[technology], capsize=3)
            ax.errorbar(group.loc[below, "distance_m"], y[below],
                        yerr=group.loc[below, ci_metric] * scale,
                        fmt=STYLES[technology], markerfacecolor="none",
                        color=COLORS[technology], capsize=3)
        ax.set_xscale("log")
        ax.set_xticks(DISTANCES)
        ax.set_xticklabels([f"{d:g}" for d in DISTANCES])
        ax.set_xlabel("Distance (m)")
        ax.set_ylabel(ylabel)
        ax.grid(True, which="both", linestyle=":", alpha=0.6)
        if logy:
            ax.set_yscale("log")
        if metric == "pdr_mean":
            ax.set_ylim(-5, 105)
            ax.text(0.02, 0.05, "open marker: PDR < 0.95",
                    transform=ax.transAxes, fontsize=7)
            if note:
                ax.text(0.02, 0.12, note, transform=ax.transAxes,
                        fontsize=7, color="darkred")
        if metric == "unique_modems":
            ax.set_yscale("log")
            if "acoustic_chain" in technologies:
                ax.text(0.02, 0.05, "relay chains overlap",
                        transform=ax.transAxes, fontsize=7)
        ax.legend(fontsize=8)
    fig.suptitle(title)
    fig.tight_layout()
    fig.savefig(path, bbox_inches="tight")
    plt.close(fig)


def plot_regime() -> None:
    summary = pd.read_csv(core.FINAL / "turbidity_summary.csv")
    # The turbid-harbor c=2.19 row is all INFEASIBLE; keep it in the table
    # and text, but not in the heat map.
    summary = summary[summary.water_c <= 1.2]
    c_values = sorted(summary.water_c.dropna().unique())
    distances = sorted(summary.distance_m.unique())
    fig, axes = plt.subplots(1, 2, figsize=(13, 5), dpi=160)
    for ax, metric, title in zip(
            axes,
            ["delay_mean_s_mean", "energy_per_bit_uj_mean"],
            ["Delay ratio: acoustic / optical",
             "Energy ratio: acoustic / optical"]):
        a = summary[summary.technology == "acoustic"].pivot_table(
            index="water_c", columns="distance_m", values=metric,
            aggfunc="first")
        o = summary[summary.technology == "optical"].pivot_table(
            index="water_c", columns="distance_m", values=metric,
            aggfunc="first")
        status = summary[summary.technology == "optical"].pivot_table(
            index="water_c", columns="distance_m", values="status",
            aggfunc="first")
        ratio = a / o
        arr = ratio.to_numpy(dtype=float)
        image = ax.imshow(
            arr, aspect="auto", origin="lower",
            cmap="coolwarm", vmin=0, vmax=max(2.0, np.nanmax(arr)))
        fig.colorbar(image, ax=ax, label="ratio (>1 favors optical)")
        for i, c in enumerate(ratio.index):
            for j, d in enumerate(ratio.columns):
                state = status.loc[c, d]
                if state == "INFEASIBLE":
                    ax.text(j, i, "INFEASIBLE", ha="center", va="center",
                            fontsize=6, rotation=45)
                elif np.isfinite(ratio.loc[c, d]):
                    value = ratio.loc[c, d]
                    text = f"{value:.0f}" if value >= 10 else f"{value:.1f}"
                    ax.text(j, i, text, ha="center", va="center", fontsize=6)
        ax.set_xticks(range(len(ratio.columns)),
                      [f"{d:g}" for d in ratio.columns])
        ax.set_yticks(range(len(ratio.index)),
                      [f"{c:g}" for c in ratio.index])
        ax.set_xlabel("Distance (m)")
        ax.set_ylabel("c (1/m)")
        ax.set_title(title)
    fig.tight_layout()
    fig.savefig(core.PAPER / "figures" / "fig_regime_maps.png",
                bbox_inches="tight")
    plt.close(fig)


def plot_hop() -> None:
    calibration = pd.read_csv(
        core.FINAL / "calibration.csv").drop_duplicates("water_c")
    calibration = calibration.sort_values("water_c")
    fig, axes = plt.subplots(1, 2, figsize=(12, 5), dpi=160)
    ax = axes[0]
    ax.plot(calibration.water_c, calibration.max_usable_hop_m, "o-",
            label="max pilot hop (PDR >= 0.95)")
    ax.plot(calibration.water_c, calibration.working_hop_m, "s--",
            label="working hop = 80% max")
    ax.set_xlabel("c (1/m)")
    ax.set_ylabel("Optical hop length (m)")
    ax.grid(True, linestyle=":", alpha=0.6)
    ax.legend(fontsize=8)

    ax = axes[1]
    hops = np.ceil(1000.0 / calibration.working_hop_m)
    unique = hops + 1
    feasible = hops <= 100
    ax.plot(calibration.water_c[feasible], unique[feasible], "o-",
            label="feasible")
    ax.plot(calibration.water_c[~feasible], unique[~feasible], "rx",
            markersize=9, label="INFEASIBLE (>100 hops)")
    for c, value in zip(calibration.water_c, unique):
        ax.annotate(f"{int(value)}", (c, value), textcoords="offset points",
                    xytext=(0, 7), ha="center", fontsize=8)
    ax.set_xlabel("c (1/m)")
    ax.set_ylabel("Unique optical modems at D=1000 m")
    ax.set_yscale("log")
    ax.grid(True, which="both", linestyle=":", alpha=0.6)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(core.PAPER / "figures" / "fig_hop_hardware.png",
                bbox_inches="tight")
    plt.close(fig)


def plot_energy() -> None:
    energy = pd.read_csv(core.FINAL / "energy_sensitivity.csv")
    cross = pd.read_csv(core.FINAL / "energy_crossovers.csv")
    fig, ax = plt.subplots(figsize=(9, 5), dpi=160)
    colors = {"acoustic": "tab:orange", "optical": "tab:blue"}
    for technology in ("acoustic", "optical"):
        group = energy[energy.technology == technology].sort_values(
            "distance_m")
        ax.plot(group.distance_m, group.baseline_uj_bit_mean, "o-",
                color=colors[technology], label=f"{technology} baseline")
        ax.fill_between(group.distance_m, group.band_min_uj_bit_mean,
                        group.band_max_uj_bit_mean, color=colors[technology],
                        alpha=0.16, label=f"{technology} +/-50% power")
    acoustic = energy[energy.technology == "acoustic"].sort_values(
        "distance_m")
    ax.plot(acoustic.distance_m, acoustic.scaled_acoustic_uj_bit_mean,
            "s--", color="black", label="acoustic distance-scaled TX")
    crossover = cross[cross.case == "band_acoustic_min_optical_max"]
    if len(crossover) and np.isfinite(crossover.crossover_distance_m.iloc[0]):
        x = crossover.crossover_distance_m.iloc[0]
        ax.axvline(x, color="black", linestyle=":", linewidth=1)
        ax.annotate(f"envelope crossover {x:.0f} m", (x, ax.get_ylim()[1]),
                    textcoords="offset points", xytext=(4, -12), fontsize=8)
    ax.set_xlabel("Distance (m)")
    ax.set_ylabel("Energy per delivered bit (uJ/bit)")
    ax.set_yscale("log")
    ax.grid(True, which="both", linestyle=":", alpha=0.6)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(core.PAPER / "figures" / "fig_energy_sensitivity.png",
                bbox_inches="tight")
    plt.close(fig)


def plot_wind() -> None:
    path = core.FINAL / "wind_summary.csv"
    if not path.exists():
        return
    summary = pd.read_csv(path)
    summary = summary[summary.technology == "acoustic"]
    distances = sorted(summary.distance_m.unique())
    colors = ["tab:blue", "tab:orange", "tab:green"]
    fig, axes = plt.subplots(1, 2, figsize=(12, 4.5), dpi=160)
    specs = [
        (axes[0], "pdr_mean", "pdr_ci95", "PDR (%)", 100.0),
        (axes[1], "delay_mean_s_mean", "delay_mean_s_ci95",
         "Mean delay (s)", 1.0),
    ]
    for ax, metric, ci_metric, ylabel, scale in specs:
        for color, distance in zip(colors, distances):
            group = summary[summary.distance_m == distance].sort_values(
                "windspeed")
            y = group[metric] * scale
            yerr = group[ci_metric] * scale
            finite = np.isfinite(y)
            ax.errorbar(group.windspeed[finite], y[finite],
                        yerr=yerr[finite], fmt="o-", color=color,
                        capsize=3, label=f"{distance:g} m")
        ax.set_xlabel("Wind speed (m/s)")
        ax.set_ylabel(ylabel)
        ax.grid(True, linestyle=":", alpha=0.6)
        ax.legend(fontsize=8)
    axes[0].set_ylim(-5, 105)
    fig.suptitle("Direct acoustic link: wind-speed sensitivity")
    fig.tight_layout()
    fig.savefig(core.PAPER / "figures" / "fig_wind_sensitivity.png",
                bbox_inches="tight")
    plt.close(fig)


def plot_wind_pdr() -> None:
    path = core.FINAL / "wind_summary.csv"
    if not path.exists():
        return
    summary = pd.read_csv(path)
    summary = summary[summary.technology == "acoustic"]
    distances = sorted(summary.distance_m.unique())
    colors = ["tab:blue", "tab:orange", "tab:green"]
    fig, ax = plt.subplots(figsize=(6.5, 4.5), dpi=160)
    for color, distance in zip(colors, distances):
        group = summary[summary.distance_m == distance].sort_values(
            "windspeed")
        ax.errorbar(group.windspeed, group.pdr_mean * 100.0,
                    yerr=group.pdr_ci95 * 100.0, fmt="o-", color=color,
                    capsize=3, label=f"{distance:g} m")
    ax.set_xlabel("Wind speed (m/s)")
    ax.set_ylabel("PDR (%)")
    ax.set_ylim(-5, 105)
    ax.grid(True, linestyle=":", alpha=0.6)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(core.PAPER / "figures" / "fig_wind_pdr.png",
                bbox_inches="tight")
    plt.close(fig)



def plot_load() -> None:
    path = core.FINAL / "load_summary.csv"
    if not path.exists():
        return
    summary = pd.read_csv(path)
    summary["offered_bps"] = 1000.0 / summary.cbr_period
    fig, axes = plt.subplots(2, 2, figsize=(12, 8), dpi=160)
    specs = [
        ("pdr_mean", "PDR (%)", 100.0, False),
        ("goodput_bps_mean", "Goodput (bit/s)", 1.0, True),
        ("delay_mean_s_mean", "Mean delay (s)", 1.0, True),
        ("energy_per_bit_uj_mean", "Energy per delivered bit (uJ/bit)",
         1.0, True),
    ]
    colors = {(1000.0, "acoustic"): "tab:orange",
              (1500.0, "acoustic"): "tab:red",
              (1000.0, "optical"): "tab:blue",
              (1500.0, "optical"): "tab:cyan"}
    for ax, (metric, ylabel, scale, logy) in zip(axes.flat, specs):
        for (distance, technology), color in sorted(colors.items()):
            group = summary[(summary.distance_m == distance)
                            & (summary.technology == technology)]
            group = group.sort_values("offered_bps")
            ax.plot(group.offered_bps, group[metric] * scale, "o-",
                    color=color, label=f"{technology} {distance:g} m")
        ax.set_xscale("log")
        loads = sorted(summary.offered_bps.unique())
        ax.set_xticks(loads)
        ax.set_xticklabels([f"{x:g}" for x in loads])
        ax.minorticks_off()
        ax.set_xlabel("Offered load (bit/s)")
        ax.set_ylabel(ylabel)
        ax.grid(True, which="both", linestyle=":", alpha=0.6)
        if logy:
            ax.set_yscale("log")
        ax.legend(fontsize=7)
    fig.suptitle("Offered-load sweep: direct acoustic vs optical chain")
    fig.tight_layout()
    fig.savefig(core.PAPER / "figures" / "fig_load_sweep.png",
                bbox_inches="tight")
    plt.close(fig)


def build() -> None:
    core.PAPER.mkdir(parents=True, exist_ok=True)
    (core.PAPER / "figures").mkdir(parents=True, exist_ok=True)
    main, diag = build_tables()
    table = pd.concat([main, diag], ignore_index=True)
    plot_series(
        main, core.PAPER / "figures" / "fig_main_distance.png",
        "Headline: direct acoustic vs scaled-hop optical",
        ("acoustic", "optical"))
    plot_series(
        table, core.PAPER / "figures" / "fig_chain_diagnostic.png",
        "Diagnostic only: acoustic equal-hop chain",
        ("acoustic", "acoustic_chain", "optical"),
        note="acoustic chain: diagnostic, not a PDR curve")
    plot_regime()
    plot_hop()
    plot_energy()
    plot_wind()
    plot_wind_pdr()
    plot_load()
    print("paper tables and figures rebuilt")
