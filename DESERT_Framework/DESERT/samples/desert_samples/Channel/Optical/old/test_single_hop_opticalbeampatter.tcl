#
# Four-modem optical relay with directional beam-pattern LUTs.
#
#   sender -> relay_rx <-> relay_tx -> receiver
#      0        1          2           3
#
# The relay is deliberately split into two modems.  Modem 1 points toward the
# sender and modem 2 points toward the receiver; their small separation is the
# relay_gap.  The sender application sends to node 3, while static routes force
# the packet through nodes 1 and 2.
#
# Run from this directory with:
#   ns test_single_hop_opticalbeampatter.tcl
#
# Optional arguments:
#   rngstream cbr_period packet_size hop_length relay_gap depth
#
# The filename keeps the spelling requested by the user (beampatter).

################################
# User-changeable parameters    #
################################
set opt(nn)                 4
set opt(starttime)          1.0       ;# s
set opt(stoptime)           20.0      ;# s
set opt(cbr_period)         0.1       ;# s
set opt(pktsize)            125       ;# byte
set opt(rngstream)          1
set opt(poisson_traffic)    0

# Nodes are placed along Y.  This keeps all three hops inside the default
# beam-pattern lobe (the default table has a non-zero factor at +/- PI/2).
set opt(hop_length)         10.0      ;# m: sender-relay_rx and relay_tx-receiver
set opt(relay_gap)          1.0       ;# m: distance between relay modems
set opt(depth)              -10.0     ;# m: common Z coordinate

# Optical PHY parameters.
set opt(freq)               10000000  ;# Hz
set opt(bw)                 100000    ;# Hz
set opt(bitrate)            1000000   ;# bit/s
set opt(txpower)            50.0
set opt(acq_threshold_db)   10.0      ;# dB
set opt(id)                 1.0e-9    ;# A
set opt(il)                 1.0e-6    ;# A
set opt(shunt_resistance)   1.49e9    ;# ohm
set opt(sensitivity)        0.26      ;# A/W
set opt(temperature)        293.15    ;# K
set opt(rx_area)            1.1e-6    ;# m^2
set opt(tx_area)            1.0e-5    ;# m^2

# Propagation and LUT parameters.  These are the default tables used by the
# repository's test_uwopticalbeampattern.tcl sample.  Paths are relative to
# this Optical directory; run ns from here or change them to absolute paths.
set opt(attenuation_c)      0.043     ;# fallback/nominal c, 1/m
set opt(theta)              1.0       ;# rad
set opt(noise_lut_path)     "../../dbs/optical_noise/LUT.txt"
set opt(attenuation_lut)    "../../dbs/optical_attenuation/lut_532nm/lut_532nm_CTD025.csv"
set opt(beam_lut_path)      "../../dbs/bluecomm/beam_pattern/beam5mbps.csv"
set opt(max_range_lut_path) "../../dbs/bluecomm/max_range/max_range5mbps.csv"

# The relay heads use opposite inclination values.  In this DESERT model
# inclination is an X-Z rotation; azimuth/yaw is not exposed, so the Y-axis
# placement is what keeps both relay hops valid with the default beam LUT.
set opt(inclination_sender)    -1.570796326794897
set opt(inclination_relay_rx)  -1.570796326794897
set opt(inclination_relay_tx)   1.570796326794897
set opt(inclination_receiver)   1.570796326794897

set opt(ack_mode)           "setNoAckMode"
set opt(maxinterval)        10.0
set opt(verbose)             1
set opt(debug)               0
set opt(trace_files)         0
set opt(trace_prefix)        "test_single_hop_opticalbeampatter"

################################
# Optional command-line sweep  #
################################
if {$argc > 0} {
    if {$argc != 6} {
        puts "Usage: ns test_single_hop_opticalbeampatter.tcl rngstream cbr_period packet_size hop_length relay_gap depth"
        exit 1
    }
    set opt(rngstream)  [lindex $argv 0]
    set opt(cbr_period) [lindex $argv 1]
    set opt(pktsize)    [lindex $argv 2]
    set opt(hop_length) [lindex $argv 3]
    set opt(relay_gap)  [lindex $argv 4]
    set opt(depth)      [lindex $argv 5]
}

