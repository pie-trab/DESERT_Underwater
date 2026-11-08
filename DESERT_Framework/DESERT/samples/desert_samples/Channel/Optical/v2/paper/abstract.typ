#block(width: 100%)[
  #text(13pt, weight: "bold")[Abstract]
  #v(0.4em)
  Underwater wireless networks must trade the long reach of acoustics against
  the high rate of optical links, whose usable range depends on water clarity
  and relay placement. This paper presents a simulation-based deployment
  comparison between a direct acoustic link and a single-head,
  distance-scaled optical relay chain in DESERT. Both technologies use the
  same traffic, payload, TDMA derivation, and ten RNG substreams; the optical
  hop length is calibrated conservatively from the measured clear-water
  reach. At 100 m, both links deliver all packets, but optical reduces mean
  delay from 0.150 s to 0.0149 s and analytical energy from 1,303.5 to
  64.9 uJ/bit. At 1,000 m, both remain lossless; optical delay is 0.160 s
  versus 1.110 s, and energy is 648.6 versus 1,303.5 uJ/bit, at the cost of
  51 versus 2 unique modems. Direct acoustic degrades near 1,500 m
  (27.0 +/- 4.3% PDR), whereas the optical chain remains lossless with
  76 modems. Turbidity calibration shows that high-attenuation long-distance
  cases become infeasible under the relay limit. The results quantify the
  optical delay/energy benefit and its hardware cost. Energy is analytical
  and the optical channel is deterministic; an acoustic equal-hop diagnostic
  is excluded because of an unresolved first-hop simulation artifact.
]
