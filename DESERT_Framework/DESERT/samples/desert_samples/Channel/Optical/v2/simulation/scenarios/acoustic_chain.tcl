#
# Equal-hop acoustic relay chain (v3), paper-control scenario.
#
# This is the acoustic counterpart of the single-head optical chain:
#
#   sender -> relay 1 -> relay 2 -> ... -> receiver
#
# Each relay is one DESERT modem.  The standard acoustic PHY, channel and
# propagation model are used, with the same TDMA derivation as the M1/M2
# acoustic and optical scenarios.
#
# This scenario is an equal-topology ablation, not an acoustic deployment
# recommendation.  It exists to separate optical PHY effects from the cost
# of relaying.
#
# RUNNING
#   ns acoustic_chain_v3.tcl n_relays cbr_period packet_size total_distance \
#       depth stop_time rngstream poisson_traffic
#
# The total distance is divided into n_relays+1 equal hops.
#

################################
# User-changeable parameters    #
################################

set opt(n_relays)           0         ;# relay modems
set opt(total_distance)     100.0     ;# m: source-destination distance
set opt(depth)              -10.0     ;# m: common modem depth
set opt(cbr_period)         5.0       ;# s: Poisson mean inter-packet time
set opt(pktsize)            125       ;# byte: application payload
set opt(poisson_traffic)    1         ;# 1 = Poisson CBR
set opt(rngstream)          1         ;# RNG substream (one per repetition)
set opt(starttime)          0.1       ;# s: CBR start time
set opt(stoptime)           100.0     ;# s: CBR stop time

# Acoustic physical layer, identical to the direct acoustic baseline.
set opt(freq)               50000.0
set opt(bw)                 26000.0
set opt(propagation_speed)  1500.0
set opt(bitrate)            20768.0
set opt(txpower)            180.0
set opt(acquisition_db)     0.0
set opt(max_tx_range)       200.0
set opt(spreading)          2
set opt(windspeed)          10.0
set opt(shipping)           1

# TDMA parameters.
set opt(guard_time)         0.001
set opt(max_packet_per_slot) 1
set opt(queue_size)         64

# Diagnostics and traces.
set opt(debug)              0
set opt(trace_files)        0
set opt(trace_prefix)       "acoustic_chain_v3"
set opt(maxinterval)        200.0

################################
# Optional command-line values  #
################################

if {$argc > 0} {
    if {$argc != 8} {
        puts "Usage: ns acoustic_chain_v3.tcl n_relays cbr_period packet_size total_distance depth stop_time rngstream poisson_traffic"
        exit 1
    }
    set opt(n_relays)        [lindex $argv 0]
    set opt(cbr_period)      [lindex $argv 1]
    set opt(pktsize)         [lindex $argv 2]
    set opt(total_distance)  [lindex $argv 3]
    set opt(depth)           [lindex $argv 4]
    set opt(stoptime)        [lindex $argv 5]
    set opt(rngstream)       [lindex $argv 6]
    set opt(poisson_traffic) [lindex $argv 7]
}

set opt(nn)          [expr {$opt(n_relays) + 2}]
set opt(sender_id)   0
set opt(receiver_id) [expr {$opt(nn) - 1}]
set opt(n_hops)      [expr {$opt(nn) - 1}]
set opt(hop_length)  [expr {$opt(total_distance) / $opt(n_hops)}]

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

Module/UW/TDMA set frame_duration      $opt(guard_time)
Module/UW/TDMA set guard_time          $opt(guard_time)
Module/UW/TDMA set tot_slots           $opt(nn)
Module/UW/TDMA set fair_mode           1
Module/UW/TDMA set max_packet_per_slot $opt(max_packet_per_slot)
Module/UW/TDMA set queue_size_         $opt(queue_size)
Module/UW/TDMA set drop_old_           0
Module/UW/TDMA set sea_trial_          0
Module/UW/TDMA set mac2phy_delay_      [expr {1.0e-9}]
Module/UW/TDMA set debug_              $opt(debug)

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
    global ns channel opt node cbr udp ipr ipif mll mac phy position
    global portnum data_mask propagation interf_data

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
    set phy($id)  [new Module/UW/PHYSICAL]

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

    $ipif($id) addr [expr {$id + 1}]
    $mac($id) setMacAddr [expr {$id + 1}]
    $mac($id) setSlotNumber $id

    set position($id) [new Position/BM]
    $node($id) addPosition $position($id)
    $position($id) setX_ 0.0
    $position($id) setY_ [expr {$id * $opt(hop_length)}]
    $position($id) setZ_ $opt(depth)

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

