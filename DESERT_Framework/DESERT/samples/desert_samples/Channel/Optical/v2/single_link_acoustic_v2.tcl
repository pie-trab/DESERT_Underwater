#
# Acoustic single-link baseline, redesigned (v2) companion for the
# multi-hop optical comparison.
#
# HOW THIS EXAMPLE WORKS
# ----------------------
# Two acoustic modems talk directly:
#
#   modem 0 (CBR source) ---- D metres ---- modem 1 (sink)
#
# The stack is the standard DESERT one:
#
#   UW/CBR -> UW/UDP -> UW/StaticRouting -> UW/IP -> UW/MLL -> UW/TDMA
#          -> UW/PHYSICAL -> UnderwaterChannel
#
# This file is deliberately written to be metric-compatible with
# `multi_hop_optical_v2.tcl`: both scripts speak the same command line
# conventions and print an identical machine-readable summary block, so one
# Python experiment runner can drive both and compare the technologies
# apples-to-apples (same traffic, payload, schedule, RNG substreams).
#
# DESIGN NOTES (v2)
# -----------------
# - TDMA is kept on purpose (not a random-access MAC) so that the acoustic
#   baseline is never penalised by collisions that the TDMA-multi-hop
#   optical chain never sees.
# - The frame auto-expands to fit one payload packet plus guard time in a
#   slot, exactly like the optical chain, so both technologies suffer a
#   comparable scheduling delay at saturation.
# - The end-of-run summary prints per-node MAC TX/RX counters, upper-layer
#   delivered counts and the residual queue size of every node; the runner
#   uses them to compute energy-per-bit (actual PHY transmissions), hop
#   PDRs and queue-drop accounting.
# - Only the sender runs an application. n_relays is accepted (and ignored)
#   to keep one unified argument list for both scripts.
#
# RUNNING
# -------
#   source <DESERT_build>/environment
#   ns single_link_acoustic_v2.tcl \
#       n_relays cbr_period packet_size distance depth stop_time \
#       rngstream poisson_traffic
#
# All eight positional arguments are normally supplied by the runner.  With
# no arguments the built-in defaults below are used.
#

################################
# User-changeable parameters    #
################################

# Topology and traffic.
set opt(nn)                 2         ;# number of acoustic modems
set opt(sender_id)          0         ;# CBR transmitter
set opt(receiver_id)        1         ;# CBR receiver
set opt(starttime)          0.1       ;# s: CBR start time
set opt(stoptime)           1000.0    ;# s: CBR stop time
set opt(cbr_period)         0.25      ;# s: mean inter-packet time (Poisson)
set opt(pktsize)            125       ;# byte: application payload
set opt(poisson_traffic)    1         ;# 0=periodic CBR, 1=Poisson CBR
set opt(rngstream)          1         ;# RNG substream (one per repetition)
set opt(distance)           20.0      ;# m: direct transmitter/receiver range
set opt(depth)              -10.0     ;# m: common modem depth

# Acoustic physical-layer parameters.
set opt(freq)               50000.0   ;# Hz: acoustic center frequency
set opt(bw)                 26000.0   ;# Hz: signal bandwidth
set opt(propagation_speed)  1500.0    ;# m/s: sound speed in water
set opt(bitrate)            20768.0   ;# bit/s: acoustic modem bit rate
set opt(txpower)            180.0     ;# dB re 1 uPa at 1 m: source level
# 0 dB acquisition: the PHY syncs on every packet and the built-in BPSK
# BER/SNR curve (%PER = 1-(1-.5*erfc(sqrt(SINR)))^nbits) then produces
# graded losses as the distance grows.  With the historical 15 dB gate
# every acquired packet had BER ~ 1e-15, the curve was unreachable, and
# the link degenerated into a binary ~1147 m cliff (measured: 100 %
# delivery at 1146 m, zero at 1147 m).
set opt(acquisition_db)     0.0       ;# dB: PHY acquisition threshold
set opt(max_tx_range)       200.0     ;# m: PHY range cutoff
set opt(spreading)          2         ;# practical spreading coefficient
set opt(windspeed)          10.0      ;# m/s: environmental propagation input
set opt(shipping)           1         ;# shipping activity used by propagation

# TDMA timing.  Same auto-expansion rule as the v2 optical chain.
set opt(frame_duration)     0.1       ;# s: base frame (auto-expanded below)
set opt(guard_time)         0.01      ;# s: guard time around a slot
set opt(auto_frame_duration) 1
set opt(queue_size)         64        ;# packets buffered by the sender MAC
set opt(max_packet_per_slot) 1        ;# packets sent by one modem per slot

# Diagnostics and traces.
set opt(verbose)            1         ;# 1=print the final packet summary
set opt(debug)              0
set opt(trace_files)        0         ;# 1=write trace files beside script
set opt(trace_prefix)       "single_link_acoustic_v2"
set opt(maxinterval)        200.0     ;# s: interference history window

