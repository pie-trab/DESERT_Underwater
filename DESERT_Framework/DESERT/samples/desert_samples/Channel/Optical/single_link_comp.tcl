#
# Simple single-link acoustic comparison case for DESERT.
#
# HOW THIS EXAMPLE WORKS
# ----------------------
# This simulation contains exactly two acoustic modems:
#
#   modem 0 (transmitter) -------------- modem 1 (receiver)
#
# Modem 0 generates CBR packets and modem 1 receives them over DESERT's
# standard underwater acoustic channel.  The stack is:
#
#   UW/CBR -> UW/UDP -> UW/StaticRouting -> UW/IP -> UW/MLL
#           -> UW/TDMA -> UW/PHYSICAL -> UnderwaterChannel
#
# TDMA gives the two modems separate slots, so this baseline does not depend
# on a collision-prone random-access MAC.  The script intentionally does not
# use WOSS, optical beam LUTs, acoustic LUTs, or any external lookup table.
#
# RUNNING
# -------
# Source the DESERT environment and run from this directory:
#
#   source <DESERT_build>/environment
#   ns single_link_comp.tcl
#
# The first seven command-line arguments are compatible with the optical
# sweep script:
#
#   ns single_link_comp.tcl \
#       n_relays cbr_period packet_size distance relay_gap depth stop_time \
#       rngstream attenuation_scale poisson_traffic
#
# `n_relays`, `relay_gap`, and `attenuation_scale` are accepted only so one
# Python experiment runner can invoke both simulations.  They have no meaning
# for this direct, single-hop acoustic link and are ignored by this file.
# `distance` is the direct modem separation in metres.
#
# All acoustic, timing, and traffic parameters can also be changed in the
# initialization section below.  The command-line values override the
# corresponding topology/traffic values when supplied.
#

################################
# User-changeable parameters    #
################################

# Topology and traffic.
set opt(nn)                 2         ;# number of acoustic modems
set opt(sender_id)          0         ;# CBR transmitter
set opt(receiver_id)        1         ;# CBR receiver
set opt(starttime)          0.1       ;# s: CBR start time
set opt(stoptime)           20.0      ;# s: CBR stop time
set opt(cbr_period)         2.0       ;# s: mean packet period
set opt(pktsize)            125       ;# byte: application payload
set opt(poisson_traffic)    0         ;# 0=periodic, 1=Poisson CBR
set opt(rngstream)          1         ;# DESERT RNG substream
set opt(distance)           20.0      ;# m: direct transmitter/receiver range
set opt(depth)              -10.0     ;# m: common modem depth

# The following compatibility values are not used by this single link.  They
# are kept so the optical/acoustic Python runner can pass one argument list to
# both Tcl simulations.
set opt(n_relays)           0
set opt(relay_gap)          1.0
set opt(attenuation_scale)  1.0

# Acoustic physical-layer parameters.
set opt(freq)               50000.0   ;# Hz: acoustic center frequency
set opt(bw)                 26000.0   ;# Hz: signal bandwidth
set opt(propagation_speed)  1500.0    ;# m/s: sound speed in water
set opt(bitrate)            20768.0   ;# bit/s: acoustic modem bit rate
set opt(txpower)            160.0     ;# dB re 1 uPa at 1 m: source level
set opt(acquisition_db)     15.0      ;# dB: PHY acquisition threshold
set opt(max_tx_range)       200.0     ;# m: PHY range cutoff
set opt(spreading)          2         ;# practical spreading coefficient
set opt(windspeed)          10.0      ;# m/s: environmental propagation input
set opt(shipping)           1         ;# shipping activity used by propagation

# TDMA timing.  The script enlarges the frame if a packet plus guard time
# would not fit in one slot.  This keeps packet-size sweeps safe.
set opt(frame_duration)     1.0       ;# s: complete two-slot TDMA frame
set opt(guard_time)         0.01      ;# s: guard time around a slot
set opt(auto_frame_duration) 1        ;# 1=derive a safe minimum frame

