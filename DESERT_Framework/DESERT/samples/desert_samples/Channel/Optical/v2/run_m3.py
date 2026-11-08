#!/usr/bin/env python3
"""Milestone 3: acoustic equal-hop control and paper-ready outputs."""

from __future__ import annotations

import argparse
import concurrent.futures
import math
import shlex
import subprocess
import time
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

import run_comparison_v2 as base


ROOT = Path(__file__).resolve().parent
OUT = ROOT / "results_m3"
ACOUSTIC_CHAIN = ROOT / "acoustic_chain_v3.tcl"
DISTANCES = (50.0, 100.0, 200.0, 500.0, 1000.0, 1500.0)
OPTICAL_HOP_M = 20.0
CBR_PERIOD = 5.0
PACKET_SIZE = 125
DEPTH = -10.0
ACOUSTIC_BPS = 20768.0
ACOUSTIC_TX_W = 20.0
ACOUSTIC_RX_W = 4.0
OPTICAL_BPS = 1.0e6
OPTICAL_TX_W = 10.0
OPTICAL_RX_W = 1.5
PILOT_SEEDS = 2
MAIN_SEEDS = 10
PILOT_STOP_S = 20.0
MAIN_STOP_S = 100.0


def make_case(distance: float, repetition: int, stop_time: float) -> dict:
    hops = int(math.ceil(distance / OPTICAL_HOP_M))
    return {
        "n_relays": hops - 1,
        "total_distance": distance,
        "expected_hops": hops,
        "expected_hop_length_m": distance / hops,
        "unique_modems": hops + 1,
        "link_endpoint_modems": 2 * hops,
        "cbr_period": CBR_PERIOD,
        "packet_size": PACKET_SIZE,
        "depth": DEPTH,
        "stop_time": stop_time,
        "rngstream": repetition,
        "poisson_traffic": 1,
    }