################################
# Optional command-line values  #
################################

if {$argc > 0} {
    if {$argc != 8} {
        puts "Usage: ns single_link_acoustic_v2.tcl n_relays cbr_period packet_size distance depth stop_time rngstream poisson_traffic"
        exit 1
    }
    set opt(n_relays)        [lindex $argv 0]   ;# accepted, ignored (single link)
    set opt(cbr_period)      [lindex $argv 1]
    set opt(pktsize)         [lindex $argv 2]
    set opt(distance)        [lindex $argv 3]
    set opt(depth)           [lindex $argv 4]
    set opt(stoptime)        [lindex $argv 5]
    set opt(rngstream)       [lindex $argv 6]
    set opt(poisson_traffic) [lindex $argv 7]
}

# A packet must fit in one assigned slot.  The extra 20% margin covers
# MAC/PHY headers and simulator event ordering.  Two modems share the frame.
set opt(packet_time) [expr {8.0 * $opt(pktsize) / $opt(bitrate)}]
set opt(min_frame_duration) [expr {1.0 * ($opt(packet_time) + $opt(guard_time)) * 1.20}]
if {$opt(auto_frame_duration) &&
        $opt(frame_duration) < $opt(min_frame_duration)} {
    set opt(frame_duration) $opt(min_frame_duration)
}

# The run is repeated exactly once per RNG substream, so every repetition is
# an independent sample of the same setup.
set opt(sim_end) [expr {$opt(stoptime)
    + 3.0 * $opt(frame_duration) + 0.5}]

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
load libuwphy_clmsgs.so
load libuwmll.so
load libuwudp.so
load libuwcbr.so
load libuwtdma.so
load libuwinterference.so
load libUwmStd.so
load libuwstats_utilities.so
load libuwphysical.so

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

# Both modems get one slot in the shared frame, identical to the v2 optical
# chain so multi-hop scheduling behaviour is comparable.
Module/UW/TDMA set frame_duration      $opt(frame_duration)
Module/UW/TDMA set guard_time          $opt(guard_time)
Module/UW/TDMA set tot_slots           $opt(nn)
Module/UW/TDMA set fair_mode           1
Module/UW/TDMA set max_packet_per_slot $opt(max_packet_per_slot)
Module/UW/TDMA set queue_size_         $opt(queue_size)
Module/UW/TDMA set drop_old_           0   ;# drop the newly arriving packet
Module/UW/TDMA set sea_trial_          0
Module/UW/TDMA set mac2phy_delay_      [expr {1.0e-9}]
Module/UW/TDMA set debug_              $opt(debug)

# Standard underwater acoustic propagation.
MPropagation/Underwater set practicalSpreading_ $opt(spreading)
MPropagation/Underwater set debug_              $opt(debug)
MPropagation/Underwater set windspeed_          $opt(windspeed)
MPropagation/Underwater set shipping_           $opt(shipping)

set channel [new Module/UnderwaterChannel]
set propagation [new MPropagation/Underwater]
set data_mask [new MSpectralMask/Rect]
$data_mask setFreq              $opt(freq)
$data_mask setBandwidth         $opt(bw)
$data_mask setPropagationSpeed  $opt(propagation_speed)

Module/UW/PHYSICAL set BitRate_                 $opt(bitrate)
Module/UW/PHYSICAL set AcquisitionThreshold_dB_ $opt(acquisition_db)
Module/UW/PHYSICAL set RxSnrPenalty_dB_         0
Module/UW/PHYSICAL set TxSPLMargin_dB_          0
Module/UW/PHYSICAL set MaxTxSPL_dB_             $opt(txpower)
Module/UW/PHYSICAL set MinTxSPL_dB_             10
Module/UW/PHYSICAL set MaxTxRange_              $opt(max_tx_range)
Module/UW/PHYSICAL set PER_target_              0
Module/UW/PHYSICAL set CentralFreqOptimization_ 0
Module/UW/PHYSICAL set BandwidthOptimization_   0
Module/UW/PHYSICAL set SPLOptimization_         0
Module/UW/PHYSICAL set debug_                   $opt(debug)

################################
# Node-construction procedure  #
################################

