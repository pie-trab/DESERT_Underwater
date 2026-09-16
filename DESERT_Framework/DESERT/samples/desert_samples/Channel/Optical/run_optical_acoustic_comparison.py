#!/usr/bin/env python3
"""Compare one direct acoustic link with multi-hop optical links.

The acoustic case always spans the complete source-to-destination distance.
Optical cases cover the same distance with a configurable number of hops. The
LUT/beam optical case is the main result; ordinary optical is a control.
"""

from __future__ import annotations

import argparse
import csv
import math
import re
import shlex
import statistics
import subprocess
from pathlib import Path


SENT_RE = re.compile(r"sent packets:\s*([0-9]+(?:\.[0-9]+)?)")
RECEIVED_RE = re.compile(r"received packets:\s*([0-9]+(?:\.[0-9]+)?)")
FTT_RE = re.compile(r"forward trip time mean:\s*([-+0-9.eE]+)")
FTT_STD_RE = re.compile(r"forward trip time std:\s*([-+0-9.eE]+)")
MAC_RE = re.compile(
    r"^\s*modem\s+(\d+):\s+([0-9.eE+-]+)\s+([0-9.eE+-]+)",
    re.MULTILINE,
)


def parse_args() -> argparse.Namespace:
    optical_dir = Path(__file__).resolve().parent
    repo_root = optical_dir.parents[5]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--environment", type=Path,
                        default=repo_root / "DESERT_buildCopy_LOCAL" / "environment")
    parser.add_argument("--simulation", type=Path,
                        default=optical_dir / "multi_hop_optical_tdma.tcl")
    parser.add_argument("--beam-simulation", type=Path,
                        default=optical_dir / "multi_hop_optical_tdma_beampattern.tcl")
    parser.add_argument("--acoustic-simulation", type=Path,
                        default=optical_dir / "single_link_comp.tcl")
    parser.add_argument("--output-dir", type=Path,
                        default=optical_dir / "optical_acoustic_comparison_results")
    parser.add_argument("--repetitions", type=int, default=3)
    return parser.parse_args()


def optical_hop_length(total_distance: float, n_relays: int,
                       relay_gap: float) -> float:
    length = (total_distance - n_relays * relay_gap) / (n_relays + 1)
    if length <= 0:
        raise ValueError("total distance is too short for the requested relay gaps")
    return length


def run_case(environment: Path, simulation: Path, workdir: Path, log_path: Path,
             *, technology: str, n_relays: int, total_distance: float,
             cbr_period: float, packet_size: int, depth: float,
             stop_time: float, rngstream: int, relay_gap: float,
             attenuation_scale: float, poisson_traffic: int,
             optical_txpower: float, optical_threshold: float,
             optical_theta: float) -> dict[str, object]:
    is_optical = technology != "acoustic"
    hop_length = optical_hop_length(total_distance, n_relays, relay_gap)
    values = [n_relays, cbr_period, packet_size,
              hop_length if is_optical else total_distance, relay_gap, depth,
              stop_time, rngstream, attenuation_scale, poisson_traffic]
    if is_optical:
        values.extend(["", optical_txpower, optical_threshold, optical_theta])
    command = "source {env} && ns {simulation} {args}".format(
        env=shlex.quote(str(environment.resolve())),
        simulation=shlex.quote(str(simulation.resolve())),
        args=" ".join(shlex.quote(str(value)) for value in values),
    )
    completed = subprocess.run(["zsh", "-lc", command], cwd=workdir,
                               text=True, capture_output=True, check=False)
    output = completed.stdout + completed.stderr
    log_path.write_text(output, encoding="utf-8")
    if completed.returncode != 0:
        raise RuntimeError(f"Simulation failed; see {log_path}")

    sent_match = SENT_RE.search(output)
    received_match = RECEIVED_RE.search(output)
    if sent_match is None or received_match is None:
        raise RuntimeError(f"Could not parse packet counters; see {log_path}")
    sent = float(sent_match.group(1))
    received = float(received_match.group(1))
    ftt_match = FTT_RE.search(output)
    ftt_std_match = FTT_STD_RE.search(output)

    hop_pdrs: list[float] = []
    if is_optical:
        mac = {int(node): (float(sent_pkts), float(recv_pkts))
               for node, sent_pkts, recv_pkts in MAC_RE.findall(output)}
        for hop in range(n_relays + 1):
            transmitted = mac.get(hop, (0.0, 0.0))[0]
            received_hop = mac.get(hop + 1, (0.0, 0.0))[1]
            hop_pdrs.append(received_hop / transmitted if transmitted else math.nan)
    finite_hops = [value for value in hop_pdrs if math.isfinite(value)]
    return {
        "technology": technology,
        "n_relays": n_relays,
        "hop_count": n_relays + 1 if is_optical else 1,
        "total_distance": total_distance,
        "hop_length": hop_length if is_optical else total_distance,
        "sent_packets": sent,
        "received_packets": received,
        "pdr": received / sent if sent else math.nan,
        "goodput_bps": received * packet_size * 8.0 / stop_time,
        "delay_mean_s": float(ftt_match.group(1)) if ftt_match else math.nan,
        "delay_std_s": float(ftt_std_match.group(1)) if ftt_std_match else math.nan,
        "mean_hop_pdr": statistics.mean(finite_hops) if finite_hops else math.nan,
        "weakest_hop_pdr": min(finite_hops) if finite_hops else math.nan,
    }


