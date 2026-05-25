# Copyright (c) 2026 Regents of the SIGNET lab, University of Padova.
# All rights reserved.
#
# Real-modem sample for the LumaX transparent socket driver.
#
# Run one instance per modem/node. For example, on two PCs:
#
#   PC/modem 1:
#     ns test_uwlumax_application.tcl 1 2 5 120 15 192.168.1.101 5555 16 UDP
#
#   PC/modem 2:
#     ns test_uwlumax_application.tcl 2 1 5 120 0  192.168.1.102 5555 16 UDP


set opt(node)        1
set opt(dest)        2
set opt(start)       5
set opt(stop)        120
set opt(traffic)     15
set opt(ip)          "192.168.1.101"
set opt(port)        5555
set opt(pktsize)     16
set opt(bitrate)     0
set opt(tx_overhead) 0

proc printUsage {} {
    puts "Usage:"
    puts "  ns test_uwlumax_application.tcl node_id dest_id start stop traffic_period modem_ip modem_port pkt_size ?UDP|TCP? ?bitrate_bps? ?tx_overhead_s? ?CLIENT|SERVER?"
    puts ""
    puts "Arguments:"
    puts "  node_id        DESERT node/MAC/IP address of this node"
    puts "  dest_id        DESERT destination node address"
    puts "  start          application start time in seconds"
    puts "  stop           application stop time in seconds"
    puts "  traffic_period CBR packet period in seconds; use 0 for receive-only"
    puts "  modem_ip       IP address of the local LumaX modem"
    puts "  modem_port     socket port exposed by the local LumaX modem"
    puts "  pkt_size       CBR payload size in bytes"
    puts "  bitrate_bps    optional TX-duration estimate, default 0/unknown"
    puts "  tx_overhead_s  optional fixed TX-duration overhead, default 0"
}

if {$argc < 8 || $argc > 12} {
    printUsage
    exit
}

set opt(node)    [lindex $argv 0]
set opt(dest)    [lindex $argv 1]
set opt(start)   [lindex $argv 2]
set opt(stop)    [lindex $argv 3]
set opt(traffic) [lindex $argv 4]
set opt(ip)      [lindex $argv 5]
set opt(port)    [lindex $argv 6]
set opt(pktsize) [lindex $argv 7]

if {$argc >= 10} {
    set opt(bitrate) [lindex $argv 9]
}
if {$argc >= 11} {
    set opt(tx_overhead) [lindex $argv 10]
}

#####################
# Library Loading   #
#####################
load libMiracle.so
load libmphy.so
load libmmac.so
load libuwip.so
load libuwmll.so
load libuwstaticrouting.so
load libuwudp.so
load libuwcbr.so
load libuwaloha.so
load libuwcsmaaloha.so
load libuwal.so
load libpackeruwip.so
load libpackercommon.so
load libpackermac.so
load libpackeruwudp.so
load libpackeruwcbr.so
load libuwphy_clmsgs.so
load libuwconnector.so
load libuwmodem.so
load libuwlumaxmodem.so
load libuwmmac_clmsgs.so

#############################
# NS-Miracle initialization #
#############################
set ns [new Simulator]
$ns use-Miracle

# Required when the PHY talks to real hardware.
$ns use-scheduler RealTime

##################
# Tcl variables  #
##################
set modem_address "${opt(ip)}:${opt(port)}"

set time_stop [expr $opt(stop) + 5]
set tf_name "uwlumax_node_${opt(node)}.tr"

set tf [open $tf_name w]
$ns trace-all $tf

#########################
# Module Configuration  #
#########################
Module/UW/AL set Dbit 0
Module/UW/AL set PSDU 64
Module/UW/AL set debug_ 0
Module/UW/AL set interframe_period 0.e1
Module/UW/AL set frame_set_validity 0

UW/AL/Packer set SRC_ID_Bits 8
UW/AL/Packer set PKT_ID_Bits 8
UW/AL/Packer set FRAME_OFFSET_Bits 15
UW/AL/Packer set M_BIT_Bits 1
UW/AL/Packer set DUMMY_CONTENT_Bits 0
UW/AL/Packer set debug_ 0

NS2/COMMON/Packer set PTYPE_Bits 8
NS2/COMMON/Packer set SIZE_Bits 8
NS2/COMMON/Packer set UID_Bits 8
NS2/COMMON/Packer set ERROR_Bits 0
NS2/COMMON/Packer set TIMESTAMP_Bits 8
NS2/COMMON/Packer set PREV_HOP_Bits 8
NS2/COMMON/Packer set NEXT_HOP_Bits 8
NS2/COMMON/Packer set ADDR_TYPE_Bits 0
NS2/COMMON/Packer set LAST_HOP_Bits 0
NS2/COMMON/Packer set TXTIME_Bits 0
NS2/COMMON/Packer set debug_ 0

