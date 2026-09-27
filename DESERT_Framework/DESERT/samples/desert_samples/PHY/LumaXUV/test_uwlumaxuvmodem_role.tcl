#!/usr/bin/env ns

# Role-based LumaX-UV multihop test for three separate PCs.
#
# Run this same file once on each PC with a different role:
#
#     sender (node 0, IP 1) -> relay (node 1, IP 2) -> receiver (node 2, IP 3)
#
# The sender and receiver expose TCP application sockets. The relay is a
# transparent forwarding node and does not expose an application socket.

# Default simulation parameters.
set opt(start) 1.0
set opt(stop) 100.0
set opt(app_period) 0.1
set opt(app_port) 44440
set opt(trace_files) 0
set opt(tracefilename) "uwlumaxuvmodem_role.tr"

# Command-line arguments: role, stop time, modem data endpoint,
# modem configuration address, and application TCP port.
if {$argc != 5} {
	puts "The script needs 5 input arguments:"
	puts "1 - Role: sender, relay, or receiver"
	puts "2 - Stop time"
	puts "3 - Local modem data endpoint (IP:port)"
	puts "4 - Modem configuration endpoint"
	puts "5 - Application TCP port (use 0 for relay)"
	puts "The sender is node 0/IP 1; the relay is node 1/IP 2;"
	puts "the receiver is node 2/IP 3."
	puts "Example sender:"
	puts "ns $argv0 sender 100 192.168.102.50:55555 192.168.102.101 44440"
	puts "Example relay:"
	puts "ns $argv0 relay 100 192.168.102.51:55555 192.168.102.102 0"
	puts "Example receiver:"
	puts "ns $argv0 receiver 100 192.168.102.52:55555 192.168.102.103 44442"
	exit 1
}

set opt(role) [lindex $argv 0]
set opt(stop) [lindex $argv 1]
set opt(data_address) [lindex $argv 2]
set opt(modem_address) [lindex $argv 3]
set opt(app_port) [lindex $argv 4]
set opt(time_stop) [expr {$opt(stop) + 5.0}]

if {$opt(role) eq "sender"} {
	set opt(node) 0
	set opt(ip_address) 1
	set opt(destination_ip) 3
	set opt(next_hop_ip) 2
} elseif {$opt(role) eq "relay"} {
	set opt(node) 1
	set opt(ip_address) 2
} elseif {$opt(role) eq "receiver"} {
	set opt(node) 2
	set opt(ip_address) 3
	set opt(destination_ip) 1
	set opt(next_hop_ip) 2
} else {
	puts "Invalid role '$opt(role)'. Use sender, relay, or receiver."
	exit 1
}

# Load the simulator and DESERT modules.
load libMiracle.so
load libmphy.so
load libuwip.so
load libuwmll.so
load libuwstaticrouting.so
load libuwudp.so
load libuwapplication.so
load libpackeruwapplication.so
load libuwaloha.so
load libuwcsmaaloha.so
load libuwal.so
load libpackeruwip.so
load libpackercommon.so
load libpackermac.so
load libpackeruwudp.so
load libuwphy_clmsgs.so
load libuwconnector.so
load libuwmodem.so
load libuwlumaxuvmodem.so
load libuwmmac_clmsgs.so

# Create the real-time simulator.
set ns [new Simulator]
$ns use-Miracle
$ns use-scheduler RealTime

# Initialize random numbers and tracing.
global defaultRNG
$defaultRNG next-substream
if {$opt(trace_files)} {
	set opt(tracefile) [open $opt(tracefilename) w]
} else {
	set opt(tracefile) [open "/dev/null" w]
}
$ns trace-all $opt(tracefile)

# Configure the adaptation layer and packet fields.
Module/UW/AL set Dbit 0
Module/UW/AL set PSDU 2048
Module/UW/AL set debug_ 0

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

UW/UDP/Packer set SPort_Bits 8
UW/UDP/Packer set DPort_Bits 8
UW/UDP/Packer set debug_ 0

UW/APP/uwApplication/Packer set SN_FIELD_ 0
UW/APP/uwApplication/Packer set RFFT_FIELD_ 0
UW/APP/uwApplication/Packer set RFFTVALID_FIELD_ 0
UW/APP/uwApplication/Packer set PRIORITY_FIELD_ 0
UW/APP/uwApplication/Packer set PAYLOADMSG_FIELD_SIZE_ 64
UW/APP/uwApplication/Packer set debug_ 0

