#!/usr/bin/env python3
"""
Run paired optical/acoustic DESERT experiments and create comparison graphs.

The common comparisons use n_relays=0 for the optical simulation, so they
compare one optical link with one acoustic link under matching traffic,
packet-size, geometry, and simulation-time settings. Optical relay-count and
attenuation experiments remain optical-only because a direct acoustic link
has no equivalent of those two parameters.

The reported metrics are packet delivery ratio (PDR), received application
payload throughput in bit/s, and received packet count. Throughput is
calculated as received_packets * packet_size * 8 / stop_time. Delay is not
reported because the existing Tcl examples do not expose per-packet delay.

Run from the Optical directory:

    python3 run_optical_acoustic_comparison.py

The output directory contains raw results, grouped summaries, per-category
plots, an overview plot, and one complete log for every Tcl run.
"""

from __future__ import annotations

import argparse
import csv
import math
import os
import re
import shlex
import statistics
import subprocess
from pathlib import Path


SENT_RE = re.compile(r"sent packets:\s*([0-9]+(?:\.[0-9]+)?)")
RECEIVED_RE = re.compile(r"received packets:\s*([0-9]+(?:\.[0-9]+)?)")


def parse_args() -> argparse.Namespace:
    optical_dir = Path(__file__).resolve().parent
    repo_root = optical_dir.parents[5]
    default_environment = repo_root / "DESERT_buildCopy_LOCAL" / "environment"
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", type=Path, default=default_environment)
    parser.add_argument(
        "--simulation",
        type=Path,
        default=optical_dir / "multi_hop_optical_tdma.tcl",
        help="optical Tcl simulation file",
    )
    parser.add_argument(
        "--acoustic-simulation",
        type=Path,
        default=optical_dir / "single_link_comp.tcl",
        help="acoustic single-link Tcl simulation file",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=optical_dir / "optical_acoustic_comparison_results",
    )
    parser.add_argument(
        "--repetitions",
        type=int,
        default=3,
        help="RNG substreams per experiment point (default: 3)",
    )
    return parser.parse_args()


def run_case(
    environment: Path,
    simulation: Path,
    working_directory: Path,
    log_path: Path,
    *,
    n_relays: int,
    cbr_period: float,
    packet_size: int,
    hop_length: float,
    relay_gap: float,
    depth: float,
    stop_time: float,
    rngstream: int,
    attenuation_scale: float,
    poisson_traffic: int,
) -> tuple[float, float]:
    """Run one Tcl case and return sent and received packet counts."""

    # Both Tcl files accept this interface. The acoustic script uses the
    # direct distance and accepts relay-specific arguments for compatibility.
    values = [
        str(n_relays), str(cbr_period), str(packet_size), str(hop_length),
        str(relay_gap), str(depth), str(stop_time), str(rngstream),
        str(attenuation_scale), str(poisson_traffic),
    ]
    command = "source {env} && ns {simulation} {arguments}".format(
        env=shlex.quote(str(environment.resolve())),
        simulation=shlex.quote(str(simulation.resolve())),
        arguments=" ".join(shlex.quote(value) for value in values),
    )
    completed = subprocess.run(
        ["zsh", "-lc", command],
        cwd=working_directory,
        text=True,
        capture_output=True,
        check=False,
    )
    output = completed.stdout + completed.stderr
    log_path.write_text(output, encoding="utf-8")
    if completed.returncode != 0:
        raise RuntimeError(
            f"Simulation failed with exit code {completed.returncode}. See {log_path}"
        )
    sent_match = SENT_RE.search(output)
    received_match = RECEIVED_RE.search(output)
    if sent_match is None or received_match is None:
        raise RuntimeError(f"Could not parse packet counters. See {log_path}")
    return float(sent_match.group(1)), float(received_match.group(1))


def add_case(
    cases: list[dict[str, object]], *, sweep: str, value: float,
    repetitions: int, fixed: dict[str, object], technology: str,
) -> None:
    for repetition in range(1, repetitions + 1):
        case = dict(fixed)
        case.update({
            "technology": technology,
            "sweep": sweep,
            "sweep_value": value,
            "repetition": repetition,
            "rngstream": repetition,
        })
        cases.append(case)


