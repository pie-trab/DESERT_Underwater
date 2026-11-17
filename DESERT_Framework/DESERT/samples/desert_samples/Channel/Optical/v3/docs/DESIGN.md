# v3 dual-modem optical node: design and rationale

This note documents the node model, why v2 did not use it, and what the v3
results do and do not claim.  It is deliberately about the simulation, not a
paper draft.

## 1. The physical problem with the v2 node

v2 models every relay as one optical modem with one head.  The head receives
from the previous modem and transmits to the next one.  That keeps the
DESERT chain short (one node per relay) and makes every simulated hop a real
water link, but a narrow-beam optical aperture cannot simultaneously point
backwards to the predecessor and forwards to the successor.  A real relay is
a box with two heads, one per direction.

The first-generation script did use two heads:

```text
original/multi_hop_optical_tdma.tcl
  sender -> relay_0_rx -> relay_0_tx -> relay_1_rx -> relay_1_tx -> ... -> sink
```

but it implemented each relay as **two DESERT nodes** joined by a simulated
1 m optical water hop.  v2's `optical_chain.tcl` header lists the reasons it
was replaced:

- the simulated chain contains two nodes per physical relay;
- each relay has two TDMA slots, so its service share is halved and the frame
  is longer; throughput becomes limited by frame/slot count rather than by
  the water link;
- the intra-relay connection is a water propagation object that needs an
  artificial attenuation for what is really an electrical backplane;
- every other edge in the per-hop metrics is the fake gap, not a physical
  optical link.

Those are artifacts of the **two-node implementation**, not necessary
properties of dual-head hardware.  v3 removes the artifacts.

## 2. v3 node architecture

One relay box is one DESERT `M_Node`.  It owns one IP address and one static
routing table, plus two complete modem stacks:

```text
                    +---------------------------+
                    |  UW/STATICROUTING         |
                    |  UW/IP                    |
                    |  UW/MULTI_DESTINATION     |
                    +------------+--------------+
                                 |
                 +---------------+---------------+
                 |                               |
            UW/MLL (up)                     UW/MLL (down)
            UW/TDMA  head 0                 UW/TDMA  head 1
            UW/OPTICAL/PHY                  UW/OPTICAL/PHY
            face = upstream                 face = downstream
            receive only                    transmit only
```

`Module/UW/MULTI_DESTINATION` is the DESERT add-on used by the ROV
multi-interface samples.  In manual mode it sends every packet coming down
from IP to the downstream MLL and passes every packet coming up from either
MLL to IP.  The relay therefore performs ordinary store-and-forward IP
forwarding between its two heads.  No packet is transmitted over the water
between the two heads, and no synthetic attenuation is needed.

The source and sink are single-head endpoints (`CBR -> UDP ->
StaticRouting -> IP -> MLL -> one MAC/PHY`).  Their single head is the
physically required one: the source needs a downstream transmitter, the sink
an upstream receiver.

Physical layout: the two heads of a relay are colocated at the relay
position.  The water hop is exactly `hop_length`, the chain length is
`(n_relays + 1) * hop_length`, and the intra-relay distance is zero (the
hand-over is internal, not a propagation path).

## 3. TDMA schedule

Only transmitting heads need slots.  The source and the `n` downstream relay
heads own slots `0..n`; the sink and the `n` upstream heads get a dummy slot
0 because they never transmit.  `tot_slots = n + 2`, the same frame length as
v2's `n + 2` modems:

```text
slot 0      slot 1          slot 2          ...  slot n        slot n+1
source  ->  relay 1 down -> relay 2 down -> ...  relay n down   sink
            (relay 1 up RX) (relay 2 up RX)      (relay n up RX)
```

When relay `i`'s upstream head receives in slot `i-1`, the packet is handed
up to IP and back down to the downstream MAC queue before slot `i` starts.
The 1 ms guard covers the internal module calls (microseconds).  The
downstream head transmits in slot `i`.  The pipeline is one water hop per
slot, exactly like v2.

The two heads of a relay are never active at the same time in this schedule.
That respects the PHY half-duplex constraint (`startRx` drops a packet while
`txPending` is true) without any extra guard.  It also avoids the
distance-zero self-interference that would appear if the two colocated heads
were active together, because the plain optical propagation model has no
head-direction isolation.

