# Milestone 4 findings: final paper package

## Scope

M4 is an output/finalization milestone. No new benchmark simulations were
run, no physical parameters were changed, and no M1/M2/M3 result directory
was modified. The paper package is under `results_m4/`.

## Acoustic-chain artifact verdict

The M3 acoustic equal-hop chain is quarantined as **diagnostic only**.

Evidence used:

- every generated packet has `mac_tx > 0` at the source;
- delivery losses are visible only at the first edge;
- every downstream edge has PDR 1.0;
- queue drops and residual queue occupancy are zero;
- the first hop is an ideal 20 m acoustic link.

This rules out acoustic range loss. The exact simulator mechanism is not
proven by the saved counters, so the final paper must use the weaker wording:

> first-hop simulation artifact; exact TDMA/forwarding mechanism unresolved.

The M3 phrase “TDMA slot-boundary artifact” is therefore not repeated as a
proven fact in the final paper assets. No trace-enabled diagnostic was added
because it would not change the decision to exclude the curve from headline
claims.

## Final paper split

### Headline

`results_m4/paper/fig_main_distance.png`

- direct acoustic;
- optical scaled-hop at c=0.3 1/m;
- no acoustic chain.

### Diagnostic appendix

`results_m4/paper/fig_chain_diagnostic.png`

- direct acoustic and optical shown as context;
- acoustic equal-hop chain marked diagnostic;
- open markers for PDR below 0.95;
- explicit note that the curve is not a physical PDR result.

## Final key numbers

| D (m) | Direct acoustic | Optical scaled-hop |
|---:|---|---|
| 100 | 100% / 0.150 s / 1303.5 uJ/bit / 2 modems | 100% / 0.0149 s / 64.9 uJ/bit / 6 modems |
| 1000 | 100% / 1.110 s / 1303.5 uJ/bit / 2 modems | 100% / 0.160 s / 648.6 uJ/bit / 51 modems |
| 1500 | 27.0 +/- 4.3% / 2.036 s / 2 modems | 100% / 0.239 s / 76 modems |

The acoustic-chain diagnostic is 0.682 PDR at 500 m and 0.586 at 1000 m;
those points are not used as physical evidence.

## Final package

- `results_m4/paper/fig_main_distance.png`
- `results_m4/paper/fig_chain_diagnostic.png`
- `results_m4/paper/fig_regime_maps.png`
- `results_m4/paper/fig_hop_hardware.png`
- `results_m4/paper/fig_energy_sensitivity.png`
- `results_m4/paper/main_results.csv` / `.md`
- `results_m4/paper/diagnostic_results.csv` / `.md`
- `results_m4/paper/parameters.csv` / `.md`
- `results_m4/paper/paper_summary.md`
- `results_m4/paper/claims_and_caveats.md`
- `results_m4/REPRODUCE.md`
- `checks/milestone4.sh`

`checks/milestone4.sh` verifies the M1--M3 regressions, headline/diagnostic
separation, unique-modem accounting, frozen parameters, artifact wording and
protected result directories.

## Recommended paper story

The defensible story is a deployment comparison, not an equal-topology
fairness claim:

> Scaled-hop optical communication gives much lower delay and analytical
> energy per delivered bit when every hop stays within its calibrated range,
> but it requires a rapidly growing number of relays. Direct acoustic needs
> only two modems and remains lossless through 1000 m in this model, though
> it degrades near 1500 m. The acoustic equal-hop control is diagnostic only
> because its first-hop simulator artifact prevents a physical PDR claim.

No open blocker. The dataset is paper-ready with the stated model
limitations. The next step is manuscript writing, not another simulation
milestone.
