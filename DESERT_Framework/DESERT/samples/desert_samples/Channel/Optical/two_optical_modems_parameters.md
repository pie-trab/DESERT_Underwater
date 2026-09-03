# `two_optical_modems.tcl` parameter reference

This document describes the parameters exposed by
[`two_optical_modems.tcl`](two_optical_modems.tcl). Line references point to
the current working-tree sources.

## Model currently selected

The sample creates two nodes, each with a CBR → UDP → static-routing → IP →
MLL → CSMA-ALOHA → optical PHY stack. The PHY class is
`Module/UW/UWOPTICALBEAMPATTERN`, which inherits the optical PHY parameters.

The sample uses:

- fixed Lambert–Beer attenuation (`setFixedC`), controlled by `c_`;
- a beam-pattern LUT;
- a maximum-range LUT;
- an ambient-light/noise LUT;
- directional beams by default.

Therefore, `noise_lut_path`, `beam_lut_path`, and `max_range_lut_path` are
active in the sample. The propagation attenuation LUT is not active unless the
script is changed to use `setVariableC` and `setLUT`.

## Quick configuration: `opt(...)` variables

These are the intended user-facing settings in the sample, defined at
[`two_optical_modems.tcl:22-70`](two_optical_modems.tcl#L22-L70).

### Topology and run time

| Parameter | Default | Units / values | Effect |
|---|---:|---|---|
| `opt(nn)` | `2` | nodes | Number of nodes created. The traffic and geometry logic is written for a two-node link; changing it requires reviewing routing and flow setup. |
| `opt(starttime)` | `1.0` | s | Start time of each active CBR flow. |
| `opt(stoptime)` | `20.0` | s | Stop time of each active CBR flow. |
| `opt(range)` | `20.0` | m | Horizontal separation. Node `id` is placed at `X = id * range`. |
| `opt(depth)` | `-10.0` | m | Common Z coordinate. Underwater depth is represented by a negative Z value. |

Geometry is applied at
[`two_optical_modems.tcl:248-257`](two_optical_modems.tcl#L248-L257).

### Traffic and randomisation

| Parameter | Default | Units / values | Effect |
|---|---:|---|---|
| `opt(cbr_period)` | `0.1` | s | Time between CBR packet transmissions. |
| `opt(pktsize)` | `125` | bytes | CBR payload size. |
| `opt(rngstream)` | `1` | non-negative integer | Advances the global RNG by this many substreams. |
| `opt(poisson_traffic)` | `0` | `0` / `1` | `0` selects periodic CBR; `1` selects Poisson packet timing with the same mean period. |

The corresponding CBR bindings are implemented in
[`uwcbr-module.cpp:125-134`](../../../../application/uwcbr/uwcbr-module.cpp#L125-L134)
and applied by the sample at
[`two_optical_modems.tcl:139-142`](two_optical_modems.tcl#L139-L142).

### Optical PHY

| Parameter | Default | Units / values | Effect |
|---|---:|---|---|
| `opt(freq)` | `10000000` | Hz | Centre frequency of the rectangular spectral mask. |
| `opt(bw)` | `100000` | Hz | Signal bandwidth of the spectral mask; it also contributes to receiver noise power. |
| `opt(bitrate)` | `1000000` | bit/s | PHY bit rate inherited from the BPSK PHY. |
| `opt(txpower)` | `50.0` | PHY power units | Optical transmit power supplied to the PHY. Confirm the unit convention used by the installed `MPhy_Bpsk` implementation when mapping vendor data. |
| `opt(acq_threshold_db)` | `10.0` | dB | Minimum SNR used to acquire a packet. |
| `opt(id)` | `1.0e-9` | A | Photodiode dark current. |
| `opt(il)` | `1.0e-6` | A | Background photocurrent. |
| `opt(shunt_resistance)` | `1.49e9` | Ω | Receiver shunt resistance used in thermal-noise calculation. |
| `opt(sensitivity)` | `0.26` | A/W | Photodiode responsivity. |
| `opt(temperature)` | `293.15` | K | Fixed receiver temperature when variable temperature is disabled or unavailable. |
| `opt(rx_area)` | `1.1e-6` | m² | Receiver/photodiode area. Used by both PHY and propagation. |
| `opt(tx_area)` | `1.0e-5` | m² | Transmitter optical area used by propagation. |

The sample applies these settings at
[`two_optical_modems.tcl:144-159`](two_optical_modems.tcl#L144-L159).
The optical PHY bindings are implemented at
[`uwoptical-phy.cpp:60-78`](../../../../physical/uwoptical_phy/uwoptical-phy.cpp#L60-L78).
The PHY computes SNR as `(S * Pr)^2 / Pn` at
[`uwoptical-phy.cpp:148-154`](../../../../physical/uwoptical_phy/uwoptical-phy.cpp#L148-L154).

### Propagation and orientation

| Parameter | Default | Units / values | Effect |
|---|---:|---|---|
| `opt(attenuation_c)` | `0.043` | m⁻¹ | Constant beam attenuation coefficient `c = a + b` used by the fixed Lambert–Beer model. |
| `opt(theta)` | `1.0` | rad | Transmitter beam divergence / half-angle used by propagation. |
| `opt(omnidirectional)` | `0` | `0` / `1` | `0` selects directional propagation; `1` calls `setOmnidirectional`. |
| `opt(inclination_0)` | `3` | rad | Node 0 optical-axis inclination. |
| `opt(inclination_1)` | `π` | rad | Node 1 optical-axis inclination. Together these aim the two modems at one another along X. |

Propagation fields are bound at
[`uwoptical-mpropagation.cpp:71-89`](../../../../propagation/uwoptical_propagation/uwoptical-mpropagation.cpp#L71-L89),
and the mode commands are implemented at
[`uwoptical-mpropagation.cpp:91-140`](../../../../propagation/uwoptical_propagation/uwoptical-mpropagation.cpp#L91-L140).
Inclination is normalised into `[-π, π]` at
[`uwopticalbeampattern.cpp:158-167`](../../../../physical/uwopticalbeampattern/uwopticalbeampattern.cpp#L158-L167).

### LUT files and parsing

| Parameter | Default path | Format / effect |
|---|---|---|
| `opt(beam_lut_path)` | `dbs/bluecomm/beam_pattern/beam5mbps.csv` | Two columns: angle in radians, normalised beam factor. The sample passes the same file to TX and RX. |
| `opt(max_range_lut_path)` | `dbs/bluecomm/max_range/max_range5mbps.csv` | Three columns: attenuation `c`, maximum range without ambient noise, maximum range with ambient noise. |
| `opt(noise_lut_path)` | `dbs/optical_noise/LUT.txt` | Depth-to-light-noise table used by the receiver noise calculation. |
| `opt(sample_dir)` | directory of the Tcl script | Base directory used to build the database paths. Normally leave unchanged. |
| `opt(db_dir)` | normalised `../../dbs` from the sample | Root directory for optical databases. |

The path variables are defined at
[`two_optical_modems.tcl:58-62`](two_optical_modems.tcl#L58-L62) and consumed at
[`two_optical_modems.tcl:236-240`](two_optical_modems.tcl#L236-L240).
The beam-pattern commands and file readers are implemented at
[`uwopticalbeampattern.cpp:79-155`](../../../../physical/uwopticalbeampattern/uwopticalbeampattern.cpp#L79-L155)
and
[`uwopticalbeampattern.cpp:429-480`](../../../../physical/uwopticalbeampattern/uwopticalbeampattern.cpp#L429-L480).
The optical PHY noise LUT is parsed and interpolated by
[`uwoptical-phy.cpp:220-260`](../../../../physical/uwoptical_phy/uwoptical-phy.cpp#L220-L260),
and its contribution is included at
[`uwoptical-phy.cpp:166-184`](../../../../physical/uwoptical_phy/uwoptical-phy.cpp#L166-L184).

To model LumaX-UV, replace the three active files—or disable the relevant LUT
path/command—and ensure the replacement column conventions match the readers.
The maximum-range table is especially important: the beam-pattern PHY rejects
a packet when distance is greater than the LUT-derived range, before the base
PHY acquisition check
([`uwopticalbeampattern.cpp:170-198`](../../../../physical/uwopticalbeampattern/uwopticalbeampattern.cpp#L170-L198)).

### Diagnostics and output

| Parameter | Default | Units / values | Effect |
|---|---:|---|---|
| `opt(maxinterval)` | `10.0` | s | Interference-history interval for each `MInterference/MIV` instance. |
| `opt(verbose)` | `1` | `0` / `1` | Prints the end-of-run summary. |
| `opt(debug)` | `0` | `0` / `1` | Enables debug output in CBR, PHY, propagation, and interference objects. |
| `opt(trace_files)` | `0` | `0` / `1` | `0` sends traces to `/dev/null`; `1` writes `.tr` and `.cltr` files. |
| `opt(trace_prefix)` | `two_optical_modems` | filename stem | Prefix for trace files when tracing is enabled. |
| `opt(ack_mode)` | `setNoAckMode` | MAC command | MAC initialisation command. Change to the appropriate ACK command if acknowledgements are part of the experiment. |

These settings are applied at
[`two_optical_modems.tcl:125-131`](two_optical_modems.tcl#L125-L131),
[`two_optical_modems.tcl:229-241`](two_optical_modems.tcl#L229-L241), and
[`two_optical_modems.tcl:259-262`](two_optical_modems.tcl#L259-L262).

## Additional directly configurable module fields

The sample hard-codes a few module-level settings rather than exposing them
as `opt(...)` variables:

| Module / field | Current value | Location | Purpose |
|---|---:|---|---|
| `Module/UW/CSMA_ALOHA listen_time_` | `1e-12` s | [`two_optical_modems.tcl:183`](two_optical_modems.tcl#L183); bound in [`uw-csma-aloha.cpp:189`](../../../../data_link/uw-csma-aloha/uw-csma-aloha.cpp#L189) | MAC listen interval. Increase for MAC-timing experiments. |
| `Module/UW/CSMA_ALOHA wait_costant_` | `1e-12` s | [`two_optical_modems.tcl:184`](two_optical_modems.tcl#L184); bound in [`uw-csma-aloha.cpp:181`](../../../../data_link/uw-csma-aloha/uw-csma-aloha.cpp#L181) | MAC waiting cost used by this sample. |
| `Module/UW/UWOPTICALBEAMPATTERN noise_threshold` | `0.001` | [`uwopticalbeampattern-default.tcl:35`](../../../../physical/uwopticalbeampattern/uwopticalbeampattern-default.tcl#L35) | Selects the with-noise maximum-range LUT branch when background noise exceeds this value. |
| `Module/UW/Optical/Channel RefractiveIndex_` | `1.33` | [`uwoptical-channel-default.tcl:33`](../../../../channel/uwoptical_channel/uwoptical-channel-default.tcl#L33) | Water refractive index inherited by the electromagnetic channel. |

The beam-pattern class binds `noise_threshold` and
`inclination_angle_` at
[`uwopticalbeampattern.cpp:60-76`](../../../../physical/uwopticalbeampattern/uwopticalbeampattern.cpp#L60-L76).

## Command-line overrides

If any command-line arguments are supplied, exactly five are required. They
override the values in the parameter section at
[`two_optical_modems.tcl:77-87`](two_optical_modems.tcl#L77-L87):

```text
ns two_optical_modems.tcl rngstream cbr_period packet_size range depth
```

The command-line values override `opt(rngstream)`, `opt(cbr_period)`,
`opt(pktsize)`, `opt(range)`, and `opt(depth)`, in that order. All other
parameters remain controlled by the Tcl file.

## Traffic behaviour to keep in mind

CBR objects are created for every source/destination pair, but only flows with
`src != dst` are started
([`two_optical_modems.tcl:289-297`](two_optical_modems.tcl#L289-L297)).
The two active directions are deliberately offset by half a CBR period, so
changing `cbr_period` also changes that offset.
