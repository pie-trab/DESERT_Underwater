#
# Four-modem single-flow optical relay example for DESERT.
#
# Topology, from left to right on the Y axis:
#
#   sender  -->  relay_rx  <-->  relay_tx  -->  receiver
#      0          1              2             3
#
# The application runs only on node 0 and its destination is node 3.  Static
# routes force every packet through node 1 and then node 2.  Nodes 1 and 2
# form the close relay couple: relay_rx receives the packet and forwards it
# at IP level; relay_tx then transmits it toward the final receiver.
#
# This file intentionally uses the same simple optical model as the companion
# two_optical_modems.tcl example: fixed Lambert-Beer attenuation, no WOSS, and
# no LUT.  The standard UW/OPTICAL/PHY does not expose an azimuth/heading
# orientation command.  Therefore the opposite-facing relay heads are shown
# by their ordered geometry and separate PHYs; omnidirectional propagation is
# enabled so this example does not need a beam-pattern LUT.
#
# Example:
#   ns test_single_hop_optical.tcl
#   ns test_single_hop_optical.tcl 0 0.1 125 10 1 -10
#
# Command-line arguments, when supplied, are:
#   rngstream cbr_period packet_size hop_length relay_gap depth
#

################################
# User-changeable parameters    #
################################
set opt(nn)                 4         ;# sender, relay_rx, relay_tx, receiver

# Simulation and traffic parameters.
set opt(starttime)          1.0       ;# s: start of the sender application
set opt(stoptime)           20.0      ;# s: stop of the sender application
set opt(cbr_period)         0.1       ;# s: packet generation period
set opt(pktsize)            125       ;# byte: CBR payload size
set opt(rngstream)          1         ;# random-number substream
set opt(poisson_traffic)    0         ;# 0=periodic CBR, 1=Poisson CBR

# Geometry.  All nodes have the same depth and are separated along Y.
# Sender is at 0, relay_rx at hop_length, relay_tx one relay_gap later, and
# receiver one more hop_length later.  Change these values to tune each hop.
set opt(hop_length)         10.0      ;# m: sender-relay_rx and relay_tx-receiver
set opt(relay_gap)          1.0       ;# m: distance between the relay modems
set opt(depth)               -10.0     ;# m: common node depth (negative Z)

# Optical physical-layer parameters.
set opt(freq)               10000000  ;# Hz: center frequency of spectral mask
set opt(bw)                 100000    ;# Hz: optical signal bandwidth
set opt(bitrate)            1000000   ;# bit/s
set opt(txpower)            50.0      ;# optical transmit power used by PHY
set opt(acq_threshold_db)   10.0      ;# dB: receiver acquisition threshold
set opt(id)                 1.0e-9    ;# A: photodiode dark current
set opt(il)                 1.0e-6    ;# A: background photocurrent
set opt(shunt_resistance)   1.49e9    ;# ohm: receiver shunt resistance
set opt(sensitivity)        0.26      ;# A/W: photodiode sensitivity
set opt(temperature)        293.15    ;# K: fixed receiver temperature
set opt(rx_area)            1.1e-6    ;# m^2: receiver area
set opt(tx_area)            1.0e-5    ;# m^2: transmitter area
set opt(LUTpath)           "../../dbs/optical_noise/LUT.txt";#"dbs/optical_noise/ALOMEX_optical_E0/E0vsDEP_2015_11_04__12_34_41__035d45.470m_-004d54.920m_wl531.50_fileCTD020.txt";#"dbs/optical_noise/ALOMEX_optical_E0/E0vsDEP_2015_11_02__13_47_15__036d24.565m_001d40.534m_wl531.50_fileCTD001.txt";
set opt(atten_LUT)         "../../dbs/optical_attenuation/lut_532nm/lut_532nm_CTD025.csv"
set opt(beam_lut_path)     "../../dbs/bluecomm/beam_pattern/beam5mbps.csv";#"dbs/optical_noise/ALOMEX_optical_E0/E0vsDEP_2015_11_02__13_47_15__036d24.565m_001d40.534m_wl531.50_fileCTD001.txt";
set opt(range_lut_path)    "../../dbs/bluecomm/max_range/max_range5mbps.csv"
set opt(cbr_period) 0.1
set opt(pktsize)	125
set opt(rngstream)	1

# Fixed water/optical propagation parameters.
set opt(attenuation_c)      0.043     ;# 1/m: constant Lambert-Beer c
set opt(theta)              1.0       ;# rad: transmitter half-angle
set opt(omnidirectional)    1         ;# 1 avoids orientation/beam LUT needs

