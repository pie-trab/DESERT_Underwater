# Milestone 3 findings

## Scope

Milestone 3 adds the acoustic equal-hop chain and freezes the paper dataset.
No C++ or module source was changed. The previous result directories remain
untouched; all new output is in `results_m3/`.

- Acoustic equal-hop scenario: `acoustic_chain_v3.tcl`.
- Pilot: 2 seeds, 20 s, six distances, 12 runs, zero failures.
- Main: 10 seeds, 100 s, six distances, 60 runs, zero failures.
- Conservation residual is exactly zero in every run.
- `checks/milestone3.sh` prints PASS.

## Frozen paper parameters

- Acoustic PHY: 20,768 bit/s; 50 kHz; 180 dB re 1 uPa source level; 0 dB
  acquisition threshold.
- Optical PHY: 1 Mbit/s; 10 W transmit power; 15 dB acquisition threshold;
  c = 0.3 1/m baseline.
- Plain optical working hop at c=0.3: 20 m, which is 80% of the measured
  25 m maximum from M2.
- TDMA: 1 ms common guard, one packet per slot, slot and frame derived from
  full CBR/UDP/IP packet airtime plus one-hop propagation.
- Traffic: 125 byte payload, Poisson mean period 5 s, 100 s main run, 10
  seeds, depth -10 m.
- Beam mode and independent node misalignment are excluded from the paper
  dataset.

## Hardware accounting correction

The M1/M2 `modems = 2*hops` value is a link-endpoint count. It double-counts
intermediate relays. The physical count is `hops + 1`.

At 1000 m, c=0.3:

- direct acoustic: 2 unique modems;
- acoustic equal-hop chain: 51 unique modems;
- optical scaled-hop chain: 51 unique modems.

The paper assets use unique modems. M1/M2 data are unchanged and remain
valid for their original fields.

## Main paper numbers

| D (m) | Direct acoustic PDR / delay / energy | Acoustic chain | Optical scaled-hop |
|---:|---|---|---|
| 100 | 100% / 0.150 s / 1303.5 uJ/bit | 100% / 0.494 s / 6517.7 | 100% / 0.0149 s / 64.9 |
| 1000 | 100% / 1.110 s / 1303.5 | 58.6 +/- 4.4% / 8.842 s / 65960.6 | 100% / 0.160 s / 648.6 |
| 1500 | 27.0 +/- 4.3% / 2.036 s / 4434.4 | 100% / 18.837 s / 97765.8 | 100% / 0.239 s / 972.9 |

The acoustic-chain PDR points at 500 and 1000 m are below 0.95 and are shown
with open markers. Their delay is conditional on delivered packets and their
energy/bit includes transmissions of lost packets.

## Surprise and model artifact

The acoustic chain is lossless at 50--200 m and 1500 m but has PDR 0.68 at
500 m and 0.59 at 1000 m. This is not monotonic and is not an acoustic range
effect:

- source `mac_tx` equals the application sent count;
- the first edge PDR falls while every downstream edge is exactly 1.0;
- queue drops and final queue occupancy are zero;
- the first hop is a 20 m link with very high configured SNR.

The evidence therefore localizes every lost packet to source-to-first-relay
reception, not to propagation attenuation along the chain. The most likely
cause is a TDMA slot-boundary/forwarding artifact: a packet generated during
the source slot can start transmission late enough that its airtime plus
propagation crosses into the next relay's slot. The deterministic 20 m
acoustic link cannot explain a 30--40% first-hop loss. This must be reported
as a model limitation, not as a physical acoustic-range result. The acoustic
chain remains useful as an equal-topology ablation for delay and energy, but
its non-monotonic PDR is not a clean deployment curve.

At 1500 m the chain delivers every packet but with 18.8 s delay, because the
frame is 5.217 s and the source is close to its per-frame service ceiling.
This is a real consequence of the equal-hop topology and the TDMA schedule,
not a missing measurement.

## Paper-ready comparison

1. **Technology/topology ablation:** direct acoustic vs acoustic equal-hop
   chain vs optical scaled-hop chain at c=0.3.
   Plot: `results_m3/paper/fig_distance.png`.
2. **Relay cost:** unique modem count grows from 2 to 76 over 1500 m for
   both relay chains. Plot: `results_m3/paper/fig_hop_hardware.png`.
3. **Water-type sensitivity:** M2 hop calibration and delay/energy ratio
   maps. Plot: `results_m3/paper/fig_regime_maps.png`.
4. **Energy assumptions:** baseline, +/-50% power envelope and
   distance-scaled acoustic TX. Plot:
   `results_m3/paper/fig_energy_sensitivity.png`.

The paper should not claim that the acoustic equal-hop PDR is a physical
range result at 500/1000 m. The defensible claims are about delay, energy,
hardware count and the failure of ideal-topology assumptions; PDR for optical
is clean across all feasible M2 cells.
