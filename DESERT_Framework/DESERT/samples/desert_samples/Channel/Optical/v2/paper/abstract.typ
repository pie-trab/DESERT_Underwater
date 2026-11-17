#block(width: 100%)[
  #text(13pt, weight: "bold")[Abstract]
  #v(0.4em)
  Underwater wireless networks must trade the long reach of acoustics against
  the high rate and low latency of optical links. This paper compares a
  hardware-matched direct acoustic link (26 kHz, 16 kHz bandwidth,
  2.5 kbit/s, 175 dB, spreading 1.75) with a single-head, distance-scaled
  optical relay chain in DESERT. Both use the same traffic, payload, TDMA
  derivation, and ten RNG substreams; the optical hop is calibrated from the
  measured baseline reach.

  Both links deliver every packet from 50 to 1,500 m. At 100 m, optical
  reduces mean delay from 0.735 s to 0.0149 s and analytical energy from
  10,828.8 to 64.9 uJ/bit. At 1,000 m, both remain lossless; optical delay is
  0.160 s versus 2.084 s, and energy is 648.6 versus 10,828.8 uJ/bit, at the
  cost of 51 versus 2 unique modems. At 1,500 m, optical delay is 0.239 s
  versus 2.840 s and energy 972.9 versus 10,828.8 uJ/bit, with 76 versus 2
  modems. At 5 kbit/s the optical chain remains lossless while the acoustic
  link falls to 9.8% PDR at 1,000 m and 7.7% at 1,500 m. A 0--20 m/s wind
  sweep leaves the hardware-matched acoustic link lossless; the earlier
  50 kHz failure was a high-absorption parameter case. Turbid-harbor
  `c = 2.19` 1/m cannot meet the 2 m minimum hop and is infeasible. Energy is
  analytical and the optical channel is deterministic; beam-LUT mode is
  excluded because its hardware and geometry do not match the 1 Mbit/s chain.
  An acoustic equal-hop diagnostic is reported separately and excluded from
  headline claims.
]
