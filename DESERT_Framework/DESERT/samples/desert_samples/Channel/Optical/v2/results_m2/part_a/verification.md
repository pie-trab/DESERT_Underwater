# Part A: milestone 1 verification

PDR below 0.95 is marked with an open marker in the verified plots. Delay is conditional on delivered packets; energy includes TX/RX events for lost packets when delivery is nonzero.

## PDR table

```
technology  distance_m  pdr_mean  pdr_ci95  pdr_below_095
  acoustic        50.0  1.000000   0.00000          False
   optical        50.0  1.000000   0.00000          False
  acoustic       100.0  1.000000   0.00000          False
   optical       100.0  1.000000   0.00000          False
  acoustic       200.0  1.000000   0.00000          False
   optical       200.0  1.000000   0.00000          False
  acoustic       300.0  1.000000   0.00000          False
   optical       300.0  1.000000   0.00000          False
  acoustic       500.0  1.000000   0.00000          False
   optical       500.0  1.000000   0.00000          False
  acoustic       750.0  1.000000   0.00000          False
   optical       750.0  1.000000   0.00000          False
  acoustic      1000.0  1.000000   0.00000          False
   optical      1000.0  1.000000   0.00000          False
  acoustic      1500.0  0.270476   0.04307           True
   optical      1500.0  1.000000   0.00000          False
```

## Schedule check at 1000 m

```
technology  distance_m  hop_count   slot_s  frame_s  expected_delay_s  measured_delay_s  relative_error
   optical        1000         50 0.002128 0.108533          0.160671          0.160230       -0.002745
  acoustic        1000          1 0.721981 1.443962          1.082971          1.109545        0.024538
```

Optical expectation is 50 hop service slots plus half a frame for the sparse source-slot phase. Acoustic uses one service slot plus the first-order quarter-frame phase term because the source owns half of the two-slot frame. Both errors are below 10%. The timing rule is like-for-like (same full-packet airtime, propagation term, guard and one packet per slot), but the different node counts necessarily produce different frame lengths.