def run_chain_case(case: dict, log_path: Path) -> dict:
    args = [
        case["n_relays"], case["cbr_period"], case["packet_size"],
        case["total_distance"], case["depth"], case["stop_time"],
        case["rngstream"], case["poisson_traffic"],
    ]
    command = "source {env} && ns {sim} {args}".format(
        env=shlex.quote(str(base.ENV_PATH.resolve())),
        sim=shlex.quote(str(ACOUSTIC_CHAIN.resolve())),
        args=" ".join(shlex.quote(str(a)) for a in args),
    )
    completed = subprocess.run(
        ["zsh", "-lc", command], cwd=ROOT, text=True,
        capture_output=True, check=False,
    )
    output = completed.stdout + completed.stderr
    log_path.write_text(output, encoding="utf-8")
    if completed.returncode != 0:
        raise RuntimeError(f"ns exited with {completed.returncode}")

    match = lambda regex: (lambda m: float(m.group(1)) if m else math.nan)(
        regex.search(output))
    timing_match = base.TIMING_RE.search(output)
    timing = {}
    if timing_match:
        for token in timing_match.group(1).split():
            if "=" in token:
                key, value = token.split("=", 1)
                try:
                    timing[key] = float(value)
                except ValueError:
                    timing[key] = value
    sent = match(base.SENT_RE)
    received = match(base.RECEIVED_RE)
    if math.isnan(sent) or math.isnan(received):
        raise RuntimeError("metrics block missing from the ns output")

    hop_count = case["expected_hops"]
    nodes = [(int(n), int(tx), int(rx), int(up), int(q))
             for n, tx, rx, up, q in base.NODE_RE.findall(output)]
    tx_by_node = {n: (tx, rx, up, q) for n, tx, rx, up, q in nodes}

    edge_pdrs = []
    for edge in range(hop_count):
        tx_n = tx_by_node.get(edge, (0, 0, 0, 0))[0]
        rx_n = tx_by_node.get(edge + 1, (0, 0, 0, 0))[1]
        edge_pdrs.append(rx_n / tx_n if tx_n else math.nan)
    finite_edges = [v for v in edge_pdrs if math.isfinite(v)]

    delivered = tx_by_node.get(hop_count, (0, 0, 0, 0))[1]
    delay_mean = match(base.FTT_RE)
    delay_std = match(base.FTT_STD_RE)
    if delivered <= 0:
        delay_mean = math.nan
        delay_std = math.nan

    tx_events = sum(tx for _, (tx, _, _, _) in tx_by_node.items())
    rx_events = sum(rx for _, (_, rx, _, _) in tx_by_node.items())
    airtime = timing.get("airtime_s")
    if not isinstance(airtime, float) or not math.isfinite(airtime):
        header_bytes = timing.get("header_bytes", 16.0)
        airtime = 8.0 * (case["packet_size"] + header_bytes) / ACOUSTIC_BPS
    delivered_bits = delivered * case["packet_size"] * 8.0
    energy_j = ((tx_events * ACOUSTIC_TX_W + rx_events * ACOUSTIC_RX_W)
                * airtime)
    energy = (energy_j / delivered_bits * 1e6
              if delivered_bits > 0 else math.nan)

    queue_drops = 0
    total_q_final = 0
    for node_id, (_, _, up, q) in tx_by_node.items():
        total_q_final += q
        if node_id != hop_count:
            queue_drops += max(0, up - tx_by_node[node_id][0] - q)
    phy_lost = sent - delivered - queue_drops - total_q_final

    return {
        "technology": "acoustic_chain",
        "n_relays": case["n_relays"],
        "hop_count": hop_count,
        "total_distance": case["total_distance"],
        "hop_length": case["expected_hop_length_m"],
        "cbr_period": case["cbr_period"],
        "packet_size": case["packet_size"],
        "sent_packets": sent,
        "delivered_packets": delivered,
        "received_packets": received,
        "app_counter_censored": sent > 65535,
        "pdr": delivered / sent if sent else math.nan,
        "pdr_app": received / sent if sent else math.nan,
        "goodput_bps": (delivered_bits
                        / max(1e-9, case["stop_time"] - 0.1)),
        "cbr_thr_bps": match(base.CBR_THR_RE),
        "delay_mean_s": delay_mean,
        "delay_std_s": delay_std,
        "mean_edge_pdr": statistics_mean(finite_edges),
        "weakest_edge_pdr": min(finite_edges) if finite_edges else math.nan,
        "edge_pdrs": "|".join(f"{v:.4f}" for v in edge_pdrs),
        "tx_events": tx_events,
        "rx_events": rx_events,
        "queue_drops_total": queue_drops,
        "queue_final_total": total_q_final,
        "phy_lost_packets": phy_lost,
        "energy_per_bit_uj": energy,
        "packet_time_s": airtime,
        "timing_header_bytes": timing.get("header_bytes", math.nan),
        "timing_packet_bytes": timing.get("packet_bytes", math.nan),
        "timing_airtime_s": airtime,
        "timing_propagation_s": timing.get("propagation_s", math.nan),
        "timing_guard_s": timing.get("guard_s", math.nan),
        "timing_slot_s": timing.get("slot_s", math.nan),
        "timing_frame_s": timing.get("frame_s", math.nan),
        "timing_tdma_slots": timing.get("tdma_slots", math.nan),
        "timing_modems": timing.get("modems", math.nan),
        "unique_modems": case["unique_modems"],
        "link_endpoint_modems": case["link_endpoint_modems"],
        "expected_hops": case["expected_hops"],
        "expected_hop_length_m": case["expected_hop_length_m"],
    }


def statistics_mean(values: list) -> float:
    return sum(values) / len(values) if values else math.nan