# Diagnostics and traces.
set opt(verbose)            1         ;# 1=print the final packet summary
set opt(debug)              0         ;# module debug output
set opt(trace_files)        0         ;# 1=write trace files beside script
set opt(trace_prefix)       "single_link_comp_acoustic"
set opt(maxinterval)        200.0     ;# s: interference history window

################################
# Optional command-line values  #
################################

if {$argc > 0} {
    if {$argc != 7 && $argc != 8 && $argc != 9 && $argc != 10} {
        puts "Usage: ns single_link_comp.tcl n_relays cbr_period packet_size distance relay_gap depth stop_time ?rngstream? ?attenuation_scale? ?poisson_traffic?"
        exit 1
    }
    set opt(n_relays)        [lindex $argv 0]
    set opt(cbr_period)      [lindex $argv 1]
    set opt(pktsize)         [lindex $argv 2]
    set opt(distance)        [lindex $argv 3]
    set opt(relay_gap)       [lindex $argv 4]
    set opt(depth)           [lindex $argv 5]
    set opt(stoptime)        [lindex $argv 6]
    if {$argc >= 8} {
        set opt(rngstream) [lindex $argv 7]
    }
    if {$argc >= 9} {
        set opt(attenuation_scale) [lindex $argv 8]
    }
    if {$argc == 10} {
        set opt(poisson_traffic) [lindex $argv 9]
    }
}

# A packet must fit in one assigned slot.  The additional 20% margin covers
# MAC/PHY headers and simulator event ordering.  Two modems share the frame.
set opt(packet_time) [expr {8.0 * $opt(pktsize) / $opt(bitrate)}]
set opt(min_frame_duration) [expr {2.0 * ($opt(packet_time) + $opt(guard_time)) * 1.20}]
if {$opt(auto_frame_duration) && $opt(frame_duration) < $opt(min_frame_duration)} {
    set opt(frame_duration) $opt(min_frame_duration)
}

################################
# DESERT library loading       #
################################

# These are the standard DESERT libraries used by the acoustic UW-TDMA
# sample.  No WOSS library and no LUT generator/reader is loaded.
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

# CBR controls application payload size and packet-generation process.
Module/UW/CBR set packetSize_     $opt(pktsize)
Module/UW/CBR set period_         $opt(cbr_period)
Module/UW/CBR set PoissonTraffic_ $opt(poisson_traffic)
Module/UW/CBR set debug_          $opt(debug)

# Two slots are enough because only the transmitter generates traffic.  The
# receiver still has its own slot, which keeps the setup symmetric and makes
# the timing comparable with the optical TDMA simulation.
Module/UW/TDMA set frame_duration $opt(frame_duration)
Module/UW/TDMA set debug_         $opt(debug)
Module/UW/TDMA set sea_trial_     0
Module/UW/TDMA set fair_mode      1
Module/UW/TDMA set guard_time     $opt(guard_time)
Module/UW/TDMA set tot_slots      $opt(nn)

# Standard underwater acoustic propagation.  These parameters represent a
# simple analytical water model; unlike WOSS, it does not use bathymetry,
# sound-speed profiles, or precomputed channel tables.
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

# Standard DESERT acoustic physical layer.  MaxTxRange_ is a hard range
# cutoff; the actual received power and packet decision still depend on the
# propagation model, source level, noise, and acquisition threshold.
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
# Node-construction procedure   #
################################

