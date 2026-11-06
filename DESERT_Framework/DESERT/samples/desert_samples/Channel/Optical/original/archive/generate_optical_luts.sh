#!/usr/bin/env bash
# Generate analytical starter LUTs for DESERT optical simulations.
# Modes: beam, attenuation, noise, max-range.
# Device-specific beam and range tables must ultimately be calibrated with data.

set -u
script_name="$(basename "$0")"

usage() {
    cat <<EOF
Usage: $script_name MODE -o FILE [options]
Modes: beam, attenuation, noise, max-range

Beam:        --min-angle A --max-angle A --step A --half-angle A
             --exponent N --side-lobe F
Attenuation: --depth-max D --depth-step D --c C --c-slope C
             --temperature T --temp-slope T
Noise:       --depth-max D --depth-step D --threshold N --noise0 N --decay K
Max-range:   --c-min C --c-max C --c-step C --txpower W --tx-area A
             --rx-area A --theta R --sensitivity S --dark-current I
             --light-current I --shunt-resistance R --temperature T
             --bandwidth B --bitrate B --acq-threshold D --noise-factor F
             --range-limit D
EOF
}

die() { echo "$script_name: $*" >&2; exit 2; }
[[ $# -gt 0 ]] || { usage; exit 2; }
mode="$1"; shift
case "$mode" in beam|attenuation|noise|max-range) ;; -h|--help) usage; exit 0 ;; *) die "unknown mode: $mode" ;; esac

output=""
min_angle=-3.141592653589793; max_angle=3.141592653589793
angle_step=0.01; half_angle=1.570796326794897; beam_exponent=2; side_lobe=0
depth_max=125; depth_step=1; c0=0.32; c_slope=0
temperature=293.15; temp_slope=0
noise_threshold=0.6; noise0=1; noise_decay=0.08
c_min=0.05; c_max=2.45; c_step=0.05; txpower=50; bitrate=1000000
tx_area=1e-5; rx_area=1.1e-6; theta=1; sensitivity=0.26
dark_current=1e-9; light_current=1e-6; shunt_resistance=1.49e9
bandwidth=100000; acq_threshold=10; noise_factor=1.25; range_limit=10000

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output) [[ $# -ge 2 ]] || die "missing value for $1"; output="$2"; shift 2 ;;
        --min-angle) min_angle="$2"; shift 2 ;; --max-angle) max_angle="$2"; shift 2 ;;
        --step) angle_step="$2"; shift 2 ;; --half-angle) half_angle="$2"; shift 2 ;;
        --exponent) beam_exponent="$2"; shift 2 ;; --side-lobe) side_lobe="$2"; shift 2 ;;
        --depth-max) depth_max="$2"; shift 2 ;; --depth-step) depth_step="$2"; shift 2 ;;
        --c) c0="$2"; shift 2 ;; --c-slope) c_slope="$2"; shift 2 ;;
        --temperature) temperature="$2"; shift 2 ;; --temp-slope) temp_slope="$2"; shift 2 ;;
        --threshold) noise_threshold="$2"; shift 2 ;; --noise0) noise0="$2"; shift 2 ;;
        --decay) noise_decay="$2"; shift 2 ;; --c-min) c_min="$2"; shift 2 ;;
        --c-max) c_max="$2"; shift 2 ;; --c-step) c_step="$2"; shift 2 ;;
        --txpower) txpower="$2"; shift 2 ;; --bitrate) bitrate="$2"; shift 2 ;;
        --tx-area) tx_area="$2"; shift 2 ;; --rx-area) rx_area="$2"; shift 2 ;;
        --theta) theta="$2"; shift 2 ;; --sensitivity) sensitivity="$2"; shift 2 ;;
        --dark-current) dark_current="$2"; shift 2 ;; --light-current) light_current="$2"; shift 2 ;;
        --shunt-resistance) shunt_resistance="$2"; shift 2 ;; --bandwidth) bandwidth="$2"; shift 2 ;;
        --acq-threshold) acq_threshold="$2"; shift 2 ;; --noise-factor) noise_factor="$2"; shift 2 ;;
        --range-limit) range_limit="$2"; shift 2 ;; -h|--help) usage; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done

