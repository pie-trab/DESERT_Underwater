#
# Minimal two-node underwater optical modem example for DESERT.
#
# The two nodes are aligned on the X axis.  Their horizontal separation is
# controlled by opt(range), or by the fourth command-line argument.  The
# UWOPTICALBEAMPATTERN PHY is used at both ends, with fixed Lambert-Beer
# attenuation and BlueComm beam-pattern tables.  This example deliberately
# does not load WOSS or an attenuation LUT.
#
# Example:
#   ns two_optical_modems.tcl
#   ns two_optical_modems.tcl 0 0.1 125 20 -10
#
# Command-line arguments, when supplied, are:
#   rngstream cbr_period packet_size range depth
#

################################
# User-changeable parameters    #
################################
# Keep the topology at two nodes: one optical modem at each end of the link.
set opt(nn)                 2

# Simulation and traffic parameters.
set opt(starttime)          1.0       ;# s: start of both CBR sources
set opt(stoptime)           20.0      ;# s: stop time of both CBR sources
set opt(cbr_period)         0.1       ;# s: packet generation period
set opt(pktsize)            125       ;# byte: CBR payload size
set opt(rngstream)          1         ;# random-number substream
set opt(poisson_traffic)    0         ;# 0=periodic CBR, 1=Poisson CBR

# Link geometry.  Node 0 is at (0, 0, depth), node 1 at (0, range, depth).
set opt(range)              20.0      ;# m: distance between the modems
set opt(depth)              -10.0     ;# m: common node depth (negative Z)

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

# Fixed water/optical propagation parameters.
# c is the attenuation coefficient in 1/m.  Change it to represent clearer
# or more turbid water.  theta is the transmitter half-angle in radians.
set opt(attenuation_c)      0.043     ;# 1/m: constant Lambert-Beer c (default 0.043)
set opt(theta)              1.0       ;# rad: transmitter beam half-angle
set opt(omnidirectional)    0         ;# 0 enables directional beam factors
set opt(inclination_0)      0       ;# rad: node 0 points toward +X
set opt(inclination_1)      [expr {3.141592653589793/1.0}]    ;# rad: node 1 points toward -X
set opt(sample_dir)         [file dirname [info script]]
set opt(db_dir)             [file normalize [file join $opt(sample_dir) ../../dbs]]
set opt(beam_lut_path)      "../../dbs/bluecomm/beam_pattern/beam5mbps.csv"
set opt(max_range_lut_path) "../../dbs/bluecomm/max_range/max_range5mbps.csv"
set opt(noise_lut_path)     "../../dbs/optical_noise/LUT.txt"
# set opt(attenuation_lut)    "../../dbs/optical_attenuation/lut_532nm/lut_532nm_CTD025.csv"

# MAC, diagnostics, and trace output.
set opt(ack_mode)           "setNoAckMode"
set opt(maxinterval)        10.0       ;# s: interference history interval
set opt(verbose)             1         ;# 1 prints a summary at the end
set opt(debug)               0         ;# 1 enables optical PHY/prop debug
set opt(trace_files)         0         ;# 1 writes trace files in this folder
set opt(trace_prefix)        "two_optical_modems"

################################
# Optional command-line sweep  #
################################
# The five positional values make range/depth/traffic easy to sweep from a
# shell.  Every other parameter remains available in the section above.
if {$argc > 0} {
    if {$argc != 5} {
        puts "Usage: ns two_optical_modems.tcl rngstream cbr_period packet_size range depth"
        exit 1
    }
    set opt(rngstream)  [lindex $argv 0]
    set opt(cbr_period) [lindex $argv 1]
    set opt(pktsize)    [lindex $argv 2]
    set opt(range)      [lindex $argv 3]
    set opt(depth)      [lindex $argv 4]
}