## 4. What is deliberately not modelled

- **Full-duplex relaying.**  A real dual-head node could receive and transmit
  concurrently.  Exploiting that would need a directional antenna/head
  pattern or an explicit isolation model, because the plain optical model
  attenuates only by distance.  v3 uses the conservative time-separated
  schedule and does not claim a full-duplex gain.  A possible v4 is a
  per-hop-channel or beam-pattern variant that lets adjacent hops overlap and
  measures the pipeline gain; that is a different channel assumption, not a
  parameter change.
- **Head baseline.**  The two heads are colocated.  A 0.5 m baseline would
  add a negligible propagation delay and would not change the result; it
  would only complicate the geometry.  The internal hand-over is modelled as
  instantaneous IP forwarding.
- **Electrical backplane energy.**  The relay's internal forwarding does not
  consume optical airtime.  The energy table separates active optical TX/RX
  energy from a powered-idle term for the modem count; it does not model a
  separate backplane power.
- **Endpoint dual heads.**  The endpoints keep one head.  The study is
  unidirectional; a bidirectional deployment would add a second head at each
  endpoint.

## 5. Energy accounting

Active optical energy uses the same event-count method and the same 10 W TX /
1.5 W RX assumptions as v2:

```text
active = (water_tx * 10 W + water_rx * 1.5 W) * airtime / delivered bits
```

For the dual-head chain, `water_tx` counts the source and the `n` downstream
relay heads, and `water_rx` counts the `n` upstream relay heads and the sink.
These are the same event counts as v2, so the active energy is identical.

The second head adds a powered-idle cost.  `energy_sensitivity.csv` reports
idle power of 0, 0.5, 1.5 and 3 W per modem and TX/RX power scales of 0.5,
1.0 and 1.5.  The baseline in `main_results.csv` uses 1.5 W per modem for the
whole 100 s mission.  At 1.5 km the analytical idle term is 0.587 J/bit for
76 modems and 1.159 J/bit for 150 modems (exactly the modem ratio);
`main_results.csv` reports the per-run mean (1.209 J/bit) because it averages
per-run ratios.  This term is a sensitivity, not a calibrated modem power
model: with the sparse 5 s traffic and a 100 s mission it dominates the active
term, and it would shrink for a busier or longer deployment.

## 6. Results

At `c = 0.3 1/m`, 20 m hop, 10 seeds, 100 s:

| Distance | v2 modems | v3 modems | v2/v3 PDR | v2/v3 delay | active energy |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 100 m | 6 | 10 | 100% | 0.0149 s | 64.9 uJ/bit |
| 1,000 m | 51 | 100 | 100% | 0.1602 s | 648.6 uJ/bit |
| 1,500 m | 76 | 150 | 100% | 0.2393 s | 972.9 uJ/bit |

The equality is exact for every seed, not just on the means: PDR, delay,
delivered packets, sent packets, active energy and frame duration match
bit-for-bit.  The load sweep is also identical up to the saturation point
(94.6% at 1 km and 65.1% at 1.5 km for a 0.1 s period), and the 1,000 m
turbidity check is identical at `c = 0.1`, `0.3` and `0.5 1/m`.

The dual-head model therefore says: the v2 single-head abstraction is
performance-equivalent to a correctly scheduled dual-head relay, but it
under-counts the hardware by a factor of two (and the powered-idle energy by
the same factor).  That is the trade-off v2 chose to avoid, and v3 makes it
explicit.

## 7. Validation

`simulation/check.sh` verifies:

- all runs succeeded and packet conservation residual is zero;
- v2 and v3 PDR, delay, active energy, sent/delivered packets and frame
  duration match per seed at every distance;
- v3 modem count is `2 * relay_boxes + 2` and water hops are
  `relay_boxes + 1`;
- the load and turbidity sweeps match between topologies;
- the active energy is identical and the idle-energy ratio equals the modem
  ratio.

## 8. Limitations

- Deterministic optical threshold channel; no fading, turbulence or
  independent misalignment (inherited from v2).
- Plain optical PHY only; the beam-LUT mode is excluded for the reasons in
  v2 (`docs/EXPERIMENT.md`).
- Horizontal chain at a shared depth.
- One-way CBR traffic with Poisson arrivals.
- Simulation study of configured models, not a field trial.