def make_cases(repetitions: int) -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []

    # Common comparisons use one optical hop, matching the acoustic topology.
    common_fixed = {
        "n_relays": 0, "cbr_period": 2.0, "packet_size": 125,
        "hop_length": 20.0, "relay_gap": 1.0, "depth": -10.0,
        "stop_time": 20.0, "attenuation_scale": 1.0,
        "poisson_traffic": 0,
    }
    for value in (10.0, 20.0, 30.0, 40.0, 50.0, 60.0):
        fixed = dict(common_fixed)
        fixed["hop_length"] = value
        for technology in ("optical", "acoustic"):
            add_case(cases, sweep="distance_comparison", value=value,
                     repetitions=repetitions, fixed=fixed,
                     technology=technology)
    for value in (0.25, 0.5, 1.0, 2.0, 4.0):
        fixed = dict(common_fixed)
        fixed["cbr_period"] = value
        fixed["poisson_traffic"] = 1
        for technology in ("optical", "acoustic"):
            add_case(cases, sweep="traffic_comparison", value=value,
                     repetitions=repetitions, fixed=fixed,
                     technology=technology)
    for value in (64.0, 125.0, 250.0, 500.0):
        fixed = dict(common_fixed)
        fixed["packet_size"] = int(value)
        for technology in ("optical", "acoustic"):
            add_case(cases, sweep="packet_size_comparison", value=value,
                     repetitions=repetitions, fixed=fixed,
                     technology=technology)

    # Optical-only categories retain the actual multi-hop topology.
    optical_fixed = {
        "n_relays": 2, "cbr_period": 2.0, "packet_size": 125,
        "hop_length": 20.0, "relay_gap": 1.0, "depth": -10.0,
        "stop_time": 20.0, "attenuation_scale": 1.0,
        "poisson_traffic": 0,
    }
    for value in (1.0, 2.0, 3.0, 4.0, 5.0, 6.0):
        fixed = dict(optical_fixed)
        fixed["attenuation_scale"] = value
        add_case(cases, sweep="optical_attenuation", value=value,
                 repetitions=repetitions, fixed=fixed, technology="optical")
    for value in (0, 1, 2, 3, 4):
        fixed = dict(optical_fixed)
        fixed["n_relays"] = value
        add_case(cases, sweep="optical_relay_count", value=float(value),
                 repetitions=repetitions, fixed=fixed, technology="optical")
    return cases


def summarize(rows: list[dict[str, object]]) -> list[dict[str, object]]:
    groups: dict[tuple[str, str, float], list[dict[str, object]]] = {}
    for row in rows:
        key = (str(row["technology"]), str(row["sweep"]),
               float(row["sweep_value"]))
        groups.setdefault(key, []).append(row)
    summaries: list[dict[str, object]] = []
    for (technology, sweep, value), group in sorted(groups.items()):
        pdr = [float(item["pdr"]) for item in group]
        throughput = [float(item["throughput_bps"]) for item in group]
        received = [float(item["received_packets"]) for item in group]
        summaries.append({
            "technology": technology, "sweep": sweep, "sweep_value": value,
            "repetitions": len(group),
            "pdr_mean": statistics.mean(pdr),
            "pdr_std": statistics.stdev(pdr) if len(pdr) > 1 else 0.0,
            "throughput_mean_bps": statistics.mean(throughput),
            "throughput_std_bps": statistics.stdev(throughput)
            if len(throughput) > 1 else 0.0,
            "received_mean": statistics.mean(received),
            "received_std": statistics.stdev(received)
            if len(received) > 1 else 0.0,
        })
    return summaries


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    fields = [
        "technology", "sweep", "sweep_value", "repetition", "rngstream",
        "n_relays", "cbr_period", "packet_size", "hop_length", "relay_gap",
        "depth", "stop_time", "attenuation_scale", "poisson_traffic",
        "sent_packets", "received_packets", "pdr", "throughput_bps",
    ]
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def write_summary_csv(path: Path, summaries: list[dict[str, object]]) -> None:
    fields = [
        "technology", "sweep", "sweep_value", "repetitions", "pdr_mean",
        "pdr_std", "throughput_mean_bps", "throughput_std_bps",
        "received_mean", "received_std",
    ]
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(summaries)


