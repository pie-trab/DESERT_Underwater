# Copyright (c) 2026 Regents of the SIGNET lab, University of Padova.
# All rights reserved.
#
# End-to-end LumaX DESERT-stack loopback test.
#
# Default use:
#   ns test_uwlumax_stack_loopback.tcl
#
# Optional arguments:
#   ns test_uwlumax_stack_loopback.tcl ?port? ?start? ?stop? ?traffic_period? ?pkt_size? ?UDP|TCP?
#
# The launcher starts two DESERT instances:
#   node 2: receive-only LumaX socket server
#   node 1: CBR sender through UDP/IP/MLL/CSMA_ALOHA/UWAL/LumaX
#
# This keeps the same real modem driver path used by the field sample, but
# connects the two driver sockets locally on 127.0.0.1 so no modem is needed.

set script_path [file normalize [info script]]
set script_dir [file dirname $script_path]
cd $script_dir

proc printLauncherUsage {} {
    puts "Usage:"
    puts "  ns test_uwlumax_stack_loopback.tcl ?port? ?start? ?stop? ?traffic_period? ?pkt_size? ?UDP|TCP?"
    puts ""
    puts "Defaults:"
    puts "  port=5555 start=5 stop=25 traffic_period=5 pkt_size=16 protocol=UDP"
}

proc readStatsFile {filename array_name} {
    upvar $array_name stats

    if {![file exists $filename]} {
        return 0
    }

    set fd [open $filename r]
    while {[gets $fd line] >= 0} {
        set fields [split $line]
        if {[llength $fields] >= 2} {
            set stats([lindex $fields 0]) [lindex $fields 1]
        }
    }
    close $fd

    return 1
}

proc runLauncher {} {
    global argc argv script_dir script_path

    set opt(port)     5555
    set opt(start)    5
    set opt(stop)     25
    set opt(traffic)  5
    set opt(pktsize)  16
    set opt(proto)    "UDP"
    set opt(bitrate)  0
    set opt(overhead) 0
    set opt(prefix)   "uwlumax_stack_loopback"

    if {$argc > 6} {
        printLauncherUsage
        exit 1
    }

    if {$argc >= 1} { set opt(port)    [lindex $argv 0] }
    if {$argc >= 2} { set opt(start)   [lindex $argv 1] }
    if {$argc >= 3} { set opt(stop)    [lindex $argv 2] }
    if {$argc >= 4} { set opt(traffic) [lindex $argv 3] }
    if {$argc >= 5} { set opt(pktsize) [lindex $argv 4] }
    if {$argc >= 6} { set opt(proto)   [string toupper [lindex $argv 5]] }

    if {$opt(proto) != "UDP" && $opt(proto) != "TCP"} {
        puts "Invalid protocol: $opt(proto)"
        printLauncherUsage
        exit 1
    }

    set ns_bin [info nameofexecutable]
    if {$ns_bin == ""} {
        set ns_bin "ns"
    }

    set script $script_path
    set receiver_stats "${opt(prefix)}_node_2.stats"
    set sender_stats   "${opt(prefix)}_node_1.stats"
    set receiver_log   "${opt(prefix)}_receiver.out"
    set sender_log     "${opt(prefix)}_sender.out"

    foreach f [list $receiver_stats $sender_stats $receiver_log $sender_log] {
        catch {file delete -force $f}
    }

    puts "Starting LumaX stack receiver on 127.0.0.1:${opt(port)} (${opt(proto)})"
    set receiver_pid [exec $ns_bin $script NODE 2 1 $opt(start) $opt(stop) 0 127.0.0.1 $opt(port) $opt(pktsize) $opt(proto) $opt(bitrate) $opt(overhead) SERVER $opt(prefix) >& $receiver_log &]

    after 1000

    puts "Starting LumaX stack sender toward node 2"
    set sender_rc [catch {
        exec $ns_bin $script NODE 1 2 $opt(start) $opt(stop) $opt(traffic) 127.0.0.1 $opt(port) $opt(pktsize) $opt(proto) $opt(bitrate) $opt(overhead) CLIENT $opt(prefix) >& $sender_log
    } sender_result]

    after 3000

    array set tx_stats {}
    array set rx_stats {}
    set have_tx [readStatsFile $sender_stats tx_stats]
    set have_rx [readStatsFile $receiver_stats rx_stats]

    puts "---------------------------------------------------------------------"
    puts "LumaX DESERT-stack loopback summary"
    puts "sender log        : $sender_log"
    puts "receiver log      : $receiver_log"
    puts "sender stats      : $sender_stats"
    puts "receiver stats    : $receiver_stats"

    if {$sender_rc != 0} {
        puts "sender status     : ERROR"
        puts "sender result     : $sender_result"
    }

    if {!$have_tx || !$have_rx} {
        puts "test result       : FAIL"
        puts "reason            : missing sender or receiver stats file"
        catch {exec kill [lindex $receiver_pid 0]}
        exit 1
    }

    set sent_pkts $tx_stats(sent_pkts)
    set recv_pkts $rx_stats(recv_pkts)
    set pdr 0
    if {$sent_pkts > 0} {
        set pdr [expr {100.0 * $recv_pkts / $sent_pkts}]
    }

    puts "sent packets      : $sent_pkts"
    puts "received packets  : $recv_pkts"
    puts "packet delivery   : [format %.2f $pdr] %"

    if {$sender_rc == 0 && $sent_pkts > 0 && $recv_pkts > 0} {
        puts "test result       : PASS"
        exit 0
    }

    puts "test result       : FAIL"
    exit 1
}

