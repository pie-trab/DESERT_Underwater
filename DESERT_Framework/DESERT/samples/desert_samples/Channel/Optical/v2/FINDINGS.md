# Findings: v2 acoustic versus optical comparison

## 1. Scope and runs

The unchanged current sweep was run first, with no parameter changes:

- 5 sweeps, 37 configurations, 3 technologies, 30 RNG substreams;
- 3,330 simulations, 1,000 s stop time, zero failed runs;
- output: `results_current_baseline/`;
- 180 runs at offered periods 0.005 and 0.01 s have the known CBR
  sequence-number-wrap censoring. The primary PDR/goodput values below use
  destination-MAC delivery, not the censored application counter.

The diagnostic runs and additional experiments were recorded in `NOTES.md`.
The pilot contained 150 runs (2 seeds, 20 s); the focused run contained 930
runs (10 seeds, 100 s), all with zero failures and no application-counter
censoring.

## 2. The scenarios really are different

The output-only instrumentation confirmed the instantiated objects and
effective settings:

| scenario | PHY | channel | propagation | relevant settings |
|---|---|---|---|---|
| acoustic | `Module/UW/PHYSICAL` | `Module/UnderwaterChannel` | `MPropagation/Underwater` | 20,768 bit/s; 0 dB acquisition; 0.1 s frame; 1 packet/slot |
| plain optical | `Module/UW/OPTICAL/PHY` | `Module/UW/Optical/Channel` | `Module/UW/OPTICAL/Propagation` | 1 Mbit/s; 10 W; 15 dB acquisition; c=0.3; 0.1 s frame; 2 packets/slot |
| beam optical | `Module/UW/UWOPTICALBEAMPATTERN` | `Module/UW/Optical/Channel` | `Module/UW/OPTICAL/Propagation` | same values, `beam_mode=1`, LUT hardware branch |

Representative diagnostic output is in `diagnostic_*.log`. At 50 m total
distance, the acoustic run delivered 74/74 packets; both optical runs
delivered 90/90, with every optical node transmitting/receiving the same
count. Thus the scenario switch is not being ignored.

## 3. Why many old results were identical

The scenarios are not generally identical. Equality occurs for identifiable
reasons:

### Lossless, below-capacity regimes

At 20--60 m total distance, all three technologies deliver every packet.
PDR is therefore exactly 1. Goodput is just the offered payload rate, so it
is also nearly equal. This says nothing about equal PHY performance. Delay is
already different: at 60 m it is 138.1 +/- 0.6 ms acoustic versus 88.5 +/-
0.2 ms optical. Energy is 1,155.6 versus 34.5 uJ/bit under the analytical
power assumptions.

The same effect appears at offered periods 0.25, 0.5 and 1.0 s, and for
payloads 64--250 bytes: PDR and goodput are load-controlled, while delay and
energy remain different.

### Optical and beam optical share the same successful path

In clear water and below the beam/range threshold, plain and beam optical
have identical per-repetition sent counts, MAC counters, delivery counts,
delay and analytical energy. The baseline has zero sent-count mismatches
between the two optical variants. At 80 m total distance, for example, the
plain PHY transmits 408 packets and receives zero at the first hop, whereas
the beam PHY transmits and receives all 408 packets on all three edges. The
difference appears only when the hardware-specific range model is active.

### Saturation hides the PHY

At high offered load, both systems can be queue-limited. The limits are not
the same, however: with the configured MAC settings, acoustic service is
approximately 10 packets/s and optical service approximately 20 packets/s.
At periods below about 0.05 s, the counters show queue drops and no air loss;
the goodput ceiling is therefore a MAC/bit-rate result, not a propagation
result. The two optical variants remain identical because they use the same
TDMA schedule and both links are reliable in that configuration.

### The energy metric is computed, not simulated

The runner computes energy from MAC TX/RX event counts, packet airtime and
assumed powers. It does not read simulated modem energy. Therefore equal
optical event counts necessarily produce equal optical energy/bit. The large
acoustic/optical difference is expected from the configured 20 W/4 W acoustic
and 10 W/1.5 W optical assumptions, the bit rates, and the number of hops;
it is not an independent PHY measurement.

### Random seeds are applied, but many channel outcomes are deterministic

The minimum number of distinct sent counts over the baseline groups was 25
out of 30 repetitions, proving that Poisson traffic and RNG substreams are
being applied. Nevertheless, PDR has zero across-seed variance in 27/37
acoustic groups and 33/37 groups for each optical variant. This is expected
when the configured channel is either far above threshold (all packets pass)
or below an acquisition/range cliff (all packets fail). The zero variance is
not evidence that the seed is ignored.