def points(summaries: list[dict[str, object]], sweep: str,
           technology: str) -> list[dict[str, object]]:
    selected = [item for item in summaries
                if item["sweep"] == sweep and item["technology"] == technology]
    return sorted(selected, key=lambda item: float(item["sweep_value"]))


def plot_category(output_directory: Path, summaries: list[dict[str, object]], *,
                  sweep: str, xlabel: str, title: str, filename: str,
                  compare_technologies: bool) -> None:
    import matplotlib.pyplot as plt

    technologies = ("optical", "acoustic") if compare_technologies else ("optical",)
    colors = {"optical": "tab:blue", "acoustic": "tab:orange"}
    labels = {"optical": "Optical", "acoustic": "Acoustic"}
    figure, axes = plt.subplots(1, 2, figsize=(12, 4.5))
    for technology in technologies:
        selected = points(summaries, sweep, technology)
        if not selected:
            continue
        x = [float(item["sweep_value"]) for item in selected]
        pdr = [100.0 * float(item["pdr_mean"]) for item in selected]
        pdr_err = [100.0 * float(item["pdr_std"]) for item in selected]
        throughput = [float(item["throughput_mean_bps"]) for item in selected]
        throughput_err = [float(item["throughput_std_bps"]) for item in selected]
        style = {"marker": "o", "capsize": 4, "linewidth": 1.5,
                 "color": colors[technology], "label": labels[technology]}
        axes[0].errorbar(x, pdr, yerr=pdr_err, **style)
        axes[1].errorbar(x, throughput, yerr=throughput_err, **style)
    axes[0].set_xlabel(xlabel)
    axes[0].set_ylabel("Packet delivery ratio (%)")
    axes[0].set_ylim(-5, 105)
    axes[1].set_xlabel(xlabel)
    axes[1].set_ylabel("Payload throughput (bit/s)")
    for axis in axes:
        axis.grid(True, alpha=0.3)
        axis.legend()
    figure.suptitle(title)
    figure.tight_layout()
    figure.savefig(output_directory / filename, dpi=160)
    plt.close(figure)


def make_plots(output_directory: Path, summaries: list[dict[str, object]]) -> None:
    matplotlib_cache = output_directory / ".matplotlib"
    matplotlib_cache.mkdir(parents=True, exist_ok=True)
    os.environ.setdefault("MPLCONFIGDIR", str(matplotlib_cache))
    import matplotlib
    matplotlib.use("Agg")

    common = {
        "distance_comparison": ("Direct link distance (m)",
            "Optical one-hop vs acoustic direct-link comparison: distance",
            "comparison_distance.png"),
        "traffic_comparison": ("CBR mean period (s)",
            "Optical one-hop vs acoustic direct-link comparison: offered traffic",
            "comparison_traffic_period.png"),
        "packet_size_comparison": ("Packet size (byte)",
            "Optical one-hop vs acoustic direct-link comparison: packet size",
            "comparison_packet_size.png"),
    }
    optical_only = {
        "optical_attenuation": ("Optical attenuation multiplier",
            "Optical-only sensitivity: attenuation coefficient",
            "optical_attenuation.png"),
        "optical_relay_count": ("Optical relay couples",
            "Optical-only sensitivity: relay count", "optical_relay_count.png"),
    }
    for sweep, (xlabel, title, filename) in common.items():
        plot_category(output_directory, summaries, sweep=sweep, xlabel=xlabel,
                      title=title, filename=filename, compare_technologies=True)
    for sweep, (xlabel, title, filename) in optical_only.items():
        plot_category(output_directory, summaries, sweep=sweep, xlabel=xlabel,
                      title=title, filename=filename, compare_technologies=False)

    # Overview of the three paired categories: rows are categories and columns
    # are PDR and payload throughput.
    import matplotlib.pyplot as plt
    figure, axes = plt.subplots(3, 2, figsize=(12, 12))
    colors = {"optical": "tab:blue", "acoustic": "tab:orange"}
    labels = {"optical": "Optical", "acoustic": "Acoustic"}
    for row, (sweep, (xlabel, title, _filename)) in enumerate(common.items()):
        for technology in ("optical", "acoustic"):
            selected = points(summaries, sweep, technology)
            x = [float(item["sweep_value"]) for item in selected]
            axes[row, 0].plot(
                x, [100.0 * float(item["pdr_mean"]) for item in selected],
                marker="o", color=colors[technology], label=labels[technology])
            axes[row, 1].plot(
                x, [float(item["throughput_mean_bps"]) for item in selected],
                marker="o", color=colors[technology], label=labels[technology])
        axes[row, 0].set_title(title)
        axes[row, 0].set_xlabel(xlabel)
        axes[row, 0].set_ylabel("PDR (%)")
        axes[row, 0].set_ylim(-5, 105)
        axes[row, 1].set_xlabel(xlabel)
        axes[row, 1].set_ylabel("Payload throughput (bit/s)")
        for axis in axes[row]:
            axis.grid(True, alpha=0.3)
            axis.legend()
    figure.suptitle("Optical/acoustic single-link comparison summary")
    figure.tight_layout()
    figure.savefig(output_directory / "comparison_summary.png", dpi=160)
    plt.close(figure)