def make_cases(repetitions: int) -> list[dict[str, object]]:
    cases: list[dict[str, object]] = []
    common = {
        "cbr_period": 0.04, "packet_size": 125, "depth": -10.0,

        "stop_time": 1000.0, "relay_gap": 1.0,        "attenuation_scale": 0.1, "poisson_traffic": 0,

        "optical_txpower": 10.0, "optical_threshold": 1.0,
        "optical_theta": 0.524,
    }

    def add(sweep: str, value: float, n_relays: int,
            technologies: tuple[str, ...], **overrides: object) -> None:
        base = dict(common)
        base.update({"n_relays": n_relays, "total_distance": 60.0})
        base.update(overrides)
        for technology in technologies:
            for repetition in range(1, repetitions + 1):
                case = dict(base)
                case.update({"sweep": sweep, "sweep_value": value,
                             "technology": technology, "rngstream": repetition})
                cases.append(case)

    for distance in (20.0, 40.0, 60.0, 80.0, 100.0):
        add("total_distance", distance, 2,
            ("acoustic", "optical", "beam_optical"), total_distance=distance)
    for n_relays in (0, 1, 2, 3, 4):
        add("relay_count", float(n_relays), n_relays,
            ("acoustic", "optical", "beam_optical"))
    for period in (0.005, 0.01, 0.02, 0.05, 0.1, 0.25, 0.5, 1.0):
        add("offered_traffic", period, 2,
            ("acoustic", "optical", "beam_optical"),
            cbr_period=period, poisson_traffic=1)
    for packet_size in (64, 125, 250, 500):
        add("packet_size", float(packet_size), 2,
            ("acoustic", "optical", "beam_optical"), packet_size=packet_size)
    return cases


def summarize(rows: list[dict[str, object]]) -> list[dict[str, object]]:
    groups: dict[tuple[str, str, float], list[dict[str, object]]] = {}
    for row in rows:
        key = (str(row["technology"]), str(row["sweep"]),
               float(row["sweep_value"]))
        groups.setdefault(key, []).append(row)
    metrics = ("pdr", "goodput_bps", "delay_mean_s", "mean_hop_pdr",
               "weakest_hop_pdr")
    summaries: list[dict[str, object]] = []
    for (technology, sweep, value), group in sorted(groups.items()):
        result: dict[str, object] = {
            "technology": technology, "sweep": sweep, "sweep_value": value,
            "repetitions": len(group),
        }
        for metric in metrics:
            values = [float(row[metric]) for row in group
                      if math.isfinite(float(row[metric]))]
            result[f"{metric}_mean"] = statistics.mean(values) if values else math.nan
            result[f"{metric}_std"] = statistics.stdev(values) if len(values) > 1 else 0.0
        summaries.append(result)
    return summaries


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    fields = ["technology", "sweep", "sweep_value", "rngstream", "n_relays",
              "hop_count", "total_distance", "hop_length", "sent_packets",
              "received_packets", "pdr", "goodput_bps", "delay_mean_s",
              "delay_std_s", "mean_hop_pdr", "weakest_hop_pdr"]
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def write_summary_csv(path: Path, summaries: list[dict[str, object]]) -> None:
    fields = ["technology", "sweep", "sweep_value", "repetitions",
              "pdr_mean", "pdr_std", "goodput_bps_mean", "goodput_bps_std",
              "delay_mean_s_mean", "delay_mean_s_std", "mean_hop_pdr_mean",
              "mean_hop_pdr_std", "weakest_hop_pdr_mean", "weakest_hop_pdr_std"]
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(summaries)