if {$argc == 0 || [lindex $argv 0] != "NODE"} {
    runLauncher
    exit
}

if {$argc != 14} {
    puts "Internal node mode usage:"
    puts "  ns test_uwlumax_stack_loopback.tcl NODE node_id dest_id start stop traffic ip port pkt_size UDP|TCP bitrate tx_overhead CLIENT|SERVER prefix"
    exit 1
}

set opt(node)        [lindex $argv 1]
set opt(dest)        [lindex $argv 2]
set opt(start)       [lindex $argv 3]
set opt(stop)        [lindex $argv 4]
set opt(traffic)     [lindex $argv 5]
set opt(ip)          [lindex $argv 6]
set opt(port)        [lindex $argv 7]
set opt(pktsize)     [lindex $argv 8]
set opt(conn_proto)  [string toupper [lindex $argv 9]]
set opt(bitrate)     [lindex $argv 10]
set opt(tx_overhead) [lindex $argv 11]
set opt(conn_role)   [string toupper [lindex $argv 12]]
set opt(prefix)      [lindex $argv 13]

if {$opt(conn_proto) != "UDP" && $opt(conn_proto) != "TCP"} {
    puts "Invalid connector protocol: $opt(conn_proto)"
    exit 1
}

if {$opt(conn_role) != "CLIENT" && $opt(conn_role) != "SERVER"} {
    puts "Invalid connector role: $opt(conn_role)"
    exit 1
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
$ns use-scheduler RealTime

##################
# Tcl variables  #
##################
if {$opt(conn_role) == "SERVER"} {
    set modem_address "$opt(port)"
} else {
    set modem_address "${opt(ip)}:${opt(port)}"
}

set time_stop [expr {$opt(stop) + 5}]
set tf_name "${opt(prefix)}_node_${opt(node)}.tr"
set stats_name "${opt(prefix)}_node_${opt(node)}.stats"

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
    $modem_ setLogSuffix "_${opt(prefix)}_node_${opt(node)}_log"
    $modem_ setLogLevel DBG

    if {$opt(conn_proto) == "UDP"} {
        $modem_ setUDP
    } else {
        $modem_ setTCP
    }

    if {$opt(conn_role) == "SERVER"} {
        $modem_ setServer
    }

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
    global ns tf tf_name stats_name opt app_

    set sent_pkts [$app_ getsentpkts]
    set recv_pkts [$app_ getrecvpkts]
    set throughput [$app_ getthr]

    puts "---------------------------------------------------------------------"
    puts "LumaX node summary"
    puts "node             : $opt(node)"
    puts "role             : $opt(conn_role)"
    puts "sent packets     : $sent_pkts"
    puts "received packets : $recv_pkts"
    puts "throughput       : $throughput"
    puts "tracefile        : $tf_name"

    set sf [open $stats_name w]
    puts $sf "node $opt(node)"
    puts $sf "role $opt(conn_role)"
    puts $sf "sent_pkts $sent_pkts"
    puts $sf "recv_pkts $recv_pkts"
    puts $sf "throughput $throughput"
    puts $sf "tracefile $tf_name"
    close $sf

    $ns flush-trace
    close $tf
}

##################
# Run simulation #
##################
$ns at $time_stop "finish; $ns halt"
$ns run