################################
# DESERT library loading       #
################################
# UWOPTICALBEAMPATTERN provides the directional beam and max-range LUT logic.
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
load libuwopticalbeampattern.so

################################
# Simulator, RNG, and traces   #
################################
set ns [new Simulator]
$ns use-Miracle
global defaultRNG
for {set k 0} {$k < $opt(rngstream)} {incr k} {
    $defaultRNG next-substream
}

if {$opt(trace_files)} {
    set opt(tracefile)   [open "$opt(trace_prefix).tr" w]
    set opt(cltracefile) [open "$opt(trace_prefix).cltr" w]
} else {
    set opt(tracefile)   [open "/dev/null" w]
    set opt(cltracefile) [open "/dev/null" w]
}

################################
# Module and LUT configuration #
################################
Module/UW/CBR set packetSize_     $opt(pktsize)
Module/UW/CBR set period_         $opt(cbr_period)
Module/UW/CBR set PoissonTraffic_ $opt(poisson_traffic)
Module/UW/CBR set debug_          $opt(debug)

# Configure the beam-pattern PHY defaults before creating the four objects.
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

Module/UW/OPTICAL/Propagation set Ar_    $opt(rx_area)
Module/UW/OPTICAL/Propagation set At_    $opt(tx_area)
Module/UW/OPTICAL/Propagation set c_     $opt(attenuation_c)
Module/UW/OPTICAL/Propagation set theta_ $opt(theta)
Module/UW/OPTICAL/Propagation set debug_ $opt(debug)

# Directional propagation is required: do not call setOmnidirectional here.
# The attenuation LUT is loaded and setVariableC makes the path use its c
# values.  The beam-pattern object separately loads beam and max-range LUTs.
set propagation [new Module/UW/OPTICAL/Propagation]
$propagation setDirectional
$propagation setLUTFileName $opt(attenuation_lut)
$propagation setLUT
$propagation setVariableC

set channel [new Module/UW/Optical/Channel]
set data_mask [new MSpectralMask/Rect]
$data_mask setFreq      $opt(freq)
$data_mask setBandwidth $opt(bw)

Module/UW/CSMA_ALOHA set listen_time_  [expr 1.0e-12]
Module/UW/CSMA_ALOHA set wait_costant_ [expr 1.0e-12]

