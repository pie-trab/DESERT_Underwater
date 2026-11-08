#!/usr/bin/env python3
"""Milestone 4: final paper freeze and acoustic-chain diagnostic quarantine."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

import run_m3


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "results_m4"
PAPER = OUT / "paper"
DISTANCES = (50.0, 100.0, 200.0, 500.0, 1000.0, 1500.0)
COLORS = {"acoustic": "tab:orange", "acoustic_chain": "tab:brown",
          "optical": "tab:blue"}
LABELS = {"acoustic": "Direct acoustic",
          "acoustic_chain": "Acoustic equal-hop chain (diagnostic)",
          "optical": "Optical scaled-hop chain"}
STYLES = {"acoustic": "s-", "acoustic_chain": "d--", "optical": "o-"}


def read_m3_table() -> pd.DataFrame:
    path = ROOT / "results_m3" / "paper" / "main_results.csv"
    table = pd.read_csv(path)
    table = table[table.distance_m.isin(DISTANCES)].copy()
    return table.sort_values(["distance_m", "technology"])


def split_results(table: pd.DataFrame) -> tuple[pd.DataFrame, pd.DataFrame]:
    headline = table[table.technology.isin(("acoustic", "optical"))].copy()
    diagnostic = table[table.technology == "acoustic_chain"].copy()
    headline["series_role"] = "headline"
    diagnostic["series_role"] = "diagnostic_only"
    diagnostic["artifact_note"] = (
        "PDR losses localize to the first hop; mechanism unresolved")
    return headline, diagnostic


def write_tables(headline: pd.DataFrame, diagnostic: pd.DataFrame) -> None:
    headline.to_csv(PAPER / "main_results.csv", index=False)
    diagnostic.to_csv(PAPER / "diagnostic_results.csv", index=False)
    with (PAPER / "main_results.md").open("w", encoding="utf-8") as handle:
        handle.write("# Headline paper results\n\n")
        handle.write("Direct acoustic and optical scaled-hop only. "
                     "Acoustic-chain diagnostics are excluded.\n\n```\n")
        handle.write(headline.to_string(index=False))
        handle.write("\n```\n")
    with (PAPER / "diagnostic_results.md").open("w", encoding="utf-8") as handle:
        handle.write("# Diagnostic: acoustic equal-hop chain\n\n")
        handle.write("This table is not a physical PDR curve. PDR below "
                     "0.95 is an unresolved first-hop simulation artifact; "
                     "delay is conditional on delivered packets and energy "
                     "includes transmissions of lost packets.\n\n```\n")
        handle.write(diagnostic.to_string(index=False))
        handle.write("\n```\n")


def plot_series(table: pd.DataFrame, path: Path, title: str,
                technologies: tuple[str, ...], note: str | None = None) -> None:
    fig, axes = plt.subplots(2, 2, figsize=(12, 8), dpi=160)
    specs = [
        ("pdr_mean", "pdr_ci95", "PDR (%)", 100.0, False),
        ("delay_mean_s_mean", "delay_mean_s_ci95", "Mean delay (s)", 1.0, True),
        ("energy_per_bit_uj_mean", "energy_per_bit_uj_ci95",
         "Energy per delivered bit (uJ/bit)", 1.0, True),
        ("unique_modems", None, "Unique modems", 1.0, False),
    ]
    for ax, (metric, ci_metric, ylabel, scale, logy) in zip(axes.flat, specs):
        for technology in technologies:
            g = table[table.technology == technology].sort_values("distance_m")
            y = g[metric] * scale
            if metric == "unique_modems":
                ax.plot(g.distance_m, y, STYLES[technology],
                        color=COLORS[technology], label=LABELS[technology])
                continue
            below = g.pdr_below_095.astype(bool)
            normal = ~below
            ax.errorbar(g.loc[normal, "distance_m"], y[normal],
                        yerr=g.loc[normal, ci_metric] * scale,
                        fmt=STYLES[technology], color=COLORS[technology],
                        label=LABELS[technology], capsize=3)
            ax.errorbar(g.loc[below, "distance_m"], y[below],
                        yerr=g.loc[below, ci_metric] * scale,
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
            if "acoustic_chain" in technologies and "optical" in technologies:
                ax.text(0.02, 0.05, "relay chains overlap",
                        transform=ax.transAxes, fontsize=7)
        ax.legend(fontsize=8)
    fig.suptitle(title)
    fig.tight_layout()
    fig.savefig(path, bbox_inches="tight")
    plt.close(fig)


def write_parameters() -> None:
    run_m3.write_parameters(PAPER)


def write_paper_summary(headline: pd.DataFrame) -> None:
    def get(technology: str, distance: float, column: str) -> float:
        row = headline[(headline.technology == technology)
                       & (headline.distance_m == distance)]
        return float(row[column].iloc[0]) if len(row) else math.nan

    def secs(value: float) -> str:
        return f"{value:.3f} s"

    def energy(value: float) -> str:
        return f"{value:.1f} uJ/bit"

    lines = [
        "# Paper summary and final claims",
        "",
        "## Headline comparison",
        "",
        "Direct acoustic vs distance-scaled plain optical, c=0.3 1/m. "
        "The acoustic equal-hop chain is a diagnostic and is excluded from "
        "the headline PDR/delay/energy claims.",
        "",
        "## Defensible claims",
        "",
        "1. In every feasible optical cell, scaled-hop optical delivered "
        "100% of generated packets, while direct acoustic started to fail "
        "near 1500 m.",
        "2. Optical has substantially lower delay and analytical energy per "
        "delivered bit than direct acoustic at the tested low load.",
        "3. The optical advantage costs hardware: unique modems grow from 2 "
        "to 76 over 1500 m, and high-turbidity long-distance cells become "
        "infeasible under the 100-hop cap.",
        "4. Direct acoustic is the lowest-hardware option and remains "
        "lossless through 1000 m in the configured model.",
        "5. The acoustic equal-hop result is diagnostic only. Its "
        "non-monotonic PDR is an unresolved first-hop simulation artifact "
        "and is not evidence about acoustic range.",
        "",
        "## Key numbers",
        "",
        f"- 100 m direct acoustic: PDR "
        f"{100 * get('acoustic', 100.0, 'pdr_mean'):.0f}%, "
        f"delay {secs(get('acoustic', 100.0, 'delay_mean_s_mean'))}, "
        f"energy {energy(get('acoustic', 100.0, 'energy_per_bit_uj_mean'))}.",
        f"- 100 m optical: delay "
        f"{secs(get('optical', 100.0, 'delay_mean_s_mean'))}, energy "
        f"{energy(get('optical', 100.0, 'energy_per_bit_uj_mean'))}.",
        f"- 1000 m direct acoustic: delay "
        f"{secs(get('acoustic', 1000.0, 'delay_mean_s_mean'))}, energy "
        f"{energy(get('acoustic', 1000.0, 'energy_per_bit_uj_mean'))}.",
        f"- 1000 m optical: delay "
        f"{secs(get('optical', 1000.0, 'delay_mean_s_mean'))}, energy "
        f"{energy(get('optical', 1000.0, 'energy_per_bit_uj_mean'))}, "
        f"{get('optical', 1000.0, 'unique_modems'):.0f} unique modems.",
        f"- 1500 m direct acoustic: PDR "
        f"{100 * get('acoustic', 1500.0, 'pdr_mean'):.0f}%, "
        f"delay {secs(get('acoustic', 1500.0, 'delay_mean_s_mean'))}.",
        f"- 1500 m optical: PDR "
        f"{100 * get('optical', 1500.0, 'pdr_mean'):.0f}%, "
        f"{get('optical', 1500.0, 'unique_modems'):.0f} unique modems.",
        "",
        "## Required caveats",
        "",
        "- Energy is analytical from MAC TX/RX counts and assumed powers, "
        "not simulated modem energy.",
        "- The optical channel is deterministic; no fading, turbulence or "
        "independent misalignment is modeled.",
        "- Beam-LUT mode is excluded.",
        "- The acoustic equal-hop PDR is diagnostic only; its exact "
        "first-hop loss mechanism is unproven.",
        "- The M1/M2 `2*hops` modem value is a link-endpoint count; this "
        "paper uses `hops+1` unique modems.",
    ]
    (PAPER / "paper_summary.md").write_text(
        "\n".join(lines) + "\n", encoding="utf-8")


def write_claims() -> None:
    text = """# Final claims and exclusions