[[ -n "$output" ]] || die "an output file is required; use -o FILE"
mkdir -p "$(dirname "$output")" || die "cannot create output directory"

generate_beam() {
    awk -v lo="$min_angle" -v hi="$max_angle" -v step="$angle_step" \
        -v half="$half_angle" -v exponent="$beam_exponent" -v side="$side_lobe" '
        BEGIN {
            if (step <= 0 || hi <= lo || half <= 0 || exponent <= 0) exit 10
            pi = atan2(0, -1)
            for (a = lo; a <= hi + step/1000; a += step) {
                aa = (a < 0 ? -a : a)
                if (aa <= half) { f = cos((aa/half)*pi/2); f = f ^ exponent }
                else f = side
                if (f < 0) f = 0; if (f > 1) f = 1
                printf "%.10g,%.10g\n", a, f
            }
        }' > "$output" || die "invalid beam parameters"
}

generate_attenuation() {
    awk -v dmax="$depth_max" -v ds="$depth_step" -v c="$c0" \
        -v cs="$c_slope" -v t="$temperature" -v ts="$temp_slope" '
        BEGIN {
            if (dmax < 0 || ds <= 0) exit 10
            for (d = 0; d <= dmax + ds/1000; d += ds)
                printf "%.10g,%.10g,%.10g\n", d, c + cs*d, t + ts*d
        }' > "$output" || die "invalid attenuation parameters"
}

generate_noise() {
    awk -v dmax="$depth_max" -v ds="$depth_step" -v threshold="$noise_threshold" \
        -v n0="$noise0" -v decay="$noise_decay" '
        BEGIN {
            if (dmax < 0 || ds <= 0 || n0 < 0 || decay < 0) exit 10
            rows = int(dmax/ds + 1.0000001)
            printf "%.10g\n%d\n", threshold, rows
            for (d = 0; d <= dmax + ds/1000; d += ds)
                printf "%.10g %.10g\n", d, n0*exp(-decay*d)
        }' > "$output" || die "invalid noise parameters"
}

generate_max_range() {
    awk -v cmin="$c_min" -v cmax="$c_max" -v cs="$c_step" \
        -v tx="$txpower" -v at="$tx_area" -v ar="$rx_area" -v theta="$theta" \
        -v sens="$sensitivity" -v idark="$dark_current" -v ilight="$light_current" \
        -v rshunt="$shunt_resistance" -v temp="$temperature" -v bw="$bandwidth" \
        -v threshold="$acq_threshold" -v nf="$noise_factor" -v limit="$range_limit" \
        -v rate="$bitrate" '
        function snr_db(d, c, noise_mult, gain, pr, pn) {
            # Avoid an exp() underflow warning during the upper-bound search.
            if (c*d > 700) return -1e9
            gain = (2*ar)/(atan2(0,-1)*d*d*(1-cos(theta)) + 2*at)*exp(-c*d)
            pr = tx*gain
            pn = noise_mult*(2*1.6e-19*(idark+ilight)*bw + (4*1.38e-23*temp*bw)/rshunt)
            return 10*log(((sens*pr)^2)/pn)/log(10)
        }
        function find_range(c, noise_mult, lo, hi, mid, i) {
            lo=1e-9; hi=limit
            for (i=0; i<80; i++) {
                mid=(lo+hi)/2
                if (snr_db(mid,c,noise_mult)>=threshold) lo=mid; else hi=mid
            }
            return lo
        }
        BEGIN {
            # rate documents the device configuration; this model is SNR-only.
            if (rate<=0 || cmax<cmin || cs<=0 || tx<=0 || at<=0 || ar<=0 ||
                theta<=0 || sens<=0 || bw<=0 || rshunt<=0 || nf<=0 || limit<=0) exit 10
            for (c=cmin; c<=cmax+cs/1000; c+=cs)
                printf "%.10g,%.10g,%.10g\n", c, find_range(c,1), find_range(c,nf)
        }' > "$output" || die "invalid max-range parameters"
}

case "$mode" in
    beam) generate_beam ;;
    attenuation) generate_attenuation ;;
    noise) generate_noise ;;
    max-range) generate_max_range ;;
esac
echo "Generated $mode LUT: $output"