################################
# Create one beam-pattern node  #
################################
proc createNode {id} {
    global ns channel opt propagation data_mask
    global node cbr udp ipr ipif mll mac phy position portnum interf_data

    set node($id) [$ns create-M_Node $opt(tracefile) $opt(cltracefile)]
    for {set dst 0} {$dst < $opt(nn)} {incr dst} {
        set cbr($id,$dst) [new Module/UW/CBR]
    }
    set udp($id)  [new Module/UW/UDP]
    set ipr($id)  [new Module/UW/StaticRouting]
    set ipif($id) [new Module/UW/IP]
    set mll($id)  [new Module/UW/MLL]
    set mac($id)  [new Module/UW/CSMA_ALOHA]
    set phy($id)  [new Module/UW/UWOPTICALBEAMPATTERN]

    # Install the conventional seven-to-one DESERT stack.
    for {set dst 0} {$dst < $opt(nn)} {incr dst} {
        $node($id) addModule 7 $cbr($id,$dst) 1 "CBR"
    }
    $node($id) addModule 6 $udp($id)  1 "UDP"
    $node($id) addModule 5 $ipr($id)  1 "IPR"
    $node($id) addModule 4 $ipif($id) 1 "IPF"
    $node($id) addModule 3 $mll($id)  1 "MLL"
    $node($id) addModule 2 $mac($id)  1 "MAC"
    $node($id) addModule 1 $phy($id)  1 "PHY"

    for {set dst 0} {$dst < $opt(nn)} {incr dst} {
        $node($id) setConnection $cbr($id,$dst) $udp($id) 1
        set portnum($id,$dst) [$udp($id) assignPort $cbr($id,$dst)]
    }
    $node($id) setConnection $udp($id) $ipr($id) 1
    $node($id) setConnection $ipr($id) $ipif($id) 1
    $node($id) setConnection $ipif($id) $mll($id) 1
    $node($id) setConnection $mll($id) $mac($id) 1
    $node($id) setConnection $mac($id) $phy($id) 1
    $node($id) addToChannel $channel $phy($id) 1

    # Each beam-pattern PHY loads the ambient-light, beam, and max-range LUTs.
    $phy($id) setInterference [set interf_data($id) [new MInterference/MIV]]
    $interf_data($id) set maxinterval_ $opt(maxinterval)
    $interf_data($id) set debug_ $opt(debug)
    $phy($id) setPropagation $propagation
    $phy($id) setSpectralMask $data_mask
    $phy($id) setLUTFileName $opt(noise_lut_path)
    $phy($id) setLUTSeparator " "
    $phy($id) setBeamPatternPath $opt(beam_lut_path)
    $phy($id) setMaxRangePath $opt(max_range_lut_path)
    $phy($id) useLUT
    $phy($id) setVariableTemperature

    $ipif($id) addr [expr {$id + 1}]
    set position($id) [new Position/BM]
    $node($id) addPosition $position($id)
    $position($id) setX_ 0.0
    $position($id) setY_ [expr {$id == 0 ? 0.0 : ($id == 1 ? $opt(hop_length) : ($id == 2 ? $opt(hop_length) + $opt(relay_gap) : 2.0 * $opt(hop_length) + $opt(relay_gap)))}]
    $position($id) setZ_ $opt(depth)

    # Heading assignment: sender/right-facing, relay_rx/left-facing,
    # relay_tx/right-facing, receiver/left-facing.
    set angles [list $opt(inclination_sender) $opt(inclination_relay_rx) $opt(inclination_relay_tx) $opt(inclination_receiver)]
    $phy($id) setInclinationAngle [lindex $angles $id]
    $mac($id) $opt(ack_mode)
    $mac($id) initialize
}

################################
# Instantiate the four modems  #
################################
for {set id 0} {$id < $opt(nn)} {incr id} {
    createNode $id
}

################################
# Application and ARP setup    #
################################
# Only node 0 generates data.  Node 3's cbr(3,0) is the receiving counter.
$cbr(0,3) set destAddr_ [$ipif(3) addr]
$cbr(0,3) set destPort_ $portnum(3,0)
for {set src 0} {$src < $opt(nn)} {incr src} {
    for {set dst 0} {$dst < $opt(nn)} {incr dst} {
        if {$src != $dst} {
            $mll($src) addentry [$ipif($dst) addr] [$mac($dst) addr]
        }
    }
}

################################
# Force the three-hop relay path#
################################
set destination [$ipif(3) addr]
$ipr(0) addRoute $destination [$ipif(1) addr]
$ipr(1) addRoute $destination [$ipif(2) addr]
$ipr(2) addRoute $destination [$ipif(3) addr]
$ipr(3) addRoute $destination $destination

################################
# Run only the sender source    #
################################
$ns at $opt(starttime) "$cbr(0,3) start"
$ns at $opt(stoptime)  "$cbr(0,3) stop"

################################
# Results and shutdown         #
################################
proc finish {} {
    global ns opt cbr
    set sent [$cbr(0,3) getsentpkts]
    set received [$cbr(3,0) getrecvpkts]
    if {$opt(verbose)} {
        puts "----------------------------------------"
        puts "Directional single-flow optical relay"
        puts "path: sender -> relay_rx -> relay_tx -> receiver"
        puts "hop length: $opt(hop_length) m; relay gap: $opt(relay_gap) m"
        puts "sent packets: $sent"
        puts "received packets: $received"
        puts "----------------------------------------"
    }
    $ns flush-trace
    close $opt(tracefile)
    close $opt(cltracefile)
}

puts "Starting directional beam-pattern optical relay simulation"
$ns at [expr {$opt(stoptime) + 1.0}] "finish; $ns halt"
$ns run