puts "EFFECTIVE acoustic_chain: phy_class=[$phy(0) info class] channel_class=[$channel info class] propagation_class=[$propagation info class] bitrate=$opt(bitrate) acquisition_db=$opt(acquisition_db) max_tx_range=$opt(max_tx_range) hop_length=$opt(hop_length) n_hops=$opt(n_hops)"

set opt(cbr_header_bytes) [$cbr(0,1) getcbrheadersize]
set opt(udp_header_bytes) [$udp(0) getudpheadersize]
set opt(ip_header_bytes)  [$ipif(0) getipheadersize]
set opt(header_bytes) [expr {$opt(cbr_header_bytes) +
    $opt(udp_header_bytes) + $opt(ip_header_bytes)}]
set opt(packet_bytes) [expr {$opt(pktsize) + $opt(header_bytes)}]
set opt(airtime) [expr {8.0 * $opt(packet_bytes) / $opt(bitrate)}]
set opt(packet_time) $opt(airtime)
set opt(propagation_delay) [expr {$opt(hop_length) /
    $opt(propagation_speed)}]
set opt(slot_duration) [expr {$opt(airtime) + $opt(propagation_delay) +
    $opt(guard_time)}]
set opt(frame_duration) [expr {$opt(nn) * $opt(slot_duration)}]
for {set id 0} {$id < $opt(nn)} {incr id} {
    $mac($id) set frame_duration $opt(frame_duration)
}
set opt(sim_end) [expr {$opt(stoptime) +
    ($opt(n_hops) + 2) * $opt(frame_duration) + 0.5}]
puts "TDMA timing: technology=acoustic_chain modems=$opt(nn) tdma_slots=$opt(nn) hop_count=$opt(n_hops) header_bytes=$opt(header_bytes) packet_bytes=$opt(packet_bytes) airtime_s=$opt(airtime) propagation_s=$opt(propagation_delay) guard_s=$opt(guard_time) slot_s=$opt(slot_duration) frame_s=$opt(frame_duration)"

################################
# Addresses and routes         #
################################

$cbr($opt(sender_id),$opt(receiver_id)) set destAddr_ [$ipif($opt(receiver_id)) addr]
$cbr($opt(sender_id),$opt(receiver_id)) set destPort_ $portnum($opt(receiver_id),$opt(sender_id))

for {set src 0} {$src < $opt(nn)} {incr src} {
    for {set dst 0} {$dst < $opt(nn)} {incr dst} {
        if {$src != $dst} {
            $mll($src) addentry [$ipif($dst) addr] [$mac($dst) addr]
        }
    }
}

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

for {set id 0} {$id < $opt(nn)} {incr id} {
    $ns at 0.0 "$mac($id) start"
    $ns at $opt(sim_end) "$mac($id) stop"
}
$ns at $opt(starttime) "$cbr($opt(sender_id),$opt(receiver_id)) start"
$ns at $opt(stoptime)  "$cbr($opt(sender_id),$opt(receiver_id)) stop"

################################
# End-of-run metrics block     #
################################

proc finish {} {
    global ns opt cbr mac

    set sent     [$cbr($opt(sender_id),$opt(receiver_id)) getsentpkts]
    set received [$cbr($opt(receiver_id),$opt(sender_id)) getrecvpkts]

    puts "=== METRICS v2 ==="
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

puts "Starting acoustic equal-hop chain (v3)"
puts "Path has $opt(n_hops) hops, $opt(n_relays) relays, $opt(hop_length) m per hop"
$ns at [expr {$opt(sim_end) + 1.0}] "finish; $ns halt"
$ns run
