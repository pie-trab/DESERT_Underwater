#
# Multi-hop underwater optical chain, redesigned (v2).
#
# HOW THIS EXAMPLE WORKS
# ----------------------
# The topology is a chain of n_relays + 2 modems, one modem per relay:
#
#   sender -> relay 1 -> relay 2 -> ... -> relay n -> receiver
#
# CONTRARY TO THE PREVIOUS multi_hop_optical_tdma*.tcl GENERATION, each
# relay is a single DESERT modem with ONE optical head that both receives
# from its predecessor and transmits to its successor.  There is no second
# "TX head" modem and no simulated 1 m intra-relay water gap: the packet is
# handed up from the radio to the IP layer and forwarded back down by
# ordinary static routing, exactly like a real relay electronics box
# would do.  Benefits of this design:
#
#   * the propagated chain length in the simulator equals the number of
#     physical devices (no synthetic second node per relay);
#   * the number of TDMA slots equals the node count, so each relay gets
#     double the service share of the old two-head design, and the frame
#     is shorter (throughput is limited by frame/slots, not by relays);
#   * no synthetic intra-relay optical link to fashion attenuation for;
#   * every hop edge in the metrics corresponds to a real physical link:
#     edge h is the transmission of modem h received by modem h + 1.
#
# Half-duplex feasibility: UW/TDMA gives every modem its own slot in a
# common frame; a relay receives during the slots of its neighbours and
# transmits during its own slot, so RX and TX never overlap (the guard
# time covers the propagation/processing margins).  A packet received
# during one frame can therefore be forwarded typically within the same
# frame, giving a near-limited pipeline visibility for chains.
#
# The beam-pattern LUT variant is available in the same file through the
# final command-line flag beam_mode=1: it swaps the optical PHY for
# Module/UW/UWOPTICALBEAMPATTERN and loads the repository noise/beam/
# max-range LUTs.  In BOTH beam modes the water channel model is the same
# analytic fixed-c propagation, so a sweep over attenuation keeps a
# consistent baseline; only the hardware model (directional beam pattern
# plus measured ambient noise) changes.  Chains are horizontal (every
# modem shares the scalar depth) so a single per-head inclination of 0
# is faithful; depth profiles are intentionally not supported.
#
# RUNNING
# -------
#   source <DESERT_build>/environment
#   ns multi_hop_optical_v2.tcl \
#       n_relays cbr_period packet_size hop_length depth stop_time \
#       rngstream poisson_traffic attenuation_scale optical_txpower \
#       optical_acq_threshold_db optical_theta beam_mode
#
# All thirteen arguments are normally supplied by the runner.  hop_length
# is the distance between consecutive modems (the runner derives it from
# the total source-destination distance).
#

################################
# User-changeable parameters    #
################################

# Traffic and schedule.
set opt(starttime)          0.1       ;# s: sender application start time
set opt(stoptime)           1000.0    ;# s: sender application stop time
set opt(cbr_period)         0.25      ;# s: mean inter-packet time (Poisson)
set opt(pktsize)            125       ;# byte: application payload
set opt(poisson_traffic)    1         ;# 0=periodic CBR, 1=Poisson CBR
set opt(rngstream)          1         ;# RNG substream (one per repetition)

# Topology.
set opt(n_relays)           1         ;# relay modems (one node per relay)
set opt(hop_length)         50.0      ;# m: distance between modem centres
set opt(depth)              -10.0     ;# m: shared depth of every modem

# Water channel (analytic fixed c; identity for CLI runs).
set opt(attenuation_c_default) 0.3    ;# 1/m: clear-water reference
set opt(attenuation_scale)  1.0       ;# multiplicative scale for sweeps

# Optical physical-layer parameters.
set opt(freq)               7.59e14       ;# Hz: blue-light carrier
set opt(bw)                 1000000       ;# Hz: signal bandwidth
set opt(bitrate)            1000000       ;# bit/s
set opt(txpower)            10.0          ;# W: optical transmit power
set opt(acq_threshold_db)   15.0          ;# dB: acquisition threshold
set opt(theta)              0.524         ;# rad: beam half-divergence
set opt(id)                 1.0e-9        ;# A: photodiode dark current
set opt(il)                 1.0e-6        ;# A: ambient background photocurrent
set opt(shunt_resistance)   1.49e9        ;# ohm: receiver shunt resistance
set opt(sensitivity)        0.26          ;# A/W: photodiode sensitivity
set opt(temperature)        313.15        ;# K: receiver temperature
set opt(rx_area)            330.06e-6     ;# m^2: receiver aperture area
set opt(tx_area)            36e-6         ;# m^2: transmitter aperture area