## Included

- Direct acoustic baseline at 50--1500 m.
- Plain optical scaled-hop baseline at c=0.3 1/m.
- M2 turbidity regime maps for c=0.1--1.2 1/m and D=50--1000 m.
- Analytical energy sensitivity and unique-modem accounting.

## Excluded from headline claims

- The acoustic equal-hop chain PDR/delay/energy curve is diagnostic only.
  Losses occur only at the first hop, all downstream edges are 1.0 and
  queues are empty. The first hop is an ideal 20 m link, so this is not
  acoustic range loss. The exact mechanism is unresolved and is not used as
  a physical result.
- Beam-LUT mode, because its noise/LUT calibration is a documented model
  limitation.
- Independent node misalignment, which the v2 plain-optical model does not
  expose.

## Artifact statement for the paper

Use wording such as:

> The acoustic equal-hop control is reported only as a diagnostic. Its
> non-monotonic PDR is caused by first-hop packet loss in the TDMA chain,
> not by acoustic propagation over the 20 m links; the exact simulator
> mechanism remains unresolved and is excluded from the paper's physical
> conclusions.
"""
    (PAPER / "claims_and_caveats.md").write_text(text, encoding="utf-8")


def write_reproduce() -> None:
    text = """# Reproduce the paper dataset

From the repository root, after sourcing the DESERT environment:

```console
source /home/pietro/DESERT_Underwater/DESERT_buildCopy_LOCAL/environment
cd DESERT_Framework/DESERT/samples/desert_samples/Channel/Optical/v2

python3 run_m1.py --pilot-only
python3 run_m1.py --main-only

python3 run_m2.py --part-a
python3 run_m2.py --calibration-pilot
python3 run_m2.py --grid-pilot
python3 run_m2.py --main
python3 run_m2.py --energy

python3 run_m3.py --pilot
python3 run_m3.py --main
python3 run_m3.py --paper

python3 run_m4.py --paper

checks/milestone1.sh
checks/milestone2.sh
checks/milestone3.sh
checks/milestone4.sh
```

Raw per-run logs and `results*.csv` are intentionally not committed. The
committed derived outputs are the summaries, frozen parameter tables and
paper figures.

Expected final check: `PASS: milestone 4 final paper package`.
"""
    (OUT / "REPRODUCE.md").write_text(text, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Build milestone 4 paper package.")
    parser.add_argument("--paper", action="store_true")
    args = parser.parse_args()
    if not args.paper:
        parser.print_help()
        return
    PAPER.mkdir(parents=True, exist_ok=True)
    table = read_m3_table()
    headline, diagnostic = split_results(table)
    write_tables(headline, diagnostic)
    plot_series(
        headline, PAPER / "fig_main_distance.png",
        "Headline: direct acoustic vs scaled-hop optical",
        ("acoustic", "optical"))
    plot_series(
        table, PAPER / "fig_chain_diagnostic.png",
        "Diagnostic only: acoustic equal-hop chain",
        ("acoustic", "acoustic_chain", "optical"),
        note="acoustic chain: diagnostic, not a PDR curve")
    write_parameters()
    run_m3.plot_regime_maps(PAPER)
    run_m3.plot_hop_hardware(PAPER)
    run_m3.plot_energy(PAPER)
    write_paper_summary(headline)
    write_claims()
    write_reproduce()
    print(f"paper package: {PAPER}")


if __name__ == "__main__":
    main()
