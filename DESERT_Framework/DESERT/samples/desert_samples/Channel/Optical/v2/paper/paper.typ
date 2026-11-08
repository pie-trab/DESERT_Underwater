#set page(width: 16cm, height: auto, margin: 1.8cm)
#set text(size: 10pt)
#set par(justify: true)

#align(center)[
  #text(17pt, weight: "bold")[
    Acoustic versus Scaled-Hop Optical Communication in Underwater Networks:
    A Simulation Study
  ]
]
#v(0.5em)
#align(center)[
  Draft manuscript --- author names and affiliation to be completed.
]
#v(1em)

#include "abstract.typ"

#v(0.8em)

= 1. Introduction

Underwater wireless communication is constrained by a fundamental trade-off.
Acoustic links can carry information over hundreds to thousands of metres,
but their data rate is low, their propagation delay is large, and their
usable bandwidth is limited. Optical links offer much higher rates and can
substantially reduce transmission delay and energy per delivered bit, but
their range is short and strongly dependent on water clarity, turbidity,
alignment, and receiver geometry. A realistic deployment question is
therefore not simply whether optics is "better" than acoustics, but under
which range, water type, traffic load, and relay budget the optical benefit
is worth its hardware cost.

Multi-hop relaying can extend optical range, but it also changes the network
topology and the medium-access schedule. If the optical chain is given many
relays while the acoustic baseline remains a single direct link, an apparent
optical advantage may reflect the number of relays rather than the physical
layer. This is particularly important under time-division multiple access
(TDMA), where the number of nodes determines the frame length and the
service share of every modem. A like-for-like comparison must therefore
derive the same slot rule for both technologies, use the same traffic and
payload, and make the relay scaling explicit.

This paper reports a simulation-based deployment comparison between a direct
acoustic link and a single-head optical relay chain whose hop count scales
with source--destination distance. The study uses the DESERT framework and
plain optical propagation; the optical hop length is selected from a
measured clear-water reach calibration, not hand-tuned after the results.
The main contributions are:

- a common derived-TDMA rule for both technologies;
- distance-scaled optical relaying with an explicit unique-modem count;
- a turbidity calibration and regime map over distance and attenuation;
- an analytical energy sensitivity analysis with a +/-50% power envelope;
- a diagnostic equal-hop acoustic control, reported separately because its
  PDR is affected by a first-hop simulation artifact.

The headline results are limited to direct acoustic and optical scaled-hop
communication. The acoustic equal-hop chain is not used as a physical PDR
curve.

The study is deliberately narrow. It does not propose a new modulation,
coding scheme, or routing protocol. It holds the traffic model, payload,
TDMA derivation, and energy assumptions fixed across technologies so that
the remaining differences are attributable to the configured acoustic and
optical models and to the relay count required by each technology. The
result is a deployment study for a short-range, low-power optical chain and
a long-range acoustic fallback, not a claim that one physical layer replaces
the other in every environment.

= 2. Simulation model and method

== 2.1 Scenarios

Three scenarios were implemented. The direct acoustic baseline consists of
two modems separated by the source--destination distance. The optical
scaled-hop scenario is a horizontal chain of `n_hops + 1` single-head
modems: the source, `n_hops - 1` relays, and the sink. Each relay forwards
received packets through the standard DESERT stack; there is no second
optical head and no synthetic intra-relay water gap.

The acoustic equal-hop scenario uses the same chain topology and the same
number of hops as the clear-water optical scenario. It is an ablation that
isolates the cost of relaying from the optical physical layer. It is not an
acoustic deployment recommendation.

== 2.2 TDMA and packet timing

Both technologies use one packet per slot and a common 1 ms guard interval.
The slot duration is derived as

$ tau_"slot" = (8 (L_"payload" + H_"CBR" + H_"UDP" + H_"IP")) / R
  + d_"hop" / v_"prop" + t_"guard", $

where `L_payload` is the application payload in bytes, `H_*` are the
protocol-header sizes queried from the loaded DESERT modules, `R` is the PHY
bit rate, `d_hop` is the hop length, `v_prop` is the propagation speed, and
`t_guard` is the common guard. The frame is `N_slots` times the slot
duration, with one TDMA slot per simulator node. The optical propagation
speed is 225,000 km/s; the acoustic propagation speed is 1,500 m/s. Full
packet airtime, rather than payload-only airtime, is used consistently in the
energy calculation.

