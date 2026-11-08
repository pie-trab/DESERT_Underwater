# Diagnostic: acoustic equal-hop chain

This table is not a physical PDR curve. PDR below 0.95 is an unresolved first-hop simulation artifact; delay is conditional on delivered packets and energy includes transmissions of lost packets.

```
    technology  distance_m  repetitions  hop_count  unique_modems  link_endpoint_modems  pdr_mean  pdr_ci95  delay_mean_s_mean  delay_mean_s_ci95  energy_per_bit_uj_mean  energy_per_bit_uj_ci95  pdr_below_095     series_role                                              artifact_note
acoustic_chain        50.0           10          3              4                     6  1.000000  0.000000           0.272936           0.015219             3910.631741            3.428795e-13          False diagnostic_only PDR losses localize to the first hop; mechanism unresolved
acoustic_chain       100.0           10          5              6                    10  1.000000  0.000000           0.494145           0.024758             6517.719569            6.505681e-13          False diagnostic_only PDR losses localize to the first hop; mechanism unresolved
acoustic_chain       200.0           10         10             11                    20  1.000000  0.000000           1.094980           0.062314            13035.439137            1.371518e-12          False diagnostic_only PDR losses localize to the first hop; mechanism unresolved
acoustic_chain       500.0           10         25             26                    50  0.681974  0.028569           2.840352           0.147624            33100.072499            6.668247e+01           True diagnostic_only PDR losses localize to the first hop; mechanism unresolved
acoustic_chain      1000.0           10         50             51                   100  0.586385  0.044337           8.841518           2.198612            65960.555546            1.301482e+02           True diagnostic_only PDR losses localize to the first hop; mechanism unresolved
acoustic_chain      1500.0           10         75             76                   150  1.000000  0.000000          18.836550           6.271349            97765.793529            1.040909e-11          False diagnostic_only PDR losses localize to the first hop; mechanism unresolved
```