def plot_results(output_dir: Path, summaries: list[dict[str, object]]) -> None:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    colors = {"acoustic": "tab:orange", "optical": "tab:blue",
              "beam_optical": "tab:green"}
    labels = {"acoustic": "Direct acoustic", "optical": "Ordinary optical",
              "beam_optical": "Optical + LUT/beam"}
    styles = {"acoustic": ("s", "--"), "optical": ("o", "-"),
              "beam_optical": ("^", "-.")}
    definitions = {
        "total_distance": "Total source-destination distance (m)",
        "relay_count": "Optical relay couples",
        "offered_traffic": "CBR mean period (s)",
        "packet_size": "Packet size (bytes)",
    }
    for sweep, xlabel in definitions.items():
        selected = [row for row in summaries if row["sweep"] == sweep]
        figure, axes = plt.subplots(2, 4, figsize=(20, 4.5))
        for technology in ("acoustic", "optical", "beam_optical"):
            points = sorted((row for row in selected
                             if row["technology"] == technology),
                            key=lambda row: float(row["sweep_value"]))
            if not points:
                continue
            x = [float(row["sweep_value"]) for row in points]
            marker, linestyle = styles[technology]
            style = {"marker": marker, "linestyle": linestyle,
                     "color": colors[technology], "label": labels[technology]}
            axes[0].plot(x, [100 * float(row["pdr_mean"]) for row in points], **style)
            axes[1].plot(x, [float(row["goodput_bps_mean"]) for row in points], **style)
            axes[2].plot(x, [1000 * float(row["delay_mean_s_mean"]) for row in points], **style)
            if technology != "acoustic":
                axes[3].plot(x, [100 * float(row["weakest_hop_pdr_mean"]) for row in points], **style)
        axes[0].set_ylabel("End-to-end PDR (%)")
        axes[1].set_ylabel("Goodput (bit/s)")
        axes[2].set_ylabel("Mean delay (ms)")
        axes[3].set_ylabel("Weakest optical-hop PDR (%)")
        for axis in axes:
            axis.set_xlabel(xlabel)
            axis.grid(True, alpha=0.3)
            axis.legend()
        figure.suptitle("Direct acoustic versus multi-hop optical: " + sweep)
        figure.tight_layout()
        figure.savefig(output_dir / f"comparison_{sweep}.png", dpi=160)
        plt.close(figure)


def main() -> None:
    arguments = parse_args()
    if arguments.repetitions < 1:
        raise SystemExit("--repetitions must be at least 1")
    for path in (arguments.environment, arguments.simulation,
                 arguments.beam_simulation, arguments.acoustic_simulation):
        if not path.is_file():
            raise SystemExit(f"File not found: {path}")
    output_dir = arguments.output_dir.resolve()
    logs_dir = output_dir / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, object]] = []
    cases = make_cases(arguments.repetitions)
    for index, case in enumerate(cases, 1):
        technology = str(case["technology"])
        simulation = {"acoustic": arguments.acoustic_simulation,
                      "optical": arguments.simulation,
                      "beam_optical": arguments.beam_simulation}[technology]
        log_path = logs_dir / f"{index:03d}_{technology}_{case['sweep']}_{case['sweep_value']}.log"
        result = run_case(
            arguments.environment, simulation, simulation.parent, log_path,
            **{key: case[key] for key in (
                "technology", "n_relays", "total_distance", "cbr_period",
                "packet_size", "depth", "stop_time", "rngstream", "relay_gap",
                "attenuation_scale", "poisson_traffic", "optical_txpower",
                "optical_threshold", "optical_theta")},
        )
        result.update({"sweep": case["sweep"], "sweep_value": case["sweep_value"],
                       "rngstream": case["rngstream"]})
        rows.append(result)
        print(f"[{index}/{len(cases)}] {technology} {case['sweep']}={case['sweep_value']}")
    write_csv(output_dir / "results.csv", rows)
    summaries = summarize(rows)
    write_summary_csv(output_dir / "summary.csv", summaries)
    plot_results(output_dir, summaries)
    print(f"Results written to {output_dir}")


if __name__ == "__main__":
    main()