### Metrics share a delivery source

PDR and goodput are both based on destination-MAC delivery. Consequently,
they must be identical in any configuration with the same delivered count.
Delay is the sink CBR forward-trip statistic. At no-delivery points delay and
energy/bit are undefined; the summary CSV fills missing values with zero for
plotting, so those zeros must not be interpreted as measured zero latency or
energy.

Packet conservation is exact in the baseline: the maximum residual in
`sent = delivered + queue drops + residual queue + PHY loss` is zero.

## 4. Baseline identity check

The requested rule was applied: a metric is flagged when the mean difference
is below 2% **or** the 95% confidence intervals overlap. There are 37 sweep
configurations. Counts are:

| pair | PDR flagged | delay flagged | goodput flagged | energy/bit flagged |
|---|---:|---:|---:|---:|
| acoustic vs plain optical | 18/37 | 1/37 | 18/37 | 0/37 |
| acoustic vs beam optical | 22/37 | 1/37 | 22/37 | 0/37 |
| plain vs beam optical | 33/37 | 33/37 | 33/37 | 33/37 |

The acoustic/optical PDR and goodput flags are concentrated in lossless or
load-controlled cases. The acoustic/optical delay and energy metrics remain
different wherever they are defined. Plain/beam flags are mostly genuine
same-outcome cases; the zero-delivery cases are formally flagged by equal
summary zeros but have undefined delay and energy.

## 5. What actually differs

Values are mean +/- 95% CI from the 30-seed baseline unless marked
“focused”.

| configuration | acoustic | plain optical | beam optical |
|---|---|---|---|
| distance 60 m: PDR / delay / energy | 100% / 138.1+/-0.6 ms / 1155.6 | 100% / 88.5+/-0.2 ms / 34.5 | 100% / 88.5+/-0.2 ms / 34.5 |
| distance 80 m: PDR / goodput | 100% / 3999+/-25 bit/s | 0% / 0 | 100% / 3980+/-26 bit/s |
| distance 1400 m: PDR / delay / energy | 95.4+/-0.2% / 1031+/-1 ms / 1201.7+/-1.6 | 0% / undefined / undefined | 0% / undefined / undefined |
| distance 1500 m: PDR / goodput / energy | 23.1+/-0.2% / 926+/-10 bit/s / 4357+/-41 | 0% / 0 / undefined | 0% / 0 / undefined |
| load period 0.05 s: PDR / goodput / delay | 50.1+/-0.2% / 10008+/-0.3 / 6379+/-1 ms | 98.5+/-0.2% / 19668+/-35 / 836+/-27 ms | same as plain |
| load period 0.10 s: PDR / goodput / delay | 99.2+/-0.2% / 9907+/-22 / 2909+/-280 ms | 100% / 9981+/-37 / 104+/-0.4 ms | same as plain |
| relay count 3 at 100 m: delay / energy | 165+/-1 ms / 1155.6 | 103+/-0 ms / 46.0 | same as plain |
| relay count 5 at 100 m: delay / energy | 165+/-1 ms / 1155.6 | 121+/-0 ms / 69.0 | same as plain |
| turbidity c=0.8: PDR | 100% | 0% | 100% |

The focused 10-seed run sharpens the transitions without application-counter
censoring:

| focused configuration | acoustic PDR | plain optical PDR | beam optical PDR |
|---|---:|---:|---:|
| distance 75 m | 100% | 100% | 100% |
| distance 80 m | 100% | 0% | 100% |
| distance 85 m | 100% | 0% | 100% |
| distance 90 m | 100% | 0% | 0% |
| load period 0.04 s | 41.0+/-0.7% | 81.3+/-0.8% | 81.3+/-0.8% |
| load period 0.075 s | 77.2+/-0.9% | 100% | 100% |
| load period 0.10 s | 98.8+/-1.3% | 100% | 100% |
| turbidity c=0.5 | 100% | 100% | 100% |
| turbidity c=0.6--1.6 | 100% | 0% | 100% |
| turbidity c=2.0 | 100% | 0% | 0% |

The focused distance and turbidity failures are PHY losses rather than MAC
losses. At focused distance 80 m, mean plain-optical PHY loss is 397.3
packets/run with zero downstream transmissions; beam optical has zero PHY
loss. At c=0.6 the same first-hop pattern occurs. At load period 0.04 s,
PHY loss is zero for all technologies, while queue drops average 1393
acoustic, versus 454 optical packets/run: this is a capacity/queue result.

## 6. Candidate comparisons for the exam paper

### 1. Offered load: capacity and delay crossover — recommended

**Plot:** [`focused_results/plots/focused_offered_load.png`](focused_results/plots/focused_offered_load.png)

