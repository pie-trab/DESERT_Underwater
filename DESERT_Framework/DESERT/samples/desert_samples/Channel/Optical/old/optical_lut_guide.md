# Generating optical LUTs for DESERT

This guide explains the optical lookup tables used by the DESERT optical
examples and shows how to create starter tables with
[`generate_optical_luts.sh`](generate_optical_luts.sh).

The utility uses only Bash and `awk`. It generates analytical starting points,
but it cannot replace measurements of a real modem or water column. For a
device-specific simulation, use the generated files as templates and replace
the modelled values with measured or validated data.

## LUT types and formats

| Table | Purpose | Format |
| --- | --- | --- |
| Beam pattern | Angular acceptance/beam factor | `angle_rad,normalized_factor` |
| Maximum range | Range limit for each attenuation coefficient | `c,max_range,max_range_with_noise` |
| Attenuation | Water attenuation and temperature versus depth | `depth,c,temperature` |
| Ambient noise | Light-noise value versus depth | Two metadata lines, then `depth,noise` |

The C++ readers expect numeric data without a CSV header. Keep files sorted by
their first column and ensure simulation values are inside their table range.
Some out-of-range lookups use assertions.

## Beam-pattern LUT

The beam-pattern file contains an angle in radians and a normalized response:

```text
-3.1416,0
-1.5708,0.64
0,1.0
1.5708,0.64
3.1416,0
```

For a real device, fix the transmitter/receiver distance, rotate one optical
head, measure received power, and calculate:

```text
normalized_factor = measured_power(angle) / measured_power(boresight)
```

Convert angles to radians and save two comma-separated columns. For a first
analytical approximation:

```bash
./generate_optical_luts.sh beam \
  -o beam_device_a.csv --step 0.01 --exponent 2 --half-angle 1.5708
```

If transmit and receive optics differ:

```tcl
$phy($id) useDifferentBeamPattern
$phy($id) setBeamPatternPath tx_beam.csv rx_beam.csv
```

For identical optics:

```tcl
$phy($id) useSameBeamPattern
$phy($id) setBeamPatternPath beam.csv
```

The repository default is `dbs/bluecomm/beam_pattern/beam5mbps.csv`.

## Attenuation LUT

The attenuation reader expects positive downward depth:

```text
depth,c,temperature
```

For example, `setZ_ -10` corresponds to depth `10` in the table. Generate a
constant profile with:

```bash
./generate_optical_luts.sh attenuation \
  -o attenuation_device_a.csv --depth-max 125 --depth-step 1 \
  --c 0.32 --temperature 293.15
```

For a simple linear gradient, add `--c-slope` in `1/m^2`:

```bash
./generate_optical_luts.sh attenuation \
  -o attenuation_gradient.csv --depth-max 100 --depth-step 1 \
  --c 0.25 --c-slope 0.001 --temperature 294
```

For real water, replace the generated values with CTD/optical measurements or
a validated Hydrolight export. Enable the table with:

```tcl
$propagation setLUTFileName $opt(attenuation_lut)
$propagation setLUT
$propagation setVariableC
```

Use `setFixedC` instead when the water is intentionally uniform.

## Ambient-light noise LUT

The noise reader skips the first two lines. The default file uses them as
metadata:

```text
0.6
21
0 0
1 0.85285
2 0.48938
```

The remaining rows are `depth noise_value`. Generate a simple exponential
starter profile with:

```bash
./generate_optical_luts.sh noise \
  -o noise_device_a.txt --depth-max 125 --depth-step 1 \
  --threshold 0.6 --noise0 1.0 --decay 0.08
```

For real conditions, use Hydrolight output or calibrated underwater-light
measurements at the modem wavelength, and confirm the units match the optical
PHY. Enable it with:

```tcl
$phy($id) setLUTFileName $opt(noise_lut_path)
$phy($id) setLUTSeparator " "
$phy($id) useLUT
```

## Maximum-range LUT

The maximum-range format is:

```text
c,max_range_without_noise,max_range_with_noise
```

Generate a theoretical estimate using the exact device parameters:

```bash
./generate_optical_luts.sh max-range \
  -o max_range_device_a.csv --c-min 0.05 --c-max 2.45 --c-step 0.05 \
  --txpower 50 --bitrate 1000000 --acq-threshold 10
```

This mode uses the DESERT Lambert-Beer link budget and an SNR threshold. It is
not a measured range. For a real device, sweep distance for each `c`, record
packet error rate or acquisition success, choose a criterion such as `PER <=
1%`, and store the largest passing distance in the table. The second range
column is the corresponding result with an increased noise multiplier. The
default `--noise-factor 1.25` is only a rough placeholder; replace it with a
measured noisy result. The accepted `--bitrate` option documents the device
configuration, but this simple generator does not model bitrate-dependent PER.

The beam-pattern PHY uses this table as an acceptance gate and scales it with
the transmit/receive beam factors. The underlying received-power calculation
still comes from optical propagation, so the tables must be calibrated
consistently.

## Using generated files

Point the Tcl scenario at the generated files:

```tcl
set opt(noise_lut_path)     "my_luts/noise_device_a.txt"
set opt(attenuation_lut)    "my_luts/attenuation_device_a.csv"
set opt(beam_lut_path)      "my_luts/beam_device_a.csv"
set opt(max_range_lut_path) "my_luts/max_range_device_a.csv"
```

Run from the Optical sample directory so the existing relative paths resolve:

```bash
cd DESERT_Framework/DESERT/samples/desert_samples/Channel/Optical
ns test_single_hop_opticalbeampatter.tcl
```

## Validation checklist

- No header rows; all numeric values are finite.
- Beam angles cover `[-pi, pi]` and are sorted.
- Depth tables cover every simulation depth.
- Max-range `c` covers every attenuation coefficient in use.
- The generated files match wavelength, bitrate, optical power, receiver area,
  sensitivity, and noise assumptions.
- Test distances below and above the predicted range.
- Compare packet error rate against the measurements used for calibration.
- Record modem settings, wavelength, water conditions, temperature, and date
  with each measured LUT set.