UW/IP/Packer set SAddr_Bits 8
UW/IP/Packer set DAddr_Bits 8
UW/IP/Packer set debug_ 0

NS2/MAC/Packer set Ftype_Bits 0
NS2/MAC/Packer set SRC_Bits 8
NS2/MAC/Packer set DST_Bits 8
NS2/MAC/Packer set Htype_Bits 0
NS2/MAC/Packer set TXtime_Bits 0
NS2/MAC/Packer set SStime_Bits 0
NS2/MAC/Packer set Padding_Bits 0
NS2/MAC/Packer set debug_ 0

UW/UDP/Packer set SPort_Bits 2
UW/UDP/Packer set DPort_Bits 2
UW/UDP/Packer set debug_ 0

UW/CBR/Packer set SN_bits 32
UW/CBR/Packer set RFFT_bits 0
UW/CBR/Packer set RFFT_VALID_bits 0
UW/CBR/Packer set debug_ 0

Module/UW/CBR set packetSize_ $opt(pktsize)
Module/UW/CBR set period_ $opt(traffic)
Module/UW/CBR set PoissonTraffic_ 0
Module/UW/CBR set debug_ 0

Module/UW/UwModem/LumaX set debug_ 1
Module/UW/UwModem/LumaX set buffer_size 4096
Module/UW/UwModem/LumaX set max_read_size 4096
Module/UW/UwModem/LumaX set bitrate $opt(bitrate)
Module/UW/UwModem/LumaX set tx_overhead $opt(tx_overhead)

################################
# Procedure(s) to create nodes #
################################
proc createNode {} {
    global ns opt modem_address
    global node_ app_ transport_ port_ routing_ ipif_ mac_ modem_ mll_ uwal_

    set node_ [$ns create-M_Node]

    set app_       [new Module/UW/CBR]
    set transport_ [new Module/UW/UDP]
    set routing_   [new Module/UW/StaticRouting]
    set ipif_      [new Module/UW/IP]
    set mll_       [new Module/UW/MLL]
    set mac_       [new Module/UW/CSMA_ALOHA]
    set uwal_      [new Module/UW/AL]
    set modem_     [new Module/UW/UwModem/LumaX]

    $node_ addModule 8 $app_       1 "CBR"
    $node_ addModule 7 $transport_ 1 "UDP"
    $node_ addModule 6 $routing_   1 "IPR"
    $node_ addModule 5 $ipif_      1 "IPIF"
    $node_ addModule 4 $mll_       1 "MLL"
    $node_ addModule 3 $mac_       1 "ALOHA"
    $node_ addModule 2 $uwal_      1 "UWAL"
    $node_ addModule 1 $modem_     1 "LUMAX"

    $node_ setConnection $app_       $transport_ trace
    $node_ setConnection $transport_ $routing_   trace
    $node_ setConnection $routing_   $ipif_      trace
    $node_ setConnection $ipif_      $mll_       trace
    $node_ setConnection $mll_       $mac_       trace
    $node_ setConnection $mac_       $uwal_      trace
    $node_ setConnection $uwal_      $modem_     trace

    set port_ [$transport_ assignPort $app_]
    $ipif_ addr $opt(node)
    $mac_ setMacAddr $opt(node)
    $modem_ set ID_ $opt(node)
    $modem_ setModemAddress $modem_address
    $modem_ setLogLevel DBG

    $modem_ setUDP

    set packer_ [new UW/AL/Packer]
    set packer_payload0 [new NS2/COMMON/Packer]
    set packer_payload1 [new UW/IP/Packer]
    set packer_payload2 [new NS2/MAC/Packer]
    set packer_payload3 [new UW/UDP/Packer]
    set packer_payload4 [new UW/CBR/Packer]

    $packer_ addPacker $packer_payload0
    $packer_ addPacker $packer_payload1
    $packer_ addPacker $packer_payload2
    $packer_ addPacker $packer_payload3
    $packer_ addPacker $packer_payload4

    $uwal_ linkPacker $packer_
    $uwal_ set nodeID $opt(node)

    $mac_ setNoAckMode
    $mac_ initialize
}

#################
# Node Creation #
#################
createNode

################################
# Inter-node module connection #
################################
$app_ set destAddr_ $opt(dest)
$app_ set destPort_ 1

$routing_ addRoute $opt(dest) $opt(dest)
$mll_ addentry $opt(dest) $opt(dest)

#####################
# Start/Stop Timers #
#####################
$ns at 0 "$modem_ start"

if {$opt(traffic) != 0} {
    $ns at $opt(start) "$app_ start"
    $ns at $opt(stop) "$app_ stop"
}

$ns at $time_stop "$modem_ stop"

###################
# Final Procedure #
###################
proc finish {} {
    global ns tf tf_name

    puts "done!"
    puts "tracefile: $tf_name"

    $ns flush-trace
    close $tf
}

##################
# Run simulation #
##################
$ns at $time_stop "finish; $ns halt"
$ns run