proc createAcousticNode {id} {
    global ns channel opt node cbr udp ipr ipif mll mac phy position portnum
    global data_mask propagation interf_data

    set node($id) [$ns create-M_Node $opt(tracefile) $opt(cltracefile)]

    set other [expr {1 - $id}]
    set cbr($id,$other) [new Module/UW/CBR]
    $node($id) addModule 7 $cbr($id,$other) 1 "CBR"

    set udp($id)  [new Module/UW/UDP]
    set ipr($id)  [new Module/UW/StaticRouting]
    set ipif($id) [new Module/UW/IP]
    set mll($id)  [new Module/UW/MLL]
    set mac($id)  [new Module/UW/TDMA]
    set phy($id)  [new Module/UW/PHYSICAL]

    $node($id) addModule 6 $udp($id)  1 "UDP"
    $node($id) addModule 5 $ipr($id)  1 "IPR"
    $node($id) addModule 4 $ipif($id) 1 "IPF"
    $node($id) addModule 3 $mll($id)  1 "MLL"
    $node($id) addModule 2 $mac($id)  1 "MAC"
    $node($id) addModule 1 $phy($id)  1 "PHY"

    $node($id) setConnection $cbr($id,$other) $udp($id) 0
    set portnum($id,$other) [$udp($id) assignPort $cbr($id,$other)]
    $node($id) setConnection $udp($id)  $ipr($id)  1
    $node($id) setConnection $ipr($id)  $ipif($id) 1
    $node($id) setConnection $ipif($id) $mll($id)  1
    $node($id) setConnection $mll($id)  $mac($id)  1
    $node($id) setConnection $mac($id)  $phy($id)  1
    $node($id) addToChannel $channel $phy($id) 1

    $ipif($id) addr [expr {$id + 1}]
    $mac($id) setMacAddr [expr {$id + 1}]
    $mac($id) setSlotNumber $id

    # Modems are placed on the Y axis at the requested depth.
    set position($id) [new Position/BM]
    $node($id) addPosition $position($id)
    $position($id) setX_ 0.0
    if {$id == 0} {
        $position($id) setY_ 0.0
    } else {
        $position($id) setY_ $opt(distance)
    }
    $position($id) setZ_ $opt(depth)

    # Each PHY gets its own interference history while sharing the same
    # acoustic propagation and spectral-mask objects.
    set interf_data($id) [new Module/UW/INTERFERENCE]
    $interf_data($id) set maxinterval_ $opt(maxinterval)
    $interf_data($id) set debug_       $opt(debug)
    $phy($id) setPropagation     $propagation
    $phy($id) setSpectralMask    $data_mask
    $phy($id) setInterference    $interf_data($id)
    $phy($id) setInterferenceModel "MEANPOWER"
}

for {set id 0} {$id < $opt(nn)} {incr id} {
    createAcousticNode $id
}

################################
# Addresses, ports and routes  #
################################

$cbr($opt(sender_id),$opt(receiver_id)) set destAddr_ [$ipif($opt(receiver_id)) addr]
$cbr($opt(sender_id),$opt(receiver_id)) set destPort_ $portnum($opt(receiver_id),$opt(sender_id))

for {set src 0} {$src < $opt(nn)} {incr src} {
    for {set dst 0} {$dst < $opt(nn)} {incr dst} {
        if {$src != $dst} {
            $mll($src) addentry [$ipif($dst) addr] [$mac($dst) addr]
            $ipr($src) addRoute [$ipif($dst) addr] [$ipif($dst) addr]
        }
    }
}

################################
# Start/stop schedule          #
################################

# MACs stop only after a drain margin long enough for every packet still
# queued in the source MAC to reach the sink; the runner relies on this to
# attribute every non-received packet to a counted drop (never to silent
# truncation of the experiment tail).
for {set id 0} {$id < $opt(nn)} {incr id} {
    $ns at 0.0 "$mac($id) start"
    $ns at $opt(sim_end) "$mac($id) stop"
}
$ns at $opt(starttime) "$cbr($opt(sender_id),$opt(receiver_id)) start"
$ns at $opt(stoptime)  "$cbr($opt(sender_id),$opt(receiver_id)) stop"

################################
# End-of summary block         #
################################

# Machine-readable block parsed by the experiment runner:
#   sent/received   = CBR counters at the source and the sink application
#   ftt             = forward trip time statistics at the sink
#   node stats      = mac_tx  : transmissions handed down to the radio
#                     mac_rx  : packets received from the radio and kept
#                               (this modem was the destination)
#                     up_rx   : packets delivered by the IP layer down to
#                               the MAC (traffic generated or forwarded)
#                     q_final : residual packets in the MAC queue at stop
# The margin before MAC stop guarantees q_final is empty in normal traffic
# conditions; a residual point still indicates saturation behaviour (see
# runner).
proc finish {} {
    global ns opt cbr mac

    set sent     [$cbr($opt(sender_id),$opt(receiver_id)) getsentpkts]
    set received [$cbr($opt(receiver_id),$opt(sender_id)) getrecvpkts]

    puts "=== METRICS v2 ==="
    puts "sim_node_count: $opt(nn)"
    puts "sim_hop_count: 1"
    puts "sim_distance_m: $opt(distance)"
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

puts "Starting single-link acoustic comparison (v2)"
puts "Direct modem separation: $opt(distance) m"
$ns at [expr {$opt(sim_end) + 1.0}] "finish; $ns halt"
$ns run