def run_grid(out_dir: Path, repetitions: int, stop_time: float) -> pd.DataFrame:
    log_dir = out_dir / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    jobs = []
    index = 0
    for distance in DISTANCES:
        for repetition in range(1, repetitions + 1):
            jobs.append((index, make_case(distance, repetition, stop_time)))
            index += 1

    def execute(job):
        idx, case = job
        log = log_dir / (
            f"{idx:05d}_acoustic_chain_D{case['total_distance']:g}"
            f"_rep{case['rngstream']:02d}.log")
        started = time.monotonic()
        try:
            row = run_chain_case(case, log)
            row.update({
                "sweep": "distance_m3",
                "sweep_value": case["total_distance"],
                "rngstream": case["rngstream"],
                "conservation_residual": (
                    row["sent_packets"] - row["delivered_packets"]
                    - row["queue_drops_total"] - row["queue_final_total"]
                    - row["phy_lost_packets"]),
                "runtime_s": time.monotonic() - started,
                "failed": False,
            })
        except Exception as exc:
            row = {
                "technology": "acoustic_chain",
                "n_relays": case["n_relays"],
                "hop_count": case["expected_hops"],
                "total_distance": case["total_distance"],
                "expected_hops": case["expected_hops"],
                "expected_hop_length_m": case["expected_hop_length_m"],
                "unique_modems": case["unique_modems"],
                "link_endpoint_modems": case["link_endpoint_modems"],
                "rngstream": case["rngstream"],
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
    result = pd.DataFrame([rows[i] for i in sorted(rows)])
    result.to_csv(out_dir / "results.csv", index=False)
    print(f"{out_dir.name}: {len(result)} rows, "
          f"{int(result.failed.sum())} failures")
    return result


def summarize(raw: pd.DataFrame, out_path: Path) -> pd.DataFrame:
    rows = []
    metrics = ["pdr", "goodput_bps", "delay_mean_s", "energy_per_bit_uj"]
    good = raw[~raw.failed]
    for distance, group in good.groupby("total_distance"):
        row = {
            "technology": "acoustic_chain",
            "distance_m": distance,
            "repetitions": len(group),
            "hop_count": group.expected_hops.iloc[0],
            "hop_length_m": group.expected_hop_length_m.iloc[0],
            "unique_modems": group.unique_modems.iloc[0],
            "link_endpoint_modems": group.link_endpoint_modems.iloc[0],
            "slot_s": group.timing_slot_s.iloc[0],
            "airtime_s": group.timing_airtime_s.iloc[0],
            "propagation_s": group.timing_propagation_s.iloc[0],
            "frame_s": group.timing_frame_s.iloc[0],
        }
        for metric in metrics:
            values = group[metric]
            row[f"{metric}_mean"] = values.mean()
            row[f"{metric}_ci95"] = base.ci95(values)
            row[f"{metric}_std"] = values.std(ddof=1)
        if not np.isfinite(row["pdr_mean"]) or row["pdr_mean"] <= 0:
            for metric in ("delay_mean_s", "energy_per_bit_uj"):
                row[f"{metric}_mean"] = math.nan
                row[f"{metric}_ci95"] = math.nan
                row[f"{metric}_std"] = math.nan
        row["pdr_below_095"] = bool(row["pdr_mean"] < 0.95)
        rows.append(row)
    result = pd.DataFrame(rows).sort_values("distance_m")
    result.to_csv(out_path, index=False)
    return result


def recompute_energy(frame: pd.DataFrame, technology: str) -> pd.Series:
    if technology == "acoustic":
        tx, rx = ACOUSTIC_TX_W, ACOUSTIC_RX_W
    elif technology == "acoustic_chain":
        tx, rx = ACOUSTIC_TX_W, ACOUSTIC_RX_W
    else:
        tx, rx = OPTICAL_TX_W, OPTICAL_RX_W
    bits = frame.delivered_packets * frame.packet_size * 8.0
    energy = ((frame.tx_events * tx + frame.rx_events * rx)
              * frame.timing_airtime_s)
    return energy / bits * 1e6


def grouped_metric(frame: pd.DataFrame, value_column: str,
                   ci_column: str) -> pd.DataFrame:
    rows = []
    for (technology, distance), group in frame.groupby(
            ["technology", "distance_m"]):
        values = group[value_column]
        row = {
            "technology": technology,
            "distance_m": distance,
            "mean": values.mean(),
            "ci95": base.ci95(values),
        }
        if (row["mean"] == 0 or not np.isfinite(row["mean"])) and \
                value_column in ("delay_mean_s", "energy_per_bit_uj"):
            row["mean"] = math.nan
            row["ci95"] = math.nan
        rows.append(row)
    return pd.DataFrame(rows)


def load_paper_frame(m3_summary: pd.DataFrame) -> pd.DataFrame:
    m1 = pd.read_csv(ROOT / "results_m1" / "results.csv")
    m1 = m1[m1.technology.isin(("acoustic", "optical"))].copy()
    m1 = m1[m1.total_distance.isin(DISTANCES)].copy()
    m1["distance_m"] = m1.total_distance
    m1["unique_modems"] = m1.hop_count + 1
    m1["link_endpoint_modems"] = 2 * m1.hop_count
    m1.loc[m1.technology == "acoustic", "unique_modems"] = 2
    m1.loc[m1.technology == "acoustic", "link_endpoint_modems"] = 2
    m1["energy_full_uj_bit"] = np.nan
    for technology in ("acoustic", "optical"):
        mask = m1.technology == technology
        m1.loc[mask, "energy_full_uj_bit"] = recompute_energy(
            m1.loc[mask], technology)

    m3 = pd.read_csv(OUT / "main" / "results.csv")
    m3["distance_m"] = m3.total_distance
    m3["energy_full_uj_bit"] = recompute_energy(m3, "acoustic_chain")

    columns = ["technology", "distance_m", "pdr", "goodput_bps",
               "delay_mean_s", "energy_full_uj_bit", "unique_modems",
               "link_endpoint_modems", "hop_count", "hop_length"]
    return pd.concat([m1[columns], m3[columns]], ignore_index=True)


def metric_table(frame: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for (technology, distance), group in frame.groupby(
            ["technology", "distance_m"]):
        row = {
            "technology": technology,
            "distance_m": distance,
            "repetitions": len(group),
            "hop_count": group.hop_count.iloc[0],
            "unique_modems": group.unique_modems.iloc[0],
            "link_endpoint_modems": group.link_endpoint_modems.iloc[0],
        }
        for metric, source in (
                ("pdr", "pdr"),
                ("delay_mean_s", "delay_mean_s"),
                ("energy_per_bit_uj", "energy_full_uj_bit")):
            values = group[source].dropna()
            row[f"{metric}_mean"] = values.mean() if len(values) else math.nan
            row[f"{metric}_ci95"] = base.ci95(values) if len(values) else math.nan
        rows.append(row)
    result = pd.DataFrame(rows).sort_values(["distance_m", "technology"])
    result["pdr_below_095"] = result.pdr_mean < 0.95
    return result


def write_parameters(paper_dir: Path) -> None:
    values = [
        ("acoustic_bitrate", "20768", "bit/s", "UW/PHYSICAL BitRate_"),
        ("acoustic_frequency", "50000", "Hz", "acoustic carrier"),
        ("acoustic_bandwidth", "26000", "Hz", "acoustic signal bandwidth"),
        ("acoustic_source_level", "180", "dB re 1 uPa at 1 m", "MaxTxSPL_dB_"),
        ("acoustic_acquisition_threshold", "0", "dB", "0 dB exposes BPSK PER curve"),
        ("acoustic_spreading", "2", "-", "practical spreading coefficient"),
        ("acoustic_tx_power", "20", "W", "analytical energy assumption"),
        ("acoustic_rx_power", "4", "W", "analytical energy assumption"),
        ("optical_bitrate", "1000000", "bit/s", "UW/OPTICAL/PHY BitRate_"),
        ("optical_wavelength", "395", "nm", "frequency 7.59e14 Hz"),
        ("optical_tx_power", "10", "W", "configured TxPower_"),
        ("optical_rx_power", "1.5", "W", "analytical energy assumption"),
        ("optical_acquisition_threshold", "15", "dB", "AcquisitionThreshold_dB_"),
        ("optical_divergence_half_angle", "0.524", "rad", "theta"),
        ("clear_water_c", "0.3", "1/m", "baseline water type"),
        ("optical_hop_clear_water", "20", "m", "80% of measured 25 m max"),
        ("tdma_guard", "0.001", "s", "common fixed guard"),
        ("tdma_packets_per_slot", "1", "-", "both technologies"),
        ("payload", "125", "byte", "application payload"),
        ("traffic_model", "Poisson", "-", "mean period 5.0 s"),
        ("simulation_time", "100", "s", "main runs"),
        ("seeds", "10", "-", "RNG substream repetitions"),
        ("depth", "-10", "m", "shared horizontal chain"),
    ]
    table = pd.DataFrame(values, columns=["parameter", "value", "units", "note"])
    table.to_csv(paper_dir / "parameters.csv", index=False)
    with (paper_dir / "parameters.md").open("w", encoding="utf-8") as handle:
        handle.write("# Frozen paper parameters\n\n")
        handle.write("```\n")
        handle.write(table.to_string(index=False))
        handle.write("\n```\n")


def plot_distance(table: pd.DataFrame, paper_dir: Path) -> None:
    colors = {"acoustic": "tab:orange", "acoustic_chain": "tab:brown",
              "optical": "tab:blue"}
    labels = {"acoustic": "Direct acoustic",
              "acoustic_chain": "Acoustic equal-hop chain",
              "optical": "Optical scaled-hop chain"}
    styles = {"acoustic": "s-", "acoustic_chain": "d--", "optical": "o-"}
    specs = [
        ("pdr_mean", "pdr_ci95", "PDR (%)", 100.0, False),
        ("delay_mean_s_mean", "delay_mean_s_ci95", "Mean delay (s)", 1.0, True),
        ("energy_per_bit_uj_mean", "energy_per_bit_uj_ci95",
         "Energy per delivered bit (uJ/bit)", 1.0, True),
        ("unique_modems", None, "Unique modems", 1.0, False),
    ]
    fig, axes = plt.subplots(2, 2, figsize=(12, 8), dpi=160)
    for ax, (metric, ci_metric, ylabel, scale, logy) in zip(
            axes.flat, specs):
        for technology in ("acoustic", "acoustic_chain", "optical"):
            g = table[table.technology == technology].sort_values("distance_m")
            y = g[metric] * scale
            if metric == "unique_modems":
                ax.plot(g.distance_m, y, styles[technology],
                        color=colors[technology], label=labels[technology])
            else:
                below = (g.pdr_below_095 if metric != "unique_modems"
                         else pd.Series(False, index=g.index))
                normal = ~below
                ax.errorbar(g.loc[normal, "distance_m"], y[normal],
                            yerr=g.loc[normal, ci_metric] * scale,
                            fmt=styles[technology], color=colors[technology],
                            label=labels[technology], capsize=3)
                ax.errorbar(g.loc[below, "distance_m"], y[below],
                            yerr=g.loc[below, ci_metric] * scale,
                            fmt=styles[technology], markerfacecolor="none",
                            color=colors[technology], capsize=3)
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
        if metric == "unique_modems":
            ax.set_yscale("log")
            ax.text(0.02, 0.05, "relay chains overlap",
                    transform=ax.transAxes, fontsize=7)
        ax.legend(fontsize=8)
    fig.suptitle("Paper baseline: direct acoustic vs equal-hop controls")
    fig.tight_layout()
    fig.savefig(paper_dir / "fig_distance.png", bbox_inches="tight")
    plt.close(fig)


def plot_regime_maps(paper_dir: Path) -> None:
    summary = pd.read_csv(ROOT / "results_m2" / "main" / "summary.csv")
    calibration = pd.read_csv(ROOT / "results_m2" / "calibration.csv").drop_duplicates("water_c")
    c_values = sorted(summary.water_c.dropna().unique())
    distances = sorted(summary.distance_m.unique())
    fig, axes = plt.subplots(1, 2, figsize=(13, 5), dpi=160)
    for ax, metric, title in zip(
            axes,
            ["delay_mean_s_mean", "energy_per_bit_uj_mean"],
            ["Delay ratio: acoustic / optical",
             "Energy ratio: acoustic / optical"]):
        a = summary[summary.technology == "acoustic"].pivot(
            index="water_c", columns="distance_m", values=metric)
        o = summary[summary.technology == "optical"].pivot(
            index="water_c", columns="distance_m", values=metric)
        status = summary[summary.technology == "optical"].pivot(
            index="water_c", columns="distance_m", values="status")
        ratio = a / o
        arr = ratio.to_numpy(dtype=float)
        image = ax.imshow(
            arr, aspect="auto", origin="lower",
            extent=[min(distances) - 25, max(distances) + 25,
                    min(c_values) - 0.1, max(c_values) + 0.1],
            cmap="coolwarm", vmin=0, vmax=max(2.0, np.nanmax(arr)))
        fig.colorbar(image, ax=ax, label="ratio (>1 favors optical)")
        for c in ratio.index:
            for d in ratio.columns:
                state = status.loc[c, d]
                if state == "INFEASIBLE":
                    ax.text(d, c, "INFEASIBLE", ha="center", va="center",
                            fontsize=7, rotation=45)
                elif np.isfinite(ratio.loc[c, d]):
                    ax.text(d, c, f"{ratio.loc[c, d]:.1f}", ha="center",
                            va="center", fontsize=8)
        ax.set_xlabel("Distance (m)")
        ax.set_ylabel("c (1/m)")
        ax.set_title(title)
    fig.tight_layout()
    fig.savefig(paper_dir / "fig_regime_maps.png", bbox_inches="tight")
    plt.close(fig)


def plot_hop_hardware(paper_dir: Path) -> None:
    calibration = pd.read_csv(ROOT / "results_m2" / "calibration.csv").drop_duplicates("water_c")
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
    for c, value, ok in zip(calibration.water_c, unique, feasible):
        ax.annotate(f"{int(value)}", (c, value), textcoords="offset points",
                    xytext=(0, 7), ha="center", fontsize=8)
    ax.set_xlabel("c (1/m)")
    ax.set_ylabel("Unique optical modems at D=1000 m")
    ax.set_yscale("log")
    ax.grid(True, which="both", linestyle=":", alpha=0.6)
    ax.legend(fontsize=8)
    fig.tight_layout()
    fig.savefig(paper_dir / "fig_hop_hardware.png", bbox_inches="tight")
    plt.close(fig)


def plot_energy(paper_dir: Path) -> None:
    energy = pd.read_csv(ROOT / "results_m2" / "energy_sensitivity.csv")
    cross = pd.read_csv(ROOT / "results_m2" / "energy_crossovers.csv")
    fig, ax = plt.subplots(figsize=(9, 5), dpi=160)
    colors = {"acoustic": "tab:orange", "optical": "tab:blue"}
    for technology in ("acoustic", "optical"):
        g = energy[energy.technology == technology].sort_values("distance_m")
        ax.plot(g.distance_m, g.baseline_uj_bit_mean, "o-",
                color=colors[technology], label=f"{technology} baseline")
        ax.fill_between(g.distance_m, g.band_min_uj_bit_mean,
                        g.band_max_uj_bit_mean, color=colors[technology],
                        alpha=0.16, label=f"{technology} +/-50% power")
    acoustic = energy[energy.technology == "acoustic"].sort_values("distance_m")
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
    fig.savefig(paper_dir / "fig_energy_sensitivity.png", bbox_inches="tight")
    plt.close(fig)


def write_claims(table: pd.DataFrame, paper_dir: Path) -> None:
    def get(technology, distance, metric):
        row = table[(table.technology == technology)
                    & (table.distance_m == distance)]
        return row[metric].iloc[0] if len(row) else math.nan

    lines = [
        "# Paper claims and caveats",
        "",
        "## Defensible claims",
        "",
        "1. In the feasible optical region, scaled-hop optical delivers all "
        "packets with much lower delay and analytical energy per delivered "
        "bit than direct acoustic communication.",
        "2. The optical advantage is not free: unique relay hardware grows "
        "with distance and with turbidity, and three high-turbidity/long-"
        "distance cells are infeasible under the 100-hop cap.",
        "3. The acoustic equal-hop control separates technology from "
        "topology: relaying an acoustic packet through the same number of "
        "hops is much slower and more energy-intensive than the optical chain.",
        "4. Direct acoustic remains the lowest-hardware option and is "
        "lossless through 1000 m in the configured model; it degrades near "
        "1500 m.",
        "",
        "## Key numbers",
        "",
        f"- At 100 m: direct acoustic delay {get('acoustic', 100.0, 'delay_mean_s_mean'):.3f} s, "
        f"acoustic chain {get('acoustic_chain', 100.0, 'delay_mean_s_mean'):.3f} s, "
        f"optical {get('optical', 100.0, 'delay_mean_s_mean'):.3f} s.",
        f"- At 1000 m: direct acoustic delay {get('acoustic', 1000.0, 'delay_mean_s_mean'):.3f} s, "
        f"acoustic chain {get('acoustic_chain', 1000.0, 'delay_mean_s_mean'):.3f} s, "
        f"optical {get('optical', 1000.0, 'delay_mean_s_mean'):.3f} s.",
        f"- At 1000 m, unique modems: direct acoustic 2, acoustic chain "
        f"{get('acoustic_chain', 1000.0, 'unique_modems'):.0f}, optical "
        f"{get('optical', 1000.0, 'unique_modems'):.0f}.",
        f"- Acoustic-chain PDR is "
        f"{get('acoustic_chain', 500.0, 'pdr_mean'):.2f} at 500 m and "
        f"{get('acoustic_chain', 1000.0, 'pdr_mean'):.2f} at 1000 m; the "
        f"loss is recorded at the first hop while all downstream edges are "
        f"1.0, so it is a TDMA slot-boundary artifact rather than range loss.",
        "",
        "## Caveats",
        "",
        "- Energy is analytical from MAC TX/RX event counts and assumed "
        "powers, not simulated modem energy. The +/-50% power envelope and "
        "the distance-scaled acoustic TX case are sensitivity analyses.",
        "- The optical channel is deterministic threshold behavior: no "
        "time-varying fading, turbulence, or independent node misalignment.",
        "- Beam-LUT mode is excluded from the paper dataset.",
        "- The acoustic chain is an equal-topology ablation, not an "
        "acoustic deployment recommendation. Its non-monotonic PDR at "
        "500/1000 m is a model artifact and must not be read as a physical "
        "range curve.",
        "- The M1/M2 `2*hops` modem count is a link-endpoint count; the "
        "paper uses `hops+1` unique modems and reports both in the derived "
        "data.",
    ]
    (paper_dir / "claims_and_caveats.md").write_text(
        "\n".join(lines) + "\n", encoding="utf-8")


def paper_assets() -> None:
    paper_dir = OUT / "paper"
    paper_dir.mkdir(parents=True, exist_ok=True)
    m3_summary = pd.read_csv(OUT / "main" / "summary.csv")
    frame = load_paper_frame(m3_summary)
    table = metric_table(frame)
    table.to_csv(paper_dir / "main_results.csv", index=False)
    with (paper_dir / "main_results.md").open("w", encoding="utf-8") as handle:
        handle.write("# Main paper results\n\n```\n")
        handle.write(table.to_string(index=False))
        handle.write("\n```\n")
    write_parameters(paper_dir)
    plot_distance(table, paper_dir)
    plot_regime_maps(paper_dir)
    plot_hop_hardware(paper_dir)
    plot_energy(paper_dir)
    write_claims(table, paper_dir)
    print(f"paper assets: {paper_dir}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Run milestone 3.")
    parser.add_argument("--pilot", action="store_true")
    parser.add_argument("--main", action="store_true")
    parser.add_argument("--paper", action="store_true")
    parser.add_argument("--all", action="store_true")
    args = parser.parse_args()
    OUT.mkdir(exist_ok=True)
    if args.pilot or args.all:
        pilot = run_grid(OUT / "pilot", PILOT_SEEDS, PILOT_STOP_S)
        summarize(pilot, OUT / "pilot" / "summary.csv")
        print("pilot maximum runtime (s):", pilot.runtime_s.max())
    if args.main or args.all:
        raw = run_grid(OUT / "main", MAIN_SEEDS, MAIN_STOP_S)
        summarize(raw, OUT / "main" / "summary.csv")
        print("main maximum runtime (s):", raw.runtime_s.max())
    if args.paper or args.all:
        paper_assets()


if __name__ == "__main__":
    main()
