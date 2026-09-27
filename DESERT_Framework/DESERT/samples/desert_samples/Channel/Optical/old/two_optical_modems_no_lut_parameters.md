# Two optical modems without LUT files

This guide documents
[`two_optical_modems_no_lut.tcl`](two_optical_modems_no_lut.tcl).

It is the two-node optical example with every external lookup-table dependency
removed. It does not load:

- WOSS;
- an attenuation/depth table;
- an ambient-light/noise table;
- the beam-pattern PHY;
- a beam-pattern table;
- a maximum-range table.

The simulation still models optical packet transmission, distance-dependent
Lambert-Beer attenuation, receiver noise, and the two-node DESERT protocol
stack. The difference is that all environmental and receiver values are fixed
scalars in the Tcl file.

## Run it

Run from the Optical sample directory:

```bash
cd DESERT_Framework/DESERT/samples/desert_samples/Channel/Optical
ns two_optical_modems_no_lut.tcl
```

The default link is 20 m, with both modems at depth 10 m. The optional command
line arguments are:

```text
rngstream cbr_period packet_size range depth
```

For example:

```bash
ns two_optical_modems_no_lut.tcl 0 0.1 125 10 -10
```

The Tcl file contains the complete parameter set, so changing the values at
the top of the file is the normal way to configure a specific experiment.

The default uses:

```tcl
set opt(poisson_traffic) 1
```

This is important because both directions share the same optical channel. If
both sources use periodic traffic with the same period and start time, they
transmit at the same instants. A modem that is transmitting is not available
to receive in this PHY, so synchronized bidirectional CBR can produce zero
received packets even when the link budget is strong. Poisson traffic avoids
that deterministic collision pattern. If deterministic traffic is required,
stagger the two source start times or use separate non-overlapping schedules.

## How LUTs are replaced

### Attenuation LUT → fixed `attenuation_c`

The LUT-based version can load a depth-dependent table containing:

```text
depth,c,temperature
```

The no-LUT version instead sets:

```tcl
set opt(attenuation_c) 0.043
Module/UW/OPTICAL/Propagation set c_ $opt(attenuation_c)
```

and selects:

```tcl
$propagation setFixedC
```

This means every packet uses the same attenuation coefficient at every depth.
The propagation model still applies distance-dependent Lambert-Beer loss, but
there is no depth interpolation.

The approximate optical gain used by DESERT is:

```text
G(d) = [2 Ar / (pi d^2 (1 - cos(theta)) + 2 At)] exp(-c d)
```

where:

- `d` is modem separation in metres;
- `Ar` is receiver area;
- `At` is transmitter area;
- `theta` is the transmitter half-angle;
- `c` is `attenuation_c` in `1/m`.

For clearer water, reduce `attenuation_c`. For more turbid water, increase it.

### Ambient-light/noise LUT → fixed receiver noise parameters

The LUT-based optical PHY can load noise as a function of depth. This version
does not call `setLUTFileName`, `setLUTSeparator`, `useLUT`, or
`setVariableTemperature`.

Instead, the receiver noise is controlled by these fixed parameters:

```tcl
set opt(id)               1.0e-9
set opt(il)               1.0e-6
set opt(shunt_resistance) 1.49e9
set opt(temperature)      293.15
```

They are passed directly to the optical PHY:

```tcl
Module/UW/OPTICAL/PHY set Id_ $opt(id)
Module/UW/OPTICAL/PHY set Il_ $opt(il)
Module/UW/OPTICAL/PHY set R_  $opt(shunt_resistance)
Module/UW/OPTICAL/PHY set T_  $opt(temperature)
```

The receiver noise is approximately calculated as:

```text
Pn = 2 q (Id + Il) B + 4 k T B / R
```

where:

- `q` is the electron charge;
- `k` is the Boltzmann constant;
- `B` is the signal bandwidth;
- `Id` is dark current;
- `Il` is fixed background photocurrent;
- `T` is receiver temperature;
- `R` is receiver shunt resistance.

To represent a brighter environment without a noise LUT, increase `opt(il)`.
To represent a colder or hotter receiver, change `opt(temperature)`. This
creates one constant environment for the entire simulation; it cannot model a
changing light field with depth.

### Beam-pattern LUT → ordinary optical PHY

The beam-pattern version uses:

```tcl
new Module/UW/UWOPTICALBEAMPATTERN
```

and loads both a beam response table and a maximum-range table. The no-LUT
version uses:

```tcl
new Module/UW/OPTICAL/PHY
```

and does not load `libuwopticalbeampattern.so`.

The default no-LUT configuration selects:

```tcl
set opt(omnidirectional) 1
$propagation setOmnidirectional
```

This removes angular beam acceptance and LUT-based maximum-range gating. Every
direction is treated as geometrically available, while distance attenuation
and receiver acquisition threshold are still evaluated.

If `opt(omnidirectional)` is set to `0`, the propagation object uses
`setDirectional` and the `theta` parameter affects the propagation geometry.
However, the ordinary optical PHY still has no per-device azimuth/heading
model. This is not equivalent to a measured directional beam pattern; use the
beam-pattern PHY and LUTs when angular device behavior matters.

### Max-range LUT → no separate range gate

The beam-pattern PHY uses the max-range LUT to reject packets beyond a table-
derived distance. The ordinary optical PHY does not use this gate. A packet is
accepted or rejected based on received power, noise, and the acquisition
threshold:

```tcl
set opt(acq_threshold_db) 10.0
Module/UW/OPTICAL/PHY set AcquisitionThreshold_dB_ $opt(acq_threshold_db)
```

To impose a hard experimental range without a LUT, place the nodes at the
desired distance or add an explicit scenario-level condition. The optical PHY
itself will continue to use its calculated received power.

## Main parameters

| Parameter | Meaning | Typical effect |
|---|---|---|
| `opt(range)` | Node separation | Larger range reduces received power |
| `opt(depth)` | Common negative Z coordinate | Geometry only in fixed-c mode |
| `opt(attenuation_c)` | Constant water attenuation, `1/m` | Larger value means more loss |
| `opt(theta)` | Transmitter half-angle, radians | Changes propagation gain |
| `opt(txpower)` | Optical transmit power | Larger value improves received power |
| `opt(rx_area)` | Receiver area | Larger value improves received power |
| `opt(tx_area)` | Transmitter area | Changes optical gain |
| `opt(il)` | Fixed background photocurrent | Larger value increases shot noise |
| `opt(temperature)` | Fixed receiver temperature | Changes thermal noise |
| `opt(acq_threshold_db)` | Acquisition threshold | Larger value makes reception harder |
| `opt(omnidirectional)` | Enable all-direction propagation | `1` removes directional dependence |

## Trade-offs

This no-LUT version is useful for:

- quick protocol and topology tests;
- reproducible baseline simulations;
- parameter sweeps over distance or constant water conditions;
- systems where measured optical tables are not yet available.

It does not represent:

- depth-varying attenuation;
- depth-varying ambient light;
- measured transmitter or receiver beam shape;
- device-specific angular misalignment;
- a measured maximum communication range.

For those effects, use the beam-pattern scenario and calibrated tables from
the optical LUT guide. A practical progression is to start with this file,
calibrate `attenuation_c` and `il` against a few measurements, and only then
introduce depth, noise, and beam-pattern LUTs.