# TDMA parameters.
set opt(frame_duration)     0.1           ;# s: minimum frame; auto-extended
set opt(auto_frame_duration) 1
set opt(guard_time)         0.01          ;# s: inter-slot guard interval
set opt(max_packet_per_slot) 2            ;# packets per modem per slot
set opt(queue_size)         32            ;# packets buffered per modem
set opt(drop_old_)          0             ;# drop the newly arriving packet

# Beam-pattern LUT variant.
set opt(beam_mode)          0             ;# 1 = UWOPTICALBEAMPATTERN
set opt(noise_lut_path)     "../../../dbs/optical_noise/LUT.txt"
set opt(beam_lut_path)      "../../../dbs/bluecomm/beam_pattern/beam5mbps.csv"
set opt(max_range_lut_path) "../../../dbs/bluecomm/max_range/max_range5mbps.csv"
# The CTD attenuation LUT path is defined for exact behavioural parity
# with the old beam example (its file is referenced but never applied:
# sweeps use setFixedC on the analytic c).  The plain mode uses no LUT.
set opt(attenuation_lut_path) "../../../dbs/optical_attenuation/lut_532nm/lut_532nm_CTD025.csv"

# Diagnostics and traces.
set opt(verbose)            1
set opt(debug)              0
set opt(trace_files)        0
set opt(trace_prefix)       "multi_hop_optical_v2"
set opt(maxinterval)        1.0           ;# s: interference history window

################################
# Optional command-line values  #
################################

if {$argc > 0} {
    if {$argc != 13} {
        puts "Usage: ns multi_hop_optical_v2.tcl n_relays cbr_period packet_size hop_length depth stop_time rngstream poisson_traffic attenuation_scale txpower acq_threshold_db theta beam_mode"
        exit 1
    }
    set opt(n_relays)         [lindex $argv 0]
    set opt(cbr_period)       [lindex $argv 1]
    set opt(pktsize)          [lindex $argv 2]
    set opt(hop_length)       [lindex $argv 3]
    set opt(depth)            [lindex $argv 4]
    set opt(stoptime)         [lindex $argv 5]
    set opt(rngstream)        [lindex $argv 6]
    set opt(poisson_traffic)  [lindex $argv 7]
    set opt(attenuation_scale) [lindex $argv 8]
    set opt(txpower)          [lindex $argv 9]
    set opt(acq_threshold_db) [lindex $argv 10]
    set opt(theta)            [lindex $argv 11]
    set opt(beam_mode)        [lindex $argv 12]
}

if {$opt(beam_mode)} {
    if {![file exists $opt(beam_lut_path)] || ![file exists $opt(noise_lut_path)]} {
        puts "beam_mode requested but beam/noise LUT files not found:"
        puts "  $opt(beam_lut_path)"
        puts "  $opt(noise_lut_path)"
        puts "(run from the Optical directory, or set beam_mode = 0)"
        exit 2
    }
}

# One modem per relay plus the two end modems.
set opt(nn)          [expr {$opt(n_relays) + 2}]
set opt(sender_id)   0
set opt(receiver_id) [expr {$opt(nn) - 1}]
set opt(n_hops)      [expr {$opt(nn) - 1}]

# TDMA frame sizing, same rule as the acoustic v2 baseline: every slot must
# fit one payload packet plus guard time with a 20% scheduling margin.
set opt(packet_time) [expr {8.0 * $opt(pktsize) / $opt(bitrate)}]
set opt(min_frame_duration) [expr {$opt(nn) * ($opt(packet_time) + $opt(guard_time)) * 1.20}]
if {$opt(auto_frame_duration) &&
        $opt(frame_duration) < $opt(min_frame_duration)} {
    set opt(frame_duration) $opt(min_frame_duration)
}

# Packets generated until stoptime must be able to reach the sink before
# the MACs stop, accounting for the multi-hop TDMA pipeline latency (up to
# one frame per hop plus queueing); the margin also keeps every residual
# queue non-empty only when the traffic itself is saturated.
set opt(sim_end) [expr {$opt(stoptime)
    + ($opt(n_hops) + 2) * $opt(frame_duration) + 0.5}]

################################
# DESERT library loading       #
################################