# Configure application, MAC, and LumaXUV modules.
Module/UW/UDP set debug_ 0
Module/UW/APPLICATION set period_ $opt(app_period)
Module/UW/APPLICATION set Socket_Port_ $opt(app_port)
Module/UW/APPLICATION set PoissonTraffic_ 0
Module/UW/APPLICATION set drop_out_of_order_ 0
Module/UW/APPLICATION set sea_trial_ 1

Module/UW/UwModem/LumaXUV set debug_ 0
Module/UW/UwModem/LumaXUV set buffer_size 2048
Module/UW/UwModem/LumaXUV set max_read_size 2048

# Build the single node represented by this process.
proc createNode { } {
    set node [$ns create-M_Node]
    set app [new Module/UW/APPLICATION]
    set udp [new Module/UW/UDP]
    set routing [new Module/UW/StaticRouting]
    set ipif [new Module/UW/IP]
    set mll [new Module/UW/MLL]
    set mac [new Module/UW/CSMA_ALOHA]
    set uwal [new Module/UW/AL]
    set modem [new Module/UW/UwModem/LumaXUV]
    
    $node addModule 8 $app 1 "UWA"
    $node addModule 7 $udp 1 "UDP"
    $node addModule 6 $routing 1 "IPR"
    $node addModule 5 $ipif 1 "IPIF"
    $node addModule 4 $mll 1 "MLL"
    $node addModule 3 $mac 1 "ALOHA"
    $node addModule 2 $uwal 1 "UWAL"
    $node addModule 1 $modem 1 "LumaXUV"
    
    $node setConnection $app $udp trace
    $node setConnection $udp $routing trace
    $node setConnection $routing $ipif trace
    $node setConnection $ipif $mll trace
    $node setConnection $mll $mac trace
    $node setConnection $mac $uwal trace
    $node setConnection $uwal $modem trace
    
    # Configure this PC's modem and identity.
    $ipif addr $opt(ip_address)
    $mac setMacAddr $opt(ip_address)
    $modem set ID_ $opt(node)
    $modem setLocalAddress $opt(data_address)
    $modem setModemAddress $opt(modem_address)
    $modem setLogLevel DBG
    $modem start_state 1
    $app set node_ID_ $opt(node)
    set app_port [$udp assignPort $app]
    
    # Only sender and receiver accept external netcat connections.
    if {$opt(role) eq "sender" || $opt(role) eq "receiver"} {
        $app setSocketProtocol "TCP"
    }
    
    # Serialize the complete packet through the modem driver.
    set packer [new UW/AL/Packer]
    $packer addPacker [new NS2/COMMON/Packer]
    $packer addPacker [new NS2/MAC/Packer]
    $packer addPacker [new UW/IP/Packer]
    $packer addPacker [new UW/UDP/Packer]
    $packer addPacker [new UW/APP/uwApplication/Packer]
    $uwal linkPacker $packer
    $uwal set nodeID $opt(node)
    
    $mac setNoAckMode
    $mac initialize
    $routing enableLog
}

createNode

# Add the other two nodes to the MLL table. Their MAC addresses equal their
# one-based IP addresses, as in the three-process modem examples.
for {set peer 1} {$peer <= 3} {incr peer} {
	if {$peer != $opt(ip_address)} {
		$mll addentry $peer $peer
	}
}

# Configure the final destination and next-hop route for this role.
if {$opt(role) eq "sender" || $opt(role) eq "receiver"} {
	$app set destAddr_ $opt(destination_ip)
	$app set destPort_ 1
	$routing addRoute $opt(destination_ip) $opt(next_hop_ip)
} else {
	$routing addRoute 1 1
	$routing addRoute 3 3
}

# Start the modem first, then the application endpoints.
$ns at 0 "$modem start"
if {$opt(role) eq "sender" || $opt(role) eq "receiver"} {
	$ns at $opt(start) "$app start"
	$ns at $opt(stop) "$app stop"
}
$ns at $opt(time_stop) "$modem stop"

proc finish {} {
	global ns opt app
	puts "$opt(role) sent: [$app getsentpkts]"
	puts "$opt(role) received: [$app getrecvpkts]"
	$ns flush-trace
	close $opt(tracefile)
}

$ns at $opt(time_stop) "finish; $ns halt"
$ns run