def main() -> None:
    arguments = parse_args()
    if arguments.repetitions < 1:
        raise SystemExit("--repetitions must be at least 1")
    if not arguments.environment.is_file():
        raise SystemExit(f"Environment file not found: {arguments.environment}")
    if not arguments.simulation.is_file():
        raise SystemExit(f"Optical simulation file not found: {arguments.simulation}")
    if not arguments.acoustic_simulation.is_file():
        raise SystemExit(f"Acoustic simulation file not found: {arguments.acoustic_simulation}")

    output_directory = arguments.output_dir.resolve()
    logs_directory = output_directory / "logs"
    logs_directory.mkdir(parents=True, exist_ok=True)
    cases = make_cases(arguments.repetitions)
    rows: list[dict[str, object]] = []
    point_count = len(cases) // arguments.repetitions
    print(f"Running {len(cases)} simulations ({point_count} points x {arguments.repetitions} repetitions)...")

    for index, case in enumerate(cases, start=1):
        log_name = (f"{index:03d}_{case['technology']}_{case['sweep']}"
                    f"_value_{case['sweep_value']}_rep_{case['repetition']}.log")
        print(f"[{index:03d}/{len(cases)}] {case['technology']} "
              f"{case['sweep']}={case['sweep_value']} "
              f"repetition={case['repetition']}")
        simulation = (arguments.simulation if case["technology"] == "optical"
                      else arguments.acoustic_simulation)
        run_values = {key: case[key] for key in (
            "n_relays", "cbr_period", "packet_size", "hop_length", "relay_gap",
            "depth", "stop_time", "rngstream", "attenuation_scale",
            "poisson_traffic")}
        sent, received = run_case(
            arguments.environment, simulation, simulation.resolve().parent,
            logs_directory / log_name, **run_values)
        pdr = received / sent if sent > 0 else math.nan
        throughput = (received * float(case["packet_size"]) * 8.0
                      / float(case["stop_time"]))
        row = dict(case)
        row.update({"sent_packets": sent, "received_packets": received,
                    "pdr": pdr, "throughput_bps": throughput})
        rows.append(row)

    summaries = summarize(rows)
    write_csv(output_directory / "results.csv", rows)
    write_summary_csv(output_directory / "summary.csv", summaries)
    comparison = [item for item in summaries if item["sweep"] in {
        "distance_comparison", "traffic_comparison", "packet_size_comparison"}]
    write_summary_csv(output_directory / "comparison_summary.csv", comparison)
    make_plots(output_directory, summaries)
    print(f"Results written to: {output_directory}")
    print(f"Comparison graph:    {output_directory / 'comparison_summary.png'}")
    print(f"Grouped CSV summary: {output_directory / 'summary.csv'}")


if __name__ == "__main__":
    main()