# MAC, diagnostics, and trace output.
set opt(ack_mode)           "setNoAckMode"
set opt(maxinterval)        10.0      ;# s: interference history interval
set opt(verbose)             1         ;# 1 prints a summary at the end
set opt(debug)               0         ;# 1 enables optical PHY/prop debug
set opt(trace_files)         0         ;# 1 writes trace files in this folder
set opt(trace_prefix)        "test_single_hop_optical"

################################
# Optional command-line sweep  #
################################
if {$argc > 0} {
    if {$argc != 6} {
        puts "Usage: ns test_single_hop_optical.tcl rngstream cbr_period packet_size hop_length relay_gap depth"
        exit 1
    }
    set opt(rngstream)  [lindex $argv 0]
    set opt(cbr_period) [lindex $argv 0]
    set opt(pktsize)    [lindex $argv 2]
    set opt(hop_length) [lindex $argv 3]
    set opt(relay_gap)  [lindex $argv 4]
    set opt(depth)      [lindex $argv 5]
}

################################
# DESERT library loading       #
################################
# The relay uses the ordinary IP/MLL/MAC forwarding path.  No WOSS library,
# ambient-light LUT, attenuation LUT, or beam-pattern LUT is loaded.
load libMiracle.so
load libMiracleBasicMovement.so
load libuwip.so
load libuwstaticrouting.so
load libmphy.so
load libmmac.so
load libuwcsmaaloha.so
load libuwmll.so
load libuwudp.so
load libuwcbr.so
load libuwoptical_propagation.so
load libuwem_channel.so
load libuwoptical_channel.so
load libuwoptical_phy.so

################################
# Simulator and random stream  #
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
# Module-wide default values  #
################################
Module/UW/CBR set packetSize_     $opt(pktsize)
Module/UW/CBR set period_         $opt(cbr_period)
Module/UW/CBR set PoissonTraffic_ $opt(poisson_traffic)
Module/UW/CBR set debug_          $opt(debug)

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

Module/UW/OPTICAL/Propagation set Ar_    $opt(rx_area)
Module/UW/OPTICAL/Propagation set At_    $opt(tx_area)
Module/UW/OPTICAL/Propagation set c_     $opt(attenuation_c)
Module/UW/OPTICAL/Propagation set theta_ $opt(theta)
Module/UW/OPTICAL/Propagation set debug_ $opt(debug)

# Use one shared optical propagation object for all four modem PHYs.  Fixed c
# means the attenuation coefficient is taken from opt(attenuation_c), so no
# depth-dependent table is needed.  Omnidirectional mode avoids beam-pattern
# files while retaining distance-dependent optical attenuation.
set propagation [new Module/UW/OPTICAL/Propagation]
if {$opt(omnidirectional)} {
    $propagation setOmnidirectional
} else {
    $propagation setDirectional
}
$propagation setFixedC

set channel [new Module/UW/Optical/Channel]

# Define the optical signal spectrum seen by every PHY.
set data_mask [new MSpectralMask/Rect]
$data_mask setFreq      $opt(freq)
$data_mask setBandwidth $opt(bw)

# Small CSMA timing values keep this compact relay example focused on routing.
Module/UW/CSMA_ALOHA set listen_time_  [expr 1.0e-12]
Module/UW/CSMA_ALOHA set wait_costant_ [expr 1.0e-12]