This rule makes the schedules comparable in their timing assumptions while
preserving the different physics and node counts. The optical chain has many
short slots; the direct acoustic link has one long slot. Their frame lengths
need not be equal, because the topologies are not equal.

Forwarding is deliberately conventional. Every simulator node contains the
standard DESERT stack: CBR application, UDP, static routing, IP, MLL, TDMA,
and the technology-specific PHY. Only the source application is started.
The destination address is the final sink, and each node installs a static
next-hop route to the following modem in the chain. MLL tables are populated
for all address pairs; the chain route selects the next hop. A relay receives
a packet in its receive path, passes it up through IP, and sends it back down
to the MAC for the next slot. There is no application-level store-and-forward
and no second radio head. This makes the number of simulator nodes equal to
the number of physical modems, which is the basis of the unique-modem count.

== 2.3 Water model and hop calibration

Plain optical propagation uses the analytic fixed-attenuation model with the
baseline clear-water coefficient `c = 0.3 1/m`. For each water type, a
single-hop pilot sweep measured the largest hop with PDR at least 0.95. The
working hop was fixed to 80% of that measured value. The resulting working
hops are 40 m at `c = 0.1`, 20 m at 0.3, 12 m at 0.5, 8 m at 0.8, and 4 m at
1.2 1/m. For the headline `c = 0.3` case, 20 m is exactly 80% of the measured
25 m limit.

For a requested distance `D`, the number of optical hops is
`ceil(D / hop(c))`, with one relay per hop beyond the endpoints. Cases that
would exceed 100 hops, or that would require a hop below 2 m, are marked
INFEASIBLE rather than assigned a zero-performance value. The hardware count
reported in the paper is the number of unique modems, `hops + 1`, not the
legacy link-endpoint count `2 * hops`.

== 2.4 Traffic and repetitions

Each main run uses a 125-byte application payload, Poisson arrivals with a
mean period of 5 s, a 100 s traffic window, and 10 RNG substreams. The low
load keeps both systems below their TDMA service ceilings, so goodput tracks
the offered load and the delay comparison is not dominated by queue
saturation. Every run is drained after the traffic window by a margin that
scales with the frame length and the number of hops.

== 2.5 Metrics and energy accounting

PDR is the number of packets delivered to the destination modem divided by
the number generated at the source. Goodput is delivered payload bits over
the traffic window. Delay is the sink application forward-trip time. Delay
and energy per bit are left undefined when no packet is delivered.

The energy result is an analytical model, not a simulated modem energy
measurement. TX and RX event counts are taken from the MAC counters; each
event is multiplied by the configured payload airtime and by an assumed
power. The baseline assumptions are 20 W TX and 4 W RX for acoustics, and
10 W TX and 1.5 W RX for optics. A +/-50% band on all four powers is reported
as an uncertainty envelope. A separate sensitivity case increases the
acoustic TX power with distance using spherical spreading and Thorp
absorption at 50 kHz; that case is labelled as a sensitivity analysis, not
as a calibrated modem model.

Every reported mean is accompanied by a 95% Student-t confidence interval
over the ten RNG substreams. At low load the PDR is often identical across
substreams, so the interval collapses to zero; this is a real outcome of a
deterministic threshold channel, not a missing-seed artifact. Packet
conservation is checked per run as generated packets = delivered + queue
drops + residual queue + PHY loss. A run with a nonzero residual or a missing
metric block is excluded rather than silently included in the mean.

= 3. Results

== 3.1 Distance scaling

#figure(
  image("figures/fig_main_distance.png", width: 100%),
  caption: [
    Headline distance results for direct acoustic communication and the
    scaled-hop optical chain at `c = 0.3 1/m`. PDR below 0.95 is shown with
    an open marker. Error bars are 95% confidence intervals over ten RNG
    substreams.
  ],
) <fig-main>

