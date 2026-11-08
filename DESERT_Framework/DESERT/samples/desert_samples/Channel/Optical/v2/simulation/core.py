#!/usr/bin/env python3
"""Shared simulation primitives for the consolidated acoustic/optical study."""

from __future__ import annotations

import concurrent.futures
import math
import re
import shlex
import subprocess
import time
from pathlib import Path

import pandas as pd

SCRIPT_DIR = Path(__file__).resolve().parent
V2 = SCRIPT_DIR.parent
REPO_ROOT = V2.parents[6]
ENV_PATH = REPO_ROOT / "DESERT_buildCopy_LOCAL" / "environment"
SCENARIOS = SCRIPT_DIR / "scenarios"
DATA = SCRIPT_DIR / "data"
FINAL = DATA / "final"
RAW = DATA / "raw"
PAPER = V2 / "paper"

SCENARIO_FILES = {
    "acoustic": SCENARIOS / "acoustic_direct.tcl",
    "optical": SCENARIOS / "optical_chain.tcl",
    "acoustic_chain": SCENARIOS / "acoustic_chain.tcl",
}

BASE = {
    "cbr_period": 5.0,
    "packet_size": 125,
    "depth": -10.0,
    "start_time": 0.1,
    "stop_time": 100.0,
    "poisson_traffic": 1,
    "attenuation_c": 0.3,
    "optical_txpower": 10.0,
    "optical_threshold": 15.0,
    "optical_theta": 0.524,
}
BITRATE = {"acoustic": 20768.0, "optical": 1.0e6,
           "acoustic_chain": 20768.0}
POWER = {"acoustic": (20.0, 4.0), "optical": (10.0, 1.5),
         "acoustic_chain": (20.0, 4.0)}

SENT_RE = re.compile(r"^sent_packets:\s*([0-9]+)$", re.MULTILINE)
RECEIVED_RE = re.compile(r"^received_packets:\s*([0-9]+)$", re.MULTILINE)
FTT_RE = re.compile(r"^ftt_mean_s:\s*([-+0-9.eE]+)$", re.MULTILINE)
FTT_STD_RE = re.compile(r"^ftt_std_s:\s*([-+0-9.eE]+)$", re.MULTILINE)
CBR_THR_RE = re.compile(r"^cbr_thr_bps:\s*([-+0-9.eE]+)$", re.MULTILINE)
TIMING_RE = re.compile(r"^TDMA timing:\s*(.*)$", re.MULTILINE)
NODE_RE = re.compile(
    r"^\s*node (\d+): mac_tx=(\d+)\s+"
    r"mac_rx=(\d+)\s+up_rx=(\d+)\s+q_final=([0-9]+)\s*$",
    re.MULTILINE,
)

T_CRIT_95 = {
    1: 12.706, 2: 4.303, 3: 3.182, 4: 2.776, 5: 2.571, 6: 2.447,
    7: 2.365, 8: 2.306, 9: 2.262, 10: 2.228, 11: 2.201, 12: 2.179,
    13: 2.160, 14: 2.145, 15: 2.131, 16: 2.120, 17: 2.110,
    18: 2.101, 19: 2.093, 20: 2.086, 21: 2.080, 22: 2.074,
    23: 2.069, 24: 2.064, 25: 2.060, 26: 2.056, 27: 2.052,
    28: 2.048, 29: 2.045, 30: 2.042, 40: 2.021, 50: 2.009,
    60: 2.000, 100: 1.984,
}


def t_crit_95(df: int) -> float:
    if df in T_CRIT_95:
        return T_CRIT_95[df]
    if df <= 1:
        return 12.706
    if df >= 100:
        return 1.96
    keys = sorted(T_CRIT_95)
    for k0, k1 in zip(keys, keys[1:]):
        if k0 <= df <= k1:
            f = (df - k0) / (k1 - k0)
            return T_CRIT_95[k0] * (1 - f) + T_CRIT_95[k1] * f
    return 1.96


def ci95(series: pd.Series) -> float:
    s = series.dropna()
    n = len(s)
    if n <= 1:
        return 0.0
    std = s.std(ddof=1)
    if not math.isfinite(std) or std == 0:
        return 0.0
    return t_crit_95(n - 1) * std / math.sqrt(n)