load libMiracle.so
load libMiracleBasicMovement.so
load libuwip.so
load libuwstaticrouting.so
load libmphy.so
load libmmac.so
load libuwmmac_clmsgs.so
load libuwmll.so
load libuwudp.so
load libuwcbr.so
load libuwtdma.so
load libuwem_channel.so
load libuwoptical_propagation.so
load libuwoptical_channel.so
load libuwoptical_phy.so
# NOTE (data-quality workaround): libuwopticalbeampattern is loaded even in
# plain mode on purpose.  Without it, DESERT's packet-header binding order
# makes another module overwrite hdr_uwcbr::sn with a per-transmission
# counter (measured: sn = 9999 when the generation index was 99119 at
# t = 500 s, with identical packet uid and timestamp).  Loading the beam
# library restores the correct value (sn = 99119 mod 65536 = 33584) and
# leaves the simulated network behaviour identical.  The plain optical app
# counters would otherwise be silently corrupted at high rates.
load libuwopticalbeampattern.so

################################
# Simulator and random streams #
################################

set ns [new Simulator]
$ns use-Miracle

global defaultRNG
for {set k 0} {$k < $opt(rngstream)} {incr k} {
    $defaultRNG next-substream
}

################################
# Trace files                  #
################################

if {$opt(trace_files)} {
    set opt(tracefile)   [open "$opt(trace_prefix).tr" w]
    set opt(cltracefile) [open "$opt(trace_prefix).cltr" w]
} else {
    set opt(tracefile)   [open "/dev/null" w]
    set opt(cltracefile) [open "/dev/null" w]
}

################################
# Module-wide configuration    #
################################

Module/UW/CBR set packetSize_     $opt(pktsize)
Module/UW/CBR set period_         $opt(cbr_period)
Module/UW/CBR set PoissonTraffic_ $opt(poisson_traffic)
Module/UW/CBR set debug_          $opt(debug)

Module/UW/TDMA set frame_duration      $opt(frame_duration)
Module/UW/TDMA set guard_time          $opt(guard_time)
Module/UW/TDMA set tot_slots           $opt(nn)
Module/UW/TDMA set fair_mode           1
Module/UW/TDMA set max_packet_per_slot $opt(max_packet_per_slot)
Module/UW/TDMA set queue_size_         $opt(queue_size)
Module/UW/TDMA set drop_old_           $opt(drop_old_)
Module/UW/TDMA set sea_trial_          0
Module/UW/TDMA set mac2phy_delay_      [expr {1.0e-9}]
Module/UW/TDMA set debug_              $opt(debug)

if {$opt(beam_mode)} {
    Module/UW/UWOPTICALBEAMPATTERN set TxPower_                 $opt(txpower)
    Module/UW/UWOPTICALBEAMPATTERN set BitRate_                 $opt(bitrate)
    Module/UW/UWOPTICALBEAMPATTERN set AcquisitionThreshold_dB_ $opt(acq_threshold_db)
    Module/UW/UWOPTICALBEAMPATTERN set Id_                      $opt(id)
    Module/UW/UWOPTICALBEAMPATTERN set Il_                      $opt(il)
    Module/UW/UWOPTICALBEAMPATTERN set R_                       $opt(shunt_resistance)
    Module/UW/UWOPTICALBEAMPATTERN set S_                       $opt(sensitivity)
    Module/UW/UWOPTICALBEAMPATTERN set T_                       $opt(temperature)
    Module/UW/UWOPTICALBEAMPATTERN set Ar_                      $opt(rx_area)
    Module/UW/UWOPTICALBEAMPATTERN set debug_                   $opt(debug)
} else {
    Module/UW/OPTICAL/PHY set TxPower_                 $opt(txpower)
    Module/UW/OPTICAL/PHY set BitRate_                 $opt(bitrate)
    Module/UW/OPTICAL/PHY set AcquisitionThreshold_dB_ $opt(acq_threshold_db)
    Module/UW/OPTICAL/PHY set Id_                      $opt(id)
    Module/UW/OPTICAL/PHY set Il_                      $opt(il)
    Module/UW/OPTICAL/PHY set R_                       $opt(shunt_resistance)
    Module/UW/OPTICAL/PHY set S_                       $opt(sensitivity)
    Module/UW/OPTICAL/PHY set T_                       $opt(temperature)
    Module/UW/OPTICAL/PHY set Ar_                      $opt(rx_area)
    Module/UW/OPTICAL/PHY set debug_                   $opt(debug)
}

# One shared optical channel: TDMA prevents simultaneous transmissions and
# the MAC destination field discards packets heard by non-destined modems.
set channel [new Module/UW/Optical/Channel]
set data_mask [new MSpectralMask/Rect]
$data_mask setFreq      $opt(freq)
$data_mask setBandwidth $opt(bw)

################################
# Node-construction procedure  #
################################

