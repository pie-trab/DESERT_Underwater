# Final claims and exclusions

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