At 100 m, both systems deliver all packets. Optical reduces mean delay from
0.150 s to 0.0149 s and analytical energy from 1,303.5 to 64.9 uJ/bit. At
1,000 m, both remain lossless; optical delay is 0.160 s versus 1.110 s, and
energy is 648.6 versus 1,303.5 uJ/bit. The direct acoustic link's energy per
delivered bit remains nearly constant in the lossless region because one TX
and one RX occur per delivered packet. Optical energy grows with the number
of hops because every relay adds a TX and an RX event.

At 1,500 m, the direct acoustic link degrades to 27.0 +/- 4.3% PDR with a
mean delay of 2.036 s. The optical chain remains lossless with a mean delay
of 0.239 s, but requires 76 unique modems. This is the central trade-off:
optical avoids the acoustic long-range failure only when enough relays are
deployed, and the relay count is itself the deployment cost.

The shorter-distance points show the same pattern before any packet loss
appears. From 50 to 500 m, direct acoustic delay rises from 0.106 s to
0.548 s while optical delay rises from 0.0084 s to 0.0782 s. Over the same
range, the direct acoustic energy per delivered bit stays near 1,303.5
uJ/bit, whereas optical energy rises from 38.9 to 324.3 uJ/bit as the chain
grows from 3 to 25 hops. Both systems deliver every packet in this interval;
the difference is therefore a delay and hardware-cost difference, not a
difference in loss. The optical chain already uses four unique modems at
50 m and 26 at 500 m, while the acoustic baseline uses two throughout.

#figure(
  table(
    columns: (auto, auto, auto),
    inset: 5pt,
    align: (center, center, center),
    table.header([Distance], [Direct acoustic], [Optical scaled-hop]),
    [100 m],
    [100%, 0.150 s, 1,303.5 uJ/bit, 2 modems],
    [100%, 0.0149 s, 64.9 uJ/bit, 6 modems],
    [1,000 m],
    [100%, 1.110 s, 1,303.5 uJ/bit, 2 modems],
    [100%, 0.160 s, 648.6 uJ/bit, 51 modems],
    [1,500 m],
    [27.0 +/- 4.3%, 2.036 s, 2 modems],
    [100%, 0.239 s, 76 modems],
  ),
  caption: [
    Selected headline results. Modem counts are unique devices, `hops + 1`.
  ],
) <tab-main>

== 3.2 Relay hardware scaling

The optical chain's relay count grows approximately linearly with distance
because the hop length is fixed by the water type. At `c = 0.3`, the chain
uses 4 unique modems at 50 m, 6 at 100 m, 11 at 200 m, 26 at 500 m, 51 at
1,000 m, and 76 at 1,500 m. The direct acoustic baseline always uses two.
This is not a minor accounting difference: the earlier `2 * hops` convention
counted every link endpoint and double-counted intermediate relays, making a
1,000 m chain appear to need 100 modems instead of 51.

#figure(
  image("figures/fig_hop_hardware.png", width: 100%),
  caption: [
    Calibrated optical hop length and unique modem count at 1,000 m. The
    high-turbidity points above the 100-hop limit are marked INFEASIBLE.
  ],
) <fig-hop>

== 3.3 Turbidity

#figure(
  image("figures/fig_regime_maps.png", width: 100%),
  caption: [
    Delay and energy ratios over distance and attenuation. Values above one
    favor optical. INFEASIBLE cells are not assigned a zero-performance
    value.
  ],
) <fig-regime>

The measured clear-water reach falls quickly with attenuation: 25 m at
`c = 0.3`, 15 m at 0.5, 10 m at 0.8, and 5 m at 1.2 1/m. The scaled chain
therefore needs many more relays in turbid water. Three cells are
infeasible: `c = 0.8` at 1,000 m (125 hops), and `c = 1.2` at 500 m and
1,000 m (125 and 250 hops). In every feasible cell of the baseline regime
map, optical has lower delay and lower analytical energy per delivered bit
than direct acoustic. This is a conditional result: it assumes the chain is
deployed and that every hop remains within the calibrated range.

== 3.4 Energy sensitivity

#figure(
  image("figures/fig_energy_sensitivity.png", width: 100%),
  caption: [
    Analytical energy per delivered bit. Shaded regions are the +/-50%
    power envelope. The black dashed curve is the distance-scaled acoustic
    TX sensitivity case, not the baseline.
  ],
) <fig-energy>