################################
# Node construction             #
################################
proc createNode {id} {
    global ns channel opt
    global node cbr udp ipr ipif mll mac phy position portnum interf_data
    global propagation data_mask

    set node($id) [$ns create-M_Node $opt(tracefile) $opt(cltracefile)]

    # Each node owns one CBR object per possible destination.  Only cbr(0,3)
    # is started below; the extra objects keep the stack pattern conventional.
    for {set dst 0} {$dst < $opt(nn)} {incr dst} {
        set cbr($id,$dst) [new Module/UW/CBR]
    }
    set udp($id)  [new Module/UW/UDP]
    set ipr($id)  [new Module/UW/StaticRouting]
    set ipif($id) [new Module/UW/IP]
    set mll($id)  [new Module/UW/MLL]
    set mac($id)  [new Module/UW/CSMA_ALOHA]
    set phy($id)  [new Module/UW/OPTICAL/PHY]

    # Stack order: CBR -> UDP -> static routing -> IP -> MLL -> MAC -> PHY.
    for {set dst 0} {$dst < $opt(nn)} {incr dst} {
        $node($id) addModule 7 $cbr($id,$dst) 1 "CBR"
    }
    $node($id) addModule 6 $udp($id)  1 "UDP"
    $node($id) addModule 5 $ipr($id)  1 "IPR"
    $node($id) addModule 4 $ipif($id) 1 "IPF"
    $node($id) addModule 3 $mll($id)  1 "MLL"
    $node($id) addModule 2 $mac($id)  1 "MAC"
    $node($id) addModule 1 $phy($id)  1 "PHY"

    # Connect the stack and allocate UDP ports.  A relay needs the normal IP
    # and forwarding modules, but it does not need a separate relay app.
    for {set dst 0} {$dst < $opt(nn)} {incr dst} {
        $node($id) setConnection $cbr($id,$dst) $udp($id) 1
        set portnum($id,$dst) [$udp($id) assignPort $cbr($id,$dst)]
    }
    $node($id) setConnection $udp($id)  $ipr($id)  1
    $node($id) setConnection $ipr($id)  $ipif($id) 1
    $node($id) setConnection $ipif($id) $mll($id)  1
    $node($id) setConnection $mll($id)  $mac($id)  1
    $node($id) setConnection $mac($id)  $phy($id)  1
    $node($id) addToChannel $channel $phy($id) 1

    # Attach the shared propagation and signal model to this modem.
    set interf_data($id) [new MInterference/MIV]
    $interf_data($id) set maxinterval_ $opt(maxinterval)
    $interf_data($id) set debug_ $opt(debug)
    $phy($id) setInterference $interf_data($id)
    $phy($id) setPropagation $propagation
    $phy($id) setSpectralMask $data_mask

    # IP addresses are 1, 2, 3, 4 for sender, relay_rx, relay_tx, receiver.
    $ipif($id) addr [expr {$id + 1}]

    # Put all heads at the same depth.  Node 1 and node 2 are physically close
    # and occupy separate positions, representing the two opposite relay heads.
    set position($id) [new Position/BM]
    $node($id) addPosition $position($id)
    $position($id) setX_ 0.0
    if {$id == 0} {
        set y 0.0
    } elseif {$id == 1} {
        set y $opt(hop_length)
    } elseif {$id == 2} {
        set y [expr {$opt(hop_length) + $opt(relay_gap)}]
    } else {
        set y [expr {2.0 * $opt(hop_length) + $opt(relay_gap)}]
    }
    $position($id) setY_ $y
    $position($id) setZ_ $opt(depth)

    # ACKs are disabled for this unidirectional demonstration.  Initialize MAC
    # after all common parameters and node-specific objects are configured.
    $mac($id) $opt(ack_mode)
    $mac($id) initialize
}

################################
# Create sender, relay, sink    #
################################
for {set id 0} {$id < $opt(nn)} {incr id} {
    createNode $id
}

################################
# Configure application flow    #
################################
# The CBR packet keeps destination IP 4 end-to-end.  Static routing below
# chooses the next MAC hop; the IP destination is not rewritten at relays.
$cbr(0,3) set destAddr_ [$ipif(3) addr]
$cbr(0,3) set destPort_ $portnum(3,0)

################################
# Fill MLL neighbor tables     #
################################
# Populate all entries to match the style used by the DESERT samples.  The
# static routes below decide which entry is actually used on each hop.
for {set src 0} {$src < $opt(nn)} {incr src} {
    for {set dst 0} {$dst < $opt(nn)} {incr dst} {
        if {$src != $dst} {
            $mll($src) addentry [$ipif($dst) addr] [$mac($dst) addr]
        }
    }
}

################################
# Install the forced relay path #
################################
# addRoute takes (final destination IP, next-hop IP).  These four entries
# implement: node0 -> node1 -> node2 -> node3.  Node 3's self-route delivers
# the packet locally when it reaches the final destination.
set destination [$ipif(3) addr]
$ipr(0) addRoute $destination [$ipif(1) addr]
$ipr(1) addRoute $destination [$ipif(2) addr]
$ipr(2) addRoute $destination [$ipif(3) addr]
$ipr(3) addRoute $destination $destination

################################
# Start and stop only one flow #
################################
# No CBR source is started on either relay.  Forwarding is performed by their
# IP/MLL/MAC stack after reception from the preceding hop.
$ns at $opt(starttime) "$cbr(0,3) start"
$ns at $opt(stoptime)  "$cbr(0,3) stop"

################################
# End-of-run summary           #
################################
proc finish {} {
    global ns opt cbr
    set sent [$cbr(0,3) getsentpkts]
    set received [$cbr(3,0) getrecvpkts]
    if {$opt(verbose)} {
        puts "----------------------------------------"
        puts "Single-flow optical relay simulation"
        puts "hop length: $opt(hop_length) m"
        puts "relay gap: $opt(relay_gap) m"
        puts "depth: $opt(depth) m"
        puts "path: sender -> relay_rx -> relay_tx -> receiver"
        puts "sent packets: $sent"
        puts "received packets: $received"
        puts "----------------------------------------"
    }
    $ns flush-trace
    close $opt(tracefile)
    close $opt(cltracefile)
}

################################
# Run the simulation           #
################################
puts "Starting single-flow optical relay simulation"
$ns at [expr {$opt(stoptime) + 1.0}] "finish; $ns halt"
$ns run