def build_args(technology: str, case: dict) -> list:
    cbr = case["cbr_period"]
    packet = case["packet_size"]
    depth = case["depth"]
    stop = case["stop_time"]
    rng = case["rngstream"]
    poisson = case["poisson_traffic"]
    if technology == "acoustic":
        return [0, cbr, packet, case["total_distance"], depth, stop,
                rng, poisson]
    if technology == "acoustic_chain":
        return [case["n_relays"], cbr, packet, case["total_distance"],
                depth, stop, rng, poisson]
    if technology == "optical":
        return [
            case["n_relays"], cbr, packet, case["hop_length"], depth, stop,
            rng, poisson, case.get("attenuation_scale", 1.0),
            case.get("optical_txpower", 10.0),
            case.get("optical_threshold", 15.0),
            case.get("optical_theta", 0.524), 0,
        ]
    raise ValueError(f"unknown technology: {technology}")


def run_case(technology: str, case: dict, log_path: Path) -> dict:
    sim_path = SCENARIO_FILES[technology]
    args = build_args(technology, case)
    command = "source {env} && ns {sim} {args}".format(
        env=shlex.quote(str(ENV_PATH.resolve())),
        sim=shlex.quote(str(sim_path.resolve())),
        args=" ".join(shlex.quote(str(a)) for a in args),
    )
    completed = subprocess.run(
        ["zsh", "-lc", command], cwd=V2, text=True,
        capture_output=True, check=False,
    )
    output = completed.stdout + completed.stderr
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text(output, encoding="utf-8")
    if completed.returncode != 0:
        raise RuntimeError(f"ns exited with {completed.returncode}")

    match = lambda regex: (lambda m: float(m.group(1)) if m else math.nan)(
        regex.search(output))
    timing_match = TIMING_RE.search(output)
    timing = {}
    if timing_match:
        for token in timing_match.group(1).split():
            if "=" in token:
                key, value = token.split("=", 1)
                try:
                    timing[key] = float(value)
                except ValueError:
                    timing[key] = value

    sent = match(SENT_RE)
    received = match(RECEIVED_RE)
    if math.isnan(sent) or math.isnan(received):
        raise RuntimeError("metrics block missing from ns output")

    hop_count = (1 if technology == "acoustic"
                 else int(case["n_relays"]) + 1)
    nodes = [(int(n), int(tx), int(rx), int(up), int(q))
             for n, tx, rx, up, q in NODE_RE.findall(output)]
    tx_by_node = {n: (tx, rx, up, q) for n, tx, rx, up, q in nodes}
    edge_pdrs = []
    for edge in range(hop_count):
        tx_n = tx_by_node.get(edge, (0, 0, 0, 0))[0]
        rx_n = tx_by_node.get(edge + 1, (0, 0, 0, 0))[1]
        edge_pdrs.append(rx_n / tx_n if tx_n else math.nan)
    finite_edges = [v for v in edge_pdrs if math.isfinite(v)]

    delivered = tx_by_node.get(hop_count, (0, 0, 0, 0))[1]
    delay = match(FTT_RE)
    delay_std = match(FTT_STD_RE)
    if delivered <= 0:
        delay = math.nan
        delay_std = math.nan

    tx_events = sum(tx for _, (tx, _, _, _) in tx_by_node.items())
    rx_events = sum(rx for _, (_, rx, _, _) in tx_by_node.items())
    airtime = timing.get("airtime_s")
    if not isinstance(airtime, float) or not math.isfinite(airtime):
        header_bytes = timing.get("header_bytes", 16.0)
        airtime = 8.0 * (case["packet_size"] + header_bytes) / BITRATE[technology]
    delivered_bits = delivered * case["packet_size"] * 8.0
    tx_w, rx_w = POWER[technology]
    energy = ((tx_events * tx_w + rx_events * rx_w) * airtime
              / delivered_bits * 1e6 if delivered_bits > 0 else math.nan)

    queue_drops = 0
    total_q_final = 0
    for node_id, (_, _, up, q) in tx_by_node.items():
        total_q_final += q
        if node_id != hop_count:
            queue_drops += max(0, up - tx_by_node[node_id][0] - q)
    phy_lost = sent - delivered - queue_drops - total_q_final

    return {
        "technology": technology,
        "n_relays": case["n_relays"],
        "hop_count": hop_count,
        "total_distance": case["total_distance"],
        "hop_length": (case.get("hop_length", case["total_distance"])
                       if technology == "optical" else
                       case["total_distance"] / hop_count),
        "water_c": case.get("water_c", math.nan),
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
        "cbr_thr_bps": match(CBR_THR_RE),
        "delay_mean_s": delay,
        "delay_std_s": delay_std,
        "mean_edge_pdr": (sum(finite_edges) / len(finite_edges)
                          if finite_edges else math.nan),
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
        "unique_modems": hop_count + 1,
        "link_endpoint_modems": 2 * hop_count,
    }