Use 50 m total distance, two optical relays, and periods 0.04--0.20 s.
Optical has roughly twice the configured service ceiling. Around 0.05--0.10
s it simultaneously has higher PDR, higher goodput and much lower queueing
delay. At 0.15--0.20 s both deliver all packets and the goodput curves
converge to the offered load, while optical retains a lower delay and energy
per delivered bit. This is the clearest result, but it is a configured
bit-rate/TDMA comparison rather than a pure propagation comparison.

### 2. Distance: acoustic robustness versus optical range — strong

**Plot:** [`focused_results/plots/focused_distance.png`](focused_results/plots/focused_distance.png)

Use 65--105 m with two optical relays. Plain optical fails at the 26.667 m
hop, while beam optical survives the 30 m hop at 90 m total only marginally
and fails there in this run; the pilot and focused run show deterministic
cliffs. Acoustic remains lossless throughout this range and has increasing
propagation delay. The baseline extension to 1400--1500 m then shows the
acoustic PER knee. This is physically interpretable for the configured
models, but the optical cliff is abrupt and not a fading model.

### 3. Turbidity: hardware sensitivity and beam-LUT benefit — strong with caveat

**Plot:** [`focused_results/plots/focused_turbidity.png`](focused_results/plots/focused_turbidity.png)

At 16.667 m optical hops, plain optical fails from c=0.6 in the focused
grid, while beam optical survives through c=1.6 and fails at c=2.0. Acoustic
is intentionally invariant to optical turbidity. The first-hop counters
prove that the effect is optical PHY attenuation, not queueing. This is an
interesting sensitivity result, but beam mode uses the known DESERT noise/LUT
implementation and should not be presented as validated hardware data until
that model is independently corrected or calibrated.

### 4. Relay density at fixed 100 m: energy-delay trade-off — useful secondary

**Plot:** [`results_current_baseline/v2_relay_count_fixed_100m.png`](results_current_baseline/v2_relay_count_fixed_100m.png)

The optical chain is infeasible with one or two relays, then delivers 100%
with three to five. Once feasible, every added relay increases optical energy
from 46.0 to 69.0 uJ/bit and delay from 103 to 121 ms. Acoustic is unchanged
because its `n_relays` argument is deliberately ignored. This is a clear
optical deployment trade-off, but it is not an apples-to-apples relay-count
comparison until an acoustic multihop baseline is added.

### 5. Divergence-angle control: negative result / exclusion test

**Plot:** [`focused_results/plots/focused_theta.png`](focused_results/plots/focused_theta.png)

Changing theta from 0.174 to 0.698 rad at 20 m optical hops changed none of
the measured outcomes. The link is too far inside its configured range for
this parameter to matter. More importantly, v2 fixes beam inclination at
zero and does not implement independent node misalignment. This should be
reported as a model limitation, not as evidence that alignment is
irrelevant.

The plots use bounded linear PDR scales and fitted goodput axes; delay and
energy use logarithmic/symmetric-log scaling where required. Zero-delivery
points have undefined delay and energy and are not interpreted as zero
physical delay/energy.

## 7. Recommended story and caveats

The defensible short-paper story is:

> Under the configured DESERT v2 models, single-head optical multihop is
> substantially faster and less energy-intensive than direct acoustic
> communication whenever every optical hop remains inside its usable range.
> Optical also supports roughly twice the offered packet rate in this TDMA
> configuration. Acoustic is more robust outside the optical range and has a
> gradual long-range PER transition, whereas optical failure is dominated by
> deterministic per-hop link-budget cliffs. Beam-mode hardware extends the
> usable optical region but does not remove the range-density trade-off.

This story is supported by different counters, confidence intervals and
effective class names; the equal results are limited to saturated, lossless,
or threshold-inactive regimes.

The main caveats are:

1. Acoustic is direct while optical is multihop, and their configured PHY
   rates and packets-per-slot differ (20,768 versus 1,000,000 bit/s; 1 versus
   2 packets/slot).
2. Energy/bit is an analytical assumption, not simulated modem energy.
3. Optical channel behavior is deterministic threshold behavior; there is no
   time-varying fading, turbulence, or independent node misalignment.
4. Beam optical relies on the existing LUT/noise implementation, whose
   physical calibration remains a limitation.
5. The high-load application counter wraps at 65,536 packets; those points
   must use destination-MAC delivery and should not use raw CBR delay/counters
   without the stated censoring qualification.
6. The acoustic `MaxTxRange_ = 200` setting is printed for traceability but is
   not a hard reception cutoff in this DESERT implementation; the long-range
   acoustic behavior comes from the configured propagation/SNR/PER model.
