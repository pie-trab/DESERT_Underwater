# Milestone 1 progress

## Status

Implementation is ready for the required pilot. The previous baseline and
focused result directories are untouched. New milestone output will be under
`results_m1/`.

## Decisions made

- Plain-optical target hop: 20 m. The earlier clear-water plain-optical cliff
  lies between 20 and 26.667 m, so 20 m gives a documented margin while
  keeping the distance-scaled chains finite.
- Common fixed TDMA guard: 1 ms. It is small relative to the acoustic
  propagation times in this distance range and is identical for both
  technologies.
- One packet per slot for both technologies. The slot is derived as full
  payload plus queried CBR/UDP/IP header bytes divided by PHY rate, plus the
  worst-case one-hop propagation delay and the 1 ms guard.
- Low-load period: 5.0 s Poisson mean (0.2 packet/s). This is below the
  derived acoustic service rate even for the 1500 m case, so goodput should
  track offered load while delay remains measurable.
- Optical relay count: `ceil(D / 20 m) - 1`; equal optical hops sum exactly to
  D. The requested modem-count column is 2 for acoustic and 2*hops for
  optical; the simulator still uses one node per relay as in v2.

## Verification before pilot

- Timing smoke runs succeeded for one acoustic and one plain-optical case.
  Header bytes were queried as 16 bytes, and both logs printed derived
  airtime, propagation, slot and frame values.
- No C++ or DESERT module source was changed. Existing CBR sequence-wrap and
  optical LUT concerns remain known model limitations; the low-load plain
  optical milestone avoids the wrap and does not use beam mode.

## Pilot result

- Pilot completed with 32 rows (8 distances × 2 technologies × 2 seeds), zero
  failures and zero conservation residuals.
- Every requested distance was feasible. Maximum observed run time was 5.22 s
  for the 20 s, 1500 m optical case; no distance was dropped or reduced.
- Logs print both effective scenario classes and derived timing. The optical
  node count grows from 4 at 50 m to 76 at 1500 m, while the requested modem
  accounting grows from 6 to 150. Acoustic remains two nodes/two modems.
- At 1000 m both scenarios delivered all pilot packets; at 1500 m acoustic
  PDR degraded while plain optical remained lossless with 20 m hops. Pilot
  goodput CIs are broad because a 20 s Poisson run contains few packets; the
  10-seed/100-second main run is required for the paper values.

## Main result

- Main completed with 160 rows (8 distances × 2 technologies × 10 seeds),
  zero failures, zero conservation residuals and maximum observed runtime
  6.75 s. All requested distances were feasible; none was reduced or dropped.
- `checks/milestone1.sh` prints:
  `PASS: milestone 1 timing, relay scaling, NaN handling, and conservation`.
- At 100 m, both PDRs are 100%; mean delay is 150 ms acoustic versus 14.9 ms
  optical, and energy is 1156 versus 57.5 uJ/bit. At 1000 m, both remain at
  100% PDR; mean delay is 1.11 s acoustic versus 160 ms optical, and energy is
  1156 versus 575 uJ/bit.
- At 1500 m the acoustic PDR is 27.0+/-6.0% and goodput 50+/-9.5 bit/s,
  while optical remains at 100% and about 194 bit/s. This is not a free
  optical win: the optical scenario uses 150 requested modems and 862.5
  uJ/bit, while the acoustic scenario uses two modems and suffers the
  configured acoustic PER/SNR losses.
- Plots are in `results_m1/`: delay, goodput, energy/bit and hardware count
  versus distance, with 95% CIs (zero-width CI for deterministic hardware
  count). Undefined values are skipped and are never encoded as numeric zero.

## Open blockers

None for milestone 1. Known upstream/model issues remain documented in
`FINDINGS.md` (CBR sequence wrap, beam-LUT calibration, analytical energy),
but this milestone uses low load and plain optical only, so no C++ change was
required.

## Next step

Milestone 2 should add an acoustic multihop control and/or a calibrated
optical energy/misalignment model before making broader deployment claims.
Do not start milestone 2 as part of this work.