proc createOpticalNode {id} {
    global ns channel opt
    global node cbr udp ipr ipif mll mac phy position portnum interf_data
    global propagation data_mask

    set node($id) [$ns create-M_Node $opt(tracefile) $opt(cltracefile)]
    for {set dst 0} {$dst < $opt(nn)} {incr dst} {
        set cbr($id,$dst) [new Module/UW/CBR]
        $node($id) addModule 7 $cbr($id,$dst) 1 "CBR"
    }
    set udp($id)  [new Module/UW/UDP]
    set ipr($id)  [new Module/UW/StaticRouting]
    set ipif($id) [new Module/UW/IP]
    set mll($id)  [new Module/UW/MLL]
    set mac($id)  [new Module/UW/TDMA]
    if {$opt(beam_mode)} {
        set phy($id) [new Module/UW/UWOPTICALBEAMPATTERN]
    } else {
        set phy($id) [new Module/UW/OPTICAL/PHY]
    }

    $node($id) addModule 6 $udp($id)  1 "UDP"
    $node($id) addModule 5 $ipr($id)  1 "IPR"
    $node($id) addModule 4 $ipif($id) 1 "IPF"
    $node($id) addModule 3 $mll($id)  1 "MLL"
    $node($id) addModule 2 $mac($id)  1 "MAC"
    $node($id) addModule 1 $phy($id)  1 "PHY"

    for {set dst 0} {$dst < $opt(nn)} {incr dst} {
        $node($id) setConnection $cbr($id,$dst) $udp($id) 0
        set portnum($id,$dst) [$udp($id) assignPort $cbr($id,$dst)]
    }
    $node($id) setConnection $udp($id)  $ipr($id)  1
    $node($id) setConnection $ipr($id)  $ipif($id) 1
    $node($id) setConnection $ipif($id) $mll($id)  1
    $node($id) setConnection $mll($id)  $mac($id)  1
    $node($id) setConnection $mac($id)  $phy($id)  1
    $node($id) addToChannel $channel $phy($id) 1

    # Propagation object dedicated to each RECEIVING modem (the receiving
    # modem of link h evaluates the received power of hop h's packets).  In
    # both hardware modes the water attenuation model is the same analytic
    # fixed-c law, so the two variants differ only in beam pattern and
    # receiver noise, never in the water channel itself.
    set propagation($id) [new Module/UW/OPTICAL/Propagation]
    $propagation($id) setAr    $opt(rx_area)
    $propagation($id) setAt    $opt(tx_area)
    $propagation($id) setTheta $opt(theta)
    $propagation($id) setC [expr {$opt(attenuation_c_default) * $opt(attenuation_scale)}]
    if {$opt(beam_mode)} {
        # Directional attenuation geometry for the beam-LUT hardware.
        $propagation($id) setDirectional
        $propagation($id) setLUTFileName $opt(attenuation_lut_path)
        $propagation($id) setLUTSeparator ","
        $propagation($id) setFixedC
    } else {
        $propagation($id) setFixedC
    }
    $propagation($id) set debug_ $opt(debug)
    $phy($id) setPropagation $propagation($id)

    # One interference history per PHY; TDMA avoids planned overlap.
    set interf_data($id) [new MInterference/MIV]
    $interf_data($id) set maxinterval_ $opt(maxinterval)
    $interf_data($id) set debug_ $opt(debug)
    $phy($id) setInterference $interf_data($id)
    $phy($id) setSpectralMask $data_mask

    if {$opt(beam_mode)} {
        # Beam-LUT hardware: measured ambient noise, transmit beam pattern
        # and maximum range; all links are horizontal, so a single
        # inclination of zero (X-Z plane) is faithful for TX and RX.
        $phy($id) setLUTFileName $opt(noise_lut_path)
        $phy($id) setLUTSeparator " "
        $phy($id) setBeamPatternPath $opt(beam_lut_path)
        $phy($id) setMaxRangePath $opt(max_range_lut_path)
        $phy($id) useLUT
        $phy($id) setVariableTemperature
        $phy($id) setInclinationAngle 0.0
    }

    # IP and MAC addresses follow the path order.
    $ipif($id) addr [expr {$id + 1}]
    $mac($id) setMacAddr [expr {$id + 1}]
    $mac($id) setSlotNumber $id

    # The chain is laid out on the Y axis, depth shared by all modems.
    set position($id) [new Position/BM]
    $node($id) addPosition $position($id)
    $position($id) setX_ 0.0
    $position($id) setY_ [expr {$id * $opt(hop_length)}]
    $position($id) setZ_ $opt(depth)
}