################################
# DESERT library loading       #
################################
# These are the only libraries required by the stack below.  No WOSS library,
# WOSS database, ambient-light LUT, attenuation LUT, or beam-pattern LUT is
# loaded; propagation uses the fixed coefficient configured above.
load libMiracle.so
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
# /dev/null keeps the example quiet and avoids creating files by default.
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
# Setting class defaults before creating objects gives every modem the same
# explicitly documented configuration.  To model asymmetric modems, move
# these settings into createNode and set them conditionally on id.
Module/UW/CBR set packetSize_                       $opt(pktsize)
Module/UW/CBR set period_                           $opt(cbr_period)
Module/UW/CBR set PoissonTraffic_                   $opt(poisson_traffic)
Module/UW/CBR set debug_                            $opt(debug)

Module/UW/UWOPTICALBEAMPATTERN set TxPower_                  $opt(txpower)
Module/UW/UWOPTICALBEAMPATTERN set BitRate_                  $opt(bitrate)
Module/UW/UWOPTICALBEAMPATTERN set AcquisitionThreshold_dB_  $opt(acq_threshold_db)
Module/UW/UWOPTICALBEAMPATTERN set Id_                       $opt(id)
Module/UW/UWOPTICALBEAMPATTERN set Il_                       $opt(il)
Module/UW/UWOPTICALBEAMPATTERN set R_                        $opt(shunt_resistance)
Module/UW/UWOPTICALBEAMPATTERN set S_                        $opt(sensitivity)
Module/UW/UWOPTICALBEAMPATTERN set T_                        $opt(temperature)
Module/UW/UWOPTICALBEAMPATTERN set Ar_                       $opt(rx_area)
Module/UW/UWOPTICALBEAMPATTERN set debug_                    $opt(debug)

Module/UW/OPTICAL/Propagation set Ar_               $opt(rx_area)
Module/UW/OPTICAL/Propagation set At_               $opt(tx_area)
Module/UW/OPTICAL/Propagation set c_                $opt(attenuation_c)
Module/UW/OPTICAL/Propagation set theta_            $opt(theta)
Module/UW/OPTICAL/Propagation set debug_            $opt(debug)

# This propagation object computes the distance-dependent optical gain.
# setFixedC is important: it selects the constant c_ above and therefore does
# not require an attenuation LUT.  The beam-pattern PHY uses its own beam,
# maximum-range, and ambient-light tables configured above.
set propagation [new Module/UW/OPTICAL/Propagation]
if {$opt(omnidirectional)} {
    $propagation setOmnidirectional
} else {
    $propagation setDirectional
}
$propagation setFixedC

# The optical channel carries packets between all PHYs attached to it.
set channel [new Module/UW/Optical/Channel]

# A rectangular spectral mask defines the signal frequency and bandwidth.
set data_mask [new MSpectralMask/Rect]
$data_mask setFreq      $opt(freq)
$data_mask setBandwidth $opt(bw)

# Tiny times prevent the CSMA-ALOHA example from waiting on a long acoustic
# listen interval.  Increase them for experiments involving MAC timing.
Module/UW/CSMA_ALOHA set listen_time_  [expr 1.0e-12]
Module/UW/CSMA_ALOHA set wait_costant_ [expr 1.0e-12]