def execute_cases(cases: list[dict], out_dir: Path, filename: str) -> pd.DataFrame:
    log_dir = out_dir / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    jobs = list(enumerate(cases))

    def execute(job):
        index, case = job
        technology = case["technology"]
        label = (f"{technology}_D{case['total_distance']:g}"
                 f"_C{case.get('water_c', 0):g}"
                 f"_R{case['rngstream']:02d}")
        log_path = log_dir / f"{index:05d}_{label}.log"
        started = time.monotonic()
        try:
            row = run_case(technology, case, log_path)
            row.update({
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
                "technology": technology,
                "n_relays": case["n_relays"],
                "hop_count": case["hop_count"],
                "total_distance": case["total_distance"],
                "hop_length": case.get("hop_length", math.nan),
                "water_c": case.get("water_c", math.nan),
                "rngstream": case["rngstream"],
                "unique_modems": 2 if technology == "acoustic"
                else case["n_relays"] + 2,
                "link_endpoint_modems": 2 if technology == "acoustic"
                else 2 * (case["n_relays"] + 1),
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


def summarize(raw: pd.DataFrame) -> pd.DataFrame:
    good = raw[~raw.failed].copy()
    if "water_c" not in good.columns:
        good["water_c"] = math.nan
    if "unique_modems" not in good.columns:
        good["unique_modems"] = good["hop_count"] + 1
    if "link_endpoint_modems" not in good.columns:
        good["link_endpoint_modems"] = 2 * good["hop_count"]
    tx_w = good["technology"].map(
        {"acoustic": 20.0, "optical": 10.0, "acoustic_chain": 20.0})
    rx_w = good["technology"].map(
        {"acoustic": 4.0, "optical": 1.5, "acoustic_chain": 4.0})
    delivered_bits = good["delivered_packets"] * good["packet_size"] * 8.0
    full_energy = ((good["tx_events"] * tx_w + good["rx_events"] * rx_w)
                   * good["timing_airtime_s"] / delivered_bits * 1e6)
    good["energy_full_uj"] = full_energy.where(delivered_bits > 0,
                                               math.nan)
    metrics = ["pdr", "goodput_bps", "delay_mean_s", "energy_full_uj"]
    rows = []
    for keys, group in good.groupby(["technology", "water_c", "total_distance"],
                                    dropna=False):
        technology, water_c, distance = keys
        row = {
            "technology": technology,
            "water_c": water_c,
            "distance_m": distance,
            "repetitions": len(group),
            "n_relays": group.n_relays.iloc[0],
            "hop_count": group.hop_count.iloc[0],
            "hop_length_m": group.hop_length.iloc[0],
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
            row[f"{metric}_ci95"] = ci95(values)
        if not math.isfinite(row["pdr_mean"]) or row["pdr_mean"] <= 0:
            for metric in ("delay_mean_s", "energy_full_uj"):
                row[f"{metric}_mean"] = math.nan
                row[f"{metric}_ci95"] = math.nan
        row["pdr_below_095"] = bool(row["pdr_mean"] < 0.95)
        row["status"] = "OK"
        rows.append(row)
    result = pd.DataFrame(rows)
    result = result.rename(columns={"energy_full_uj_mean":
                                     "energy_per_bit_uj_mean",
                                     "energy_full_uj_ci95":
                                     "energy_per_bit_uj_ci95"})
    return result