for {set id 0} {$id < $opt(nn)} {incr id} {
    createOpticalNode $id
}

################################
# Configure CBR and addresses  #
################################

# The source keeps the final receiver IP address end to end; the UDP
# destination port belongs to the sink's paired CBR object.
$cbr($opt(sender_id),$opt(receiver_id)) set destAddr_ [$ipif($opt(receiver_id)) addr]
$cbr($opt(sender_id),$opt(receiver_id)) set destPort_ $portnum($opt(receiver_id),$opt(sender_id))

# MLL next-hop resolution for every pair; the chain inserts only the next
# hop of the final destination, but the full table is harmless and makes
# the example reusable with arbitrary static routes.
for {set src 0} {$src < $opt(nn)} {incr src} {
    for {set dst 0} {$dst < $opt(nn)} {incr dst} {
        if {$src != $dst} {
            $mll($src) addentry [$ipif($dst) addr] [$mac($dst) addr]
        }
    }
}

################################
# Install the forced IP path   #
################################

set destination [$ipif($opt(receiver_id)) addr]
for {set src 0} {$src < $opt(nn)} {incr src} {
    if {$src < $opt(receiver_id)} {
        set next [expr {$src + 1}]
    } else {
        set next $opt(receiver_id)
    }
    $ipr($src) addRoute $destination [$ipif($next) addr]
}

################################
# Start/stop schedule          #
################################

# MACs start before traffic so the frame phase is deterministic.  MACs stop
# only after a drain margin covering the multi-hop pipeline latency; every
# non-received packet is then attributable to a real drop (attenuation,
# queue overflow, ...), never to a truncated experiment tail.
for {set id 0} {$id < $opt(nn)} {incr id} {
    $ns at 0.0 "$mac($id) start"
    $ns at $opt(sim_end) "$mac($id) stop"
}
$ns at $opt(starttime) "$cbr($opt(sender_id),$opt(receiver_id)) start"
$ns at $opt(stoptime)  "$cbr($opt(sender_id),$opt(receiver_id)) stop"

################################
# End-of-run metrics block     #
################################

# Machine-readable summary parsed by the experiment runner.  Semantics:
#   sent_packets     CBR packets generated at the source application
#   received_packets CBR packets delivered to the sink application
#   ftt_*            forward trip time statistics at the sink
#   node stats:      mac_tx  : transmissions handed down to the radio
#                    mac_rx  : received packets whose destination is this
#                              modem (kept; not cross-heard traffic)
#                    up_rx   : packets the IP layer handed down to the MAC
#                              (source-generated or forwarded)
#                    q_final : residual packets in the MAC queue at stop
# Hop edges link modem h -> modem h+1; edge PDR(h) = mac_rx[h+1]/mac_tx[h].
proc finish {} {
    global ns opt cbr mac

    set sent     [$cbr($opt(sender_id),$opt(receiver_id)) getsentpkts]
    set received [$cbr($opt(receiver_id),$opt(sender_id)) getrecvpkts]

    puts "=== METRICS v2 ==="
    puts "sim_beam_mode: $opt(beam_mode)"
    puts "sim_node_count: $opt(nn)"
    puts "sim_hop_count: $opt(n_hops)"
    puts "sim_hop_length_m: $opt(hop_length)"
    puts "sim_packet_time_s: $opt(packet_time)"
    puts "sim_frame_duration_s: $opt(frame_duration)"
    puts "sent_packets: $sent"
    puts "received_packets: $received"
    puts "ftt_mean_s: [$cbr($opt(receiver_id),$opt(sender_id)) getftt]"
    puts "ftt_std_s: [$cbr($opt(receiver_id),$opt(sender_id)) getfttstd]"
    puts "cbr_thr_bps: [$cbr($opt(receiver_id),$opt(sender_id)) getthr]"
    puts "node_stats:"
    for {set id 0} {$id < $opt(nn)} {incr id} {
        puts "  node $id: mac_tx=[$mac($id) get_sent_pkts] \
mac_rx=[$mac($id) get_recv_pkts] \
up_rx=[$mac($id) get_upper_data_pkts_rx] \
q_final=[$mac($id) get_buffer_size]"
    }
    puts "=== END ==="

    $ns flush-trace
    close $opt(tracefile)
    close $opt(cltracefile)
}

################################
# Run the simulation           #
################################

puts "Starting multi-hop optical chain (v2), beam_mode=$opt(beam_mode)"
puts "Path has $opt(n_hops) hops and $opt(n_relays) single-head relays"
$ns at [expr {$opt(sim_end) + 1.0}] "finish; $ns halt"
$ns run