################################
# Node construction             #
################################
proc createNode {id} {
    global ns channel opt
    global node cbr udp ipr ipif mll mac phy position portnum interf_data
    global propagation data_mask

    # Allocate a Miracle node and one CBR source for each possible destination.
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

    # Build the stack from application (7) down to optical PHY (1).
    for {set dst 0} {$dst < $opt(nn)} {incr dst} {
        $node($id) addModule 7 $cbr($id,$dst) 1 "CBR"
    }
    $node($id) addModule 6 $udp($id)  1 "UDP"
    $node($id) addModule 5 $ipr($id)  1 "IPR"
    $node($id) addModule 4 $ipif($id) 1 "IPF"
    $node($id) addModule 3 $mll($id)  1 "MLL"
    $node($id) addModule 2 $mac($id)  1 "MAC"
    $node($id) addModule 1 $phy($id)  1 "PHY"

    # Connect adjacent layers and assign one UDP port per CBR source.
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

    # Configure interference, shared propagation, and the spectral mask.
    set interf_data($id) [new MInterference/MIV]
    $interf_data($id) set maxinterval_ $opt(maxinterval)
    $interf_data($id) set debug_ $opt(debug)
    $phy($id) setInterference $interf_data($id)
    $phy($id) setPropagation $propagation
    $phy($id) setSpectralMask $data_mask
    $phy($id) setLUTFileName $opt(noise_lut_path)
    $phy($id) setLUTSeparator " "
    $phy($id) setBeamPatternPath $opt(beam_lut_path)
    $phy($id) setMaxRangePath $opt(max_range_lut_path)
    $phy($id) useLUT
    $phy($id) setVariableTemperature
    if {$id == 0} {
        $phy($id) setInclinationAngle $opt(inclination_0)   ; # 0
    } else {
        $phy($id) setInclinationAngle $opt(inclination_1)   ; # pi
    }

    # Give each node a unique IP address and place both modems at the same
    # depth, separated along X.  The inclination angles above make them face
    # one another along this axis; change range/depth in the parameter section
    # or CLI.
    $ipif($id) addr [expr {$id + 1}]
    set position($id) [new Position/BM]
    $node($id) addPosition $position($id)
    $position($id) setX_ [expr {$id * $opt(range)}]
    $position($id) setY_ 0.0
    $position($id) setZ_ $opt(depth)

    # Disable ACKs for this one-way-per-direction demonstration and initialize
    # the MAC after all of its parameters have been set.
    $mac($id) $opt(ack_mode)
    $mac($id) initialize
}

################################
# Modem creation               #
################################
for {set id 0} {$id < $opt(nn)} {incr id} {
    createNode $id
}

################################
# Configure the two directions #
################################
# Each modem has a CBR source aimed at the other modem.  The self-destination
# sources are left unstarted (see next section), so this remains a two-modem
# point-to-point test.
for {set src 0} {$src < $opt(nn)} {incr src} {
    for {set dst 0} {$dst < $opt(nn)} {incr dst} {
        puts "dst:$dst, src:$src"
        $cbr($src,$dst) set destAddr_ [$ipif($dst) addr]
        $cbr($src,$dst) set destPort_ $portnum($dst,$src)
        $mll($src) addentry [$ipif($dst) addr] [$mac($dst) addr]
        $ipr($src) addRoute [$ipif($dst) addr] [$ipif($dst) addr]
    }
}

################################
# Start and stop traffic       #
################################
for {set src 0} {$src < $opt(nn)} {incr src} {
    for {set dst 0} {$dst < $opt(nn)} {incr dst} {
        if {$src != $dst} {
            # Offset opposite directions to avoid deterministic collisions:
            # both periodic CBR sources would otherwise transmit together.
            set flow_start [expr {$opt(starttime) + $src * $opt(cbr_period) / 2.0}]
            $ns at $flow_start "$cbr($src,$dst) start"
            $ns at $opt(stoptime)  "$cbr($src,$dst) stop"
        }
    }
}

################################
# End-of-run summary           #
################################
proc finish {} {
    global ns opt cbr
    set sent 0.0
    set received 0.0
    if {$opt(verbose)} {
        puts "----------------------------------------"
        puts "Two-node optical modem simulation"
        puts "distance: $opt(range) m, depth: $opt(depth) m"
        puts "attenuation c: $opt(attenuation_c) 1/m"
    }
    for {set src 0} {$src < $opt(nn)} {incr src} {
        for {set dst 0} {$dst < $opt(nn)} {incr dst} {
            if {$src != $dst} {
                set s [$cbr($src,$dst) getsentpkts]
                set r [$cbr($src,$dst) getrecvpkts]
                set sent [expr {$sent + $s}]
                set received [expr {$received + $r}]
            }
        }
    }
    if {$opt(verbose)} {
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
puts "Starting two-node optical simulation"
$ns at [expr {$opt(stoptime) + 1.0}] "finish; $ns halt"
$ns run