proc createAcousticNode {id} {
    global ns channel opt node cbr udp ipr ipif mll mac phy position portnum
    global data_mask propagation interf_data

    set node($id) [$ns create-M_Node $opt(tracefile) $opt(cltracefile)]

    # Each node needs an application endpoint for the other modem.  Only the
    # sender endpoint is started below; the receiver endpoint is a sink.
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

    # Connect the protocol stack from application down to physical layer.
    $node($id) setConnection $cbr($id,$other) $udp($id) 0
    set portnum($id,$other) [$udp($id) assignPort $cbr($id,$other)]
    $node($id) setConnection $udp($id)  $ipr($id)  1
    $node($id) setConnection $ipr($id)  $ipif($id) 1
    $node($id) setConnection $ipif($id) $mll($id)  1
    $node($id) setConnection $mll($id)  $mac($id)  1
    $node($id) setConnection $mac($id)  $phy($id)  1
    $node($id) addToChannel $channel $phy($id) 1

    # Use simple numeric IP and MAC addresses, as in DESERT's acoustic
    # examples.  The explicit slot number makes the two-node schedule clear.
    $ipif($id) addr [expr {$id + 1}]
    $mac($id) setMacAddr [expr {$id + 1}]
    $mac($id) setSlotNumber $id

    # Place the modems on the Y axis at the requested depth.
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
    $phy($id) setSpectralMask     $data_mask
    $phy($id) setInterference     $interf_data($id)
    $phy($id) setInterferenceModel "MEANPOWER"
}

################################
# Create and connect the nodes  #
################################

for {set id 0} {$id < $opt(nn)} {incr id} {
    createAcousticNode $id
}

# Configure the single application flow from modem 0 to modem 1.
$cbr($opt(sender_id),$opt(receiver_id)) set destAddr_ [$ipif($opt(receiver_id)) addr]
$cbr($opt(sender_id),$opt(receiver_id)) set destPort_ $portnum($opt(receiver_id),$opt(sender_id))

# Fill the link-layer address table and install direct IP routes in both
# directions.  The reverse endpoint is not started, but its route makes the
# node stack complete and lets the receiver-side CBR count packets normally.
for {set src 0} {$src < $opt(nn)} {incr src} {
    for {set dst 0} {$dst < $opt(nn)} {incr dst} {
        if {$src != $dst} {
            $mll($src) addentry [$ipif($dst) addr] [$mac($dst) addr]
            $ipr($src) addRoute [$ipif($dst) addr] [$ipif($dst) addr]
        }
    }
}

################################
# Start/stop schedule           #
################################

for {set id 0} {$id < $opt(nn)} {incr id} {
    $ns at 0.0 "$mac($id) start"
    $ns at [expr {$opt(stoptime) + $opt(frame_duration) + 0.5}] "$mac($id) stop"
}
$ns at $opt(starttime) "$cbr($opt(sender_id),$opt(receiver_id)) start"
$ns at $opt(stoptime)  "$cbr($opt(sender_id),$opt(receiver_id)) stop"

################################
# End-of-run diagnostics        #
################################

proc finish {} {
    global ns opt cbr

    set sent [$cbr($opt(sender_id),$opt(receiver_id)) getsentpkts]
    set received [$cbr($opt(receiver_id),$opt(sender_id)) getrecvpkts]
    set throughput [expr {$received * $opt(pktsize) * 8.0 / $opt(stoptime)}]

    if {$opt(verbose)} {
        puts "----------------------------------------"
        puts "Single-link acoustic simulation"
        puts "distance: $opt(distance) m, depth: $opt(depth) m"
        puts "bitrate: $opt(bitrate) bit/s, source level: $opt(txpower) dB re 1 uPa"
        puts "CBR period: $opt(cbr_period) s, packet size: $opt(pktsize) byte"
        puts "sent packets: $sent"
        puts "received packets: $received"
        puts "throughput bps: $throughput"
        puts "----------------------------------------"
    }

    $ns flush-trace
    close $opt(tracefile)
    close $opt(cltracefile)
}

################################
# Run the simulation            #
################################

puts "Starting single-link acoustic simulation"
puts "Direct modem separation: $opt(distance) m"
$ns at [expr {$opt(stoptime) + $opt(frame_duration) + 1.0}] "finish; $ns halt"
$ns run