Under the baseline power assumptions there is no acoustic/optical energy
crossover between 50 and 1,500 m; optical is lower at every point where both
are defined. The conservative envelope (acoustic high power, optical low
power) also has no crossover. The optimistic acoustic/pessimistic optical
envelope crosses at approximately 663 m. The distance-scaled acoustic TX
case has no crossover and grows very large, because maintaining a fixed
received SNR at kilometre range would require an implausible electrical
power. These results show that absolute energy claims depend strongly on
the assumed power model; the qualitative optical advantage is robust only
within the tested assumptions.

== 3.5 Acoustic equal-hop diagnostic

#figure(
  image("figures/fig_chain_diagnostic.png", width: 100%),
  caption: [
    Diagnostic only: acoustic equal-hop chain compared with direct acoustic
    and optical context. PDR below 0.95 is shown with an open marker. The
    acoustic-chain PDR is not a physical range curve.
  ],
) <fig-diagnostic>

The acoustic equal-hop chain is lossless at 50--200 m and 1,500 m, but shows
0.682 PDR at 500 m and 0.586 at 1,000 m. Source `mac_tx` equals the number of
generated packets, all losses are visible at the first edge, every downstream
edge has PDR 1.0, and queue drops are zero. The first hop is an ideal 20 m
acoustic link, so this is not acoustic range loss. The exact simulator
mechanism remains unresolved. The result is therefore excluded from the
headline PDR/delay/energy claims and appears only in this diagnostic section.

= 4. Discussion and limitations

The results support a deployment-oriented conclusion. When the optical hop
budget is satisfied, scaled-hop optics gives much lower delay and analytical
energy per delivered bit than a direct acoustic link. The benefit is paid in
relay hardware, and the required relay count grows with both distance and
turbidity. A practical design should therefore treat the optical hop length
as a water-type-dependent parameter and should plan for a hardware count,
not just a link budget.

The following limitations apply.

- Energy is analytical. The powers are assumptions, not calibrated hardware
  measurements, and the absolute uJ/bit values should not be quoted without
  recalibration.
- The optical channel is deterministic threshold behavior. It does not model
  time-varying fading, turbulence, pointing error, or independent node
  misalignment.
- The beam-LUT optical mode is excluded; the paper uses plain optical
  propagation only.
- The optical chain is horizontal and assumes a shared depth. Vertical or
  irregular geometries require a different head-orientation model.
- The acoustic equal-hop PDR is a diagnostic exception. Its first-hop loss
  mechanism is unresolved and must not be presented as a physical result.
- The CBR sequence-number wrap is avoided by the low offered load; higher
  loads require the MAC-level delivery accounting described in the
  experiment notes.
- The comparison is a simulation study of specific configured models, not a
  field trial.

= 5. Conclusion

This paper quantified the delay, energy, and hardware trade-off between a
direct acoustic link and a distance-scaled optical relay chain in DESERT.
With a calibrated 20 m hop at `c = 0.3 1/m`, optics reduced delay by roughly
an order of magnitude and energy per delivered bit by a factor of about 20
at 100 m, while remaining lossless at 1,000 m with 51 unique modems. Direct
acoustics remained the lowest-hardware option through 1,000 m but degraded
near 1,500 m. Turbidity increased the relay requirement and made some
long-distance cells infeasible. The main engineering conclusion is that
optical multi-hop communication is attractive only when the deployment can
afford the relay density implied by the water type; the acoustic link remains
the robust low-hardware fallback.

= References

- [DESERT] DESERT framework citation: TODO verify complete bibliographic
  details before submission.
- [ACOUSTIC] Underwater acoustic communication reference: TODO select a
  verified source.
- [OPTICAL] Underwater optical communication reference: TODO select a
  verified source.
- [TDMA] TDMA scheduling reference: TODO select a verified source.

Citations are intentionally left as a scaffold. No bibliographic details
were invented.

= Reproducibility

The frozen data, parameter tables, and figures are under
`simulation/data/final/` and `paper/figures/`. The exact command sequence
and checks are listed in `paper/reproduce.typ`. This manuscript was generated
from the consolidated derived tables; no new simulations were required for
the writing pass.
