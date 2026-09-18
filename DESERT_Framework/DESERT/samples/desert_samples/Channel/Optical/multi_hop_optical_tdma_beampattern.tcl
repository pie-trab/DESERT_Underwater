#
# Parametrized multi-hop underwater optical simulation for DESERT.
#
# HOW THIS EXAMPLE WORKS
# ----------------------
# The topology is generated as a chain:
#
#   sender -> relay_0_rx -> relay_0_tx -> relay_1_rx -> relay_1_tx -> ... -> receiver
#
# Every relay is represented by two colocated (or almost colocated) DESERT
# nodes.  The first node is the receiving optical head and the second node is
# the transmitting optical head.  The short link between the two heads is
# modeled as a short optical water hop.  Normal IP forwarding passes the
# packet from the receiving head to the transmitting head, so no traffic
# application is started on the relays.
#
# DESERT's native UW/TDMA MAC is used to prevent optical collisions.  Every
# modem has one slot in a common frame and the slot number follows the path
# order.  A packet therefore advances one hop per available slot and is
# queued by TDMA when it arrives outside the next modem's slot.
#
# RUNNING THE EXAMPLE
# -------------------
# Optional command-line arguments are:
#
#   ns multi_hop_optical_tdma_beampattern.tcl \
#       n_relays \
#       cbr_period \
#       packet_size \
#       hop_length \
#       relay_gap \
#       depth \
#       stop_time \
#       rngstream \
#       attenuation_scale \
#       poisson_traffic \
#       depths \
#       optical_txpower \
#       optical_acq_threshold_db \
#       optical_theta
#
# All other parameters, including the per-hop attenuation list, are changed
# in the parameter section below.  Optical PHY sensitivity parameters can
# also be overridden from the command line for automated sweeps.  This variant
# uses the directional beam-pattern PHY and the repository optical LUTs.
#
#

################################
# User-changeable parameters    #
################################


source "get-config.tcl"

set config_filename "multi_hop_optical_tdma_opt.yaml"
load-config $config_filename

# The LUTs are the same family used by old/test_uwopticalbeampattern.tcl.
# Paths are relative to this Optical directory when the example is run here.
set opt(noise_lut_path)        "../../dbs/optical_noise/LUT.txt"
set opt(attenuation_lut_path) "../../dbs/optical_attenuation/lut_532nm/lut_532nm_CTD025.csv"
set opt(beam_lut_path)        "../../dbs/bluecomm/beam_pattern/beam5mbps.csv"
set opt(max_range_lut_path)   "../../dbs/bluecomm/max_range/max_range5mbps.csv"

# One orientation per physical role in the generated chain.  The beam model
# uses inclination in the X-Z plane; these values keep each optical head
# aligned with its incoming/outgoing path while retaining the Y-axis layout.
set opt(inclination_rx)       -1.570796326794897
set opt(inclination_tx)        1.570796326794897

################################
# Optional command-line values  #
################################

# The list of per-hop attenuation values remains in the Tcl file because it
# has one value per generated link.  The scalar topology/traffic parameters
# can conveniently be overridden from a shell.  The optional arguments after
# the first seven are useful for automated sweeps.  The depth profile is an
# empty Tcl argument when omitted, followed by optional optical PHY overrides.
if {$argc > 0} {
    if {$argc < 7 || $argc > 14} {
        puts "Usage: ns multi_hop_optical_tdma_beampattern.tcl n_relays cbr_period packet_size hop_length relay_gap depth stop_time ?rngstream? ?attenuation_scale? ?poisson_traffic? ?depths? ?optical_txpower? ?optical_acq_threshold_db? ?optical_theta?"
        exit 1
    }
    set opt(n_relays)    [lindex $argv 0]
    set opt(cbr_period)  [lindex $argv 1]
    set opt(pktsize)     [lindex $argv 2]
    set opt(hop_length)  [lindex $argv 3]
    set opt(relay_gap)   [lindex $argv 4]
    set opt(depth)       [lindex $argv 5]
    set opt(stoptime)    [lindex $argv 6]
    if {$argc >= 8} {
        set opt(rngstream) [lindex $argv 7]
    }
    if {$argc >= 9} {
        set opt(attenuation_scale) [lindex $argv 8]
    }
    if {$argc == 10} {
        set opt(poisson_traffic) [lindex $argv 9]
    }
    if {$argc >= 11} {
        set opt(poisson_traffic) [lindex $argv 9]
        set opt(depths) [lindex $argv 10]
    } else {
        # Command-line topology sweeps use the scalar depth unless an
        # explicit profile is supplied as the final argument.
        set opt(depths) {}
    }
    if {$argc >= 12} {
        set opt(txpower) [lindex $argv 11]
    }
    if {$argc >= 13} {
        set opt(acq_threshold_db) [lindex $argv 12]
    }
    if {$argc >= 14} {
        set opt(theta) [lindex $argv 13]
    }
}

# There are two end modems plus two modem nodes for every relay couple.
set opt(nn)          [expr {2 + 2 * $opt(n_relays)}]
set opt(sender_id)   0
set opt(receiver_id) [expr {1 + 2 * $opt(n_relays)}]
set opt(n_hops)      [expr {$opt(nn) - 1}]

# Keep the scalar command-line depth useful for topology sweeps.  A supplied
# depth profile must contain exactly one value per generated modem.
if {[llength $opt(depths)] == 0} {
    set opt(depths) {}
    for {set id 0} {$id < $opt(nn)} {incr id} {
        lappend opt(depths) $opt(depth)
    }
} elseif {[llength $opt(depths)] != $opt(nn)} {
    puts "Error: depths must contain exactly $opt(nn) values, got [llength $opt(depths)]"
    exit 1
}

# Return the attenuation coefficient for a link.  The receiver of hop H is
# node H+1, so this function is called with H in the range 0..n_hops-1.
proc attenuationForHop {hop} {
    global opt

    set values $opt(attenuation_c_per_hop)
    set nvalues [llength $values]
    if {$nvalues == 0} {
        return [expr {$opt(attenuation_c_default)*$opt(attenuation_scale)}]
    }
    if {$hop < $nvalues} {
        return [expr {[lindex $values $hop]*$opt(attenuation_scale)}]
    }
    # Reusing the last value avoids an out-of-range error when the user adds
    # more relay couples without extending the example list immediately.
    return [expr {[lindex $values end]*$opt(attenuation_scale)}]
}

# Automatically make a frame long enough for one packet in every slot.  The
# extra 20% is a small timing margin for headers and simulator scheduling.
set opt(packet_time) [expr {8.0 * $opt(pktsize) / $opt(bitrate)}]
set opt(min_frame_duration) [expr {$opt(nn) * ($opt(packet_time) + $opt(guard_time)) * 1.20}]
if {$opt(auto_frame_duration) && $opt(frame_duration) < $opt(min_frame_duration)} {
    set opt(frame_duration) $opt(min_frame_duration)
}

################################
# DESERT library loading       #
################################

# These modules provide the IP forwarding stack, directional optical
# beam-pattern PHY, optical channel, and the native TDMA MAC.
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

# CBR creates the application packets.  Only the sender-side CBR is started
# later; all other CBR objects exist only to provide valid destination ports.

Module/UW/CBR set packetSize_     $opt(pktsize)         ; # application payload size in bytes. Increasing it increases
                                                          # optical transmission time and the required TDMA slot size.
Module/UW/CBR set period_         $opt(cbr_period)      ; # time between generated packets in seconds when periodic traffic is
                                                          # selected.  With PoissonTraffic_=1 it is the mean inter-packet time.
Module/UW/CBR set PoissonTraffic_ $opt(poisson_traffic) ; # 0 generates packets periodically; 1 draws each interval
                                                         # from an exponential distribution using DESERT's RNG.
Module/UW/CBR set debug_          $opt(debug)           ; # CBR diagnostic verbosity.  Keep it 0 for normal experiments.

# All nodes share the same slot schedule.  setSlotNumber is applied per
# modem below, so no external TDMA schedule file is needed.

# Frame duration must include one packet and its guard time in every slot.
set opt(packet_time) [expr {8.0 * $opt(pktsize) / $opt(bitrate)}]
set opt(min_frame_duration) [expr {$opt(nn) * ($opt(packet_time) + $opt(guard_time)) * 1.20}]
if {$opt(auto_frame_duration) && $opt(frame_duration) < $opt(min_frame_duration)} {
    set opt(frame_duration) $opt(min_frame_duration)
}
Module/UW/TDMA set frame_duration      $opt(frame_duration)      ; # duration of one complete TDMA frame in seconds. Every node
                                                                  # gets frame_duration/tot_slots seconds for its slot.
# max_transmission time
Module/UW/TDMA set guard_time          $opt(guard_time)          ; # silent safety interval between adjacent slots in seconds.
                                                                  # It reduces overlap caused by timing/propagation uncertainty.
Module/UW/TDMA set tot_slots           $opt(nn)                  ; # number of slots in the frame. Here it equals the number of
                                                                  # modems, so every modem receives one unique slot.
Module/UW/TDMA set fair_mode           1                         ; # 1 enables equal-duration slots using frame_duration and
                                                                  # tot_slots; 0 uses generic per-node slot timing.
Module/UW/TDMA set max_packet_per_slot $opt(max_packet_per_slot) ; # maximum packets a modem may transmit during one slot.
                                                                  # One keeps the schedule predictable for this chain.
Module/UW/TDMA set queue_size_         $opt(queue_size)          ; # maximum number of packets waiting in a modem's TDMA queue.
                                                                  # Increase it if traffic is faster than the multi-hop pipeline.
Module/UW/TDMA set drop_old_           0                         ; # 0 drops a newly arriving packet when the queue is full.
                                                                  # Set it to 1 to discard the oldest queued packet instead.
Module/UW/TDMA set sea_trial_          0                         ; # 0 disables the extra per-node TDMA log files for sea trials.
Module/UW/TDMA set debug_              $opt(debug)               ; # TDMA diagnostic verbosity; values greater than 0 print diagnostics.
Module/UW/TDMA set mac2phy_delay_      [expr 1.0e-9]              ; # simulated delay between a MAC transmit request and PHY
                                                                  # transmission, in seconds.

# Optical PHY defaults.  Each node receives its own propagation object below
# so attenuation_c can vary from hop to hop.
Module/UW/UWOPTICALBEAMPATTERN set TxPower_                 $opt(txpower)         ; # optical transmitter power in watts in this DESERT model.
Module/UW/UWOPTICALBEAMPATTERN set BitRate_                 $opt(bitrate)         ; # optical bit rate in bit/s. It determines packet transmission time.
Module/UW/UWOPTICALBEAMPATTERN set AcquisitionThreshold_dB_ $opt(acq_threshold_db) ; # minimum received SNR, in dB, needed to lock onto
                                                                           # an incoming optical packet.
Module/UW/UWOPTICALBEAMPATTERN set Id_                      $opt(id)              ; # photodiode dark current in amperes, contributing to receiver noise.
Module/UW/UWOPTICALBEAMPATTERN set Il_                      $opt(il)              ; # fixed background photocurrent in amperes. Increase it to model more
                                                                           # ambient light; it raises the receiver noise floor.
Module/UW/UWOPTICALBEAMPATTERN set R_                       $opt(shunt_resistance) ; # receiver shunt resistance in ohms, used in the thermal-noise model.
Module/UW/UWOPTICALBEAMPATTERN set S_                       $opt(sensitivity)      ; # photodiode sensitivity in A/W, converting received optical power into
                                                                           # photocurrent.
Module/UW/UWOPTICALBEAMPATTERN set T_                       $opt(temperature)      ; # receiver temperature in kelvin, used for the thermal-noise calculation.
Module/UW/UWOPTICALBEAMPATTERN set Ar_                      $opt(rx_area)          ; # receiver photodiode area in square metres.
Module/UW/UWOPTICALBEAMPATTERN set debug_                   $opt(debug)            ; # optical PHY diagnostic verbosity.

# One optical channel carries all modem PHYs.  The TDMA schedule prevents
# simultaneous transmissions, while the MAC destination field discards
# packets that are heard by a modem other than the selected next hop.
# channel: shared simulated underwater optical medium to which every PHY is
#          attached below with addToChannel.
set channel [new Module/UW/Optical/Channel]
set data_mask [new MSpectralMask/Rect]      ; # frequency/bandwidth description of the optical signal.
$data_mask setFreq      $opt(freq)          ; # center frequency of the sig nal in hertz.
$data_mask setBandwidth $opt(bw)            ; # signal bandwidth in hertz; it affects receiver noise power.


################################
# Node-construction procedure   #
################################

proc createOpticalNode {id} {
    global ns channel opt
    global node cbr udp ipr ipif mll mac phy position portnum interf_data propagation
    global data_mask

    # Create the DESERT node and one conventional protocol stack.
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
    set phy($id)  [new Module/UW/UWOPTICALBEAMPATTERN]

    $node($id) addModule 6 $udp($id)  1 "UDP"
    $node($id) addModule 5 $ipr($id)  1 "IPR"
    $node($id) addModule 4 $ipif($id) 1 "IPF"
    $node($id) addModule 3 $mll($id)  1 "MLL"
    $node($id) addModule 2 $mac($id)  1 "MAC"
    $node($id) addModule 1 $phy($id)  1 "PHY"

    # Wire the stack.  The CBR objects all share the local UDP module and are
    # assigned ports so the sender can address the receiver's application.
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

    # Use a propagation object dedicated to this receiving modem.  In the
    # optical PHY, the destination PHY evaluates received power with its
    # propagation object; assigning c for node H+1 therefore configures hop H.
    set propagation($id) [new Module/UW/OPTICAL/Propagation]
    $propagation($id) setAr    $opt(rx_area)
    $propagation($id) setAt    $opt(tx_area)
    $propagation($id) setTheta $opt(theta)
    if {$id == 0} {
        $propagation($id) setC $opt(attenuation_c_default)
    } else {
        $propagation($id) setC [attenuationForHop [expr {$id - 1}]]
    }
    # Use the CTD attenuation LUT when both endpoint depths are covered.
    # The per-hop c_ value above remains the fallback outside the LUT range.
    $propagation($id) setDirectional
    $propagation($id) setLUTFileName $opt(attenuation_lut_path)
    $propagation($id) setLUTSeparator ","
    if {$opt(attenuation_scale) != 1.0} {
        $propagation($id) setFixedC
    } else {
        $propagation($id) setLUT
        $propagation($id) setVariableC
    }
    $propagation($id) set debug_ $opt(debug)
    $phy($id) setPropagation $propagation($id)

    # A separate interference history is required by each PHY.  TDMA avoids
    # planned overlap; this model still detects an accidental overlap.
    set interf_data($id) [new MInterference/MIV]
    $interf_data($id) set maxinterval_ $opt(maxinterval)
    $interf_data($id) set debug_ $opt(debug)
    $phy($id) setInterference $interf_data($id)
    $phy($id) setSpectralMask $data_mask

    # Load ambient-light noise, beam-pattern, and maximum-range LUTs on each
    # PHY, as required by UWOPTICALBEAMPATTERN.
    $phy($id) setLUTFileName $opt(noise_lut_path)
    $phy($id) setLUTSeparator " "
    $phy($id) setBeamPatternPath $opt(beam_lut_path)
    $phy($id) setMaxRangePath $opt(max_range_lut_path)
    $phy($id) useLUT
    $phy($id) setVariableTemperature
    # Select the X-Z inclination from the first non-horizontal link touching
    # this head.  A downward hop uses -pi/2 for transmission and +pi/2 for
    # reception; the signs reverse for an upward hop.  Horizontal relay gaps
    # need no vertical correction, so the adjacent sloped hop supplies it.
    set current_z [lindex $opt(depths) $id]
    set inclination 0.0
    if {$id < $opt(receiver_id)} {
        set next_z [lindex $opt(depths) [expr {$id + 1}]]
        if {$next_z != $current_z} {
            set inclination [expr {$next_z < $current_z ? $opt(inclination_rx) : $opt(inclination_tx)}]
        } elseif {$id > 0} {
            set previous_z [lindex $opt(depths) [expr {$id - 1}]]
            if {$previous_z != $current_z} {
                set inclination [expr {$current_z < $previous_z ? $opt(inclination_tx) : $opt(inclination_rx)}]
            }
        }
    } elseif {$id > 0} {
        set previous_z [lindex $opt(depths) [expr {$id - 1}]]
        if {$previous_z != $current_z} {
            set inclination [expr {$current_z < $previous_z ? $opt(inclination_tx) : $opt(inclination_rx)}]
        }
    }
    $phy($id) setInclinationAngle $inclination

    # IP and MAC addresses are unique and follow the physical path order.
    $ipif($id) addr [expr {$id + 1}]
    $mac($id) setMacAddr [expr {$id + 1}]
    $mac($id) setSlotNumber $id

    # All heads are aligned along Y.  Relay RX/TX heads are separated by the
    # small relay_gap, which models their short internal water connection.
    set position($id) [new Position/BM]
    $node($id) addPosition $position($id)
    $position($id) setX_ 0.0
    if {$id == 0} {
        set y 0.0
    } elseif {$id == $opt(receiver_id)} {
        set y [expr {($opt(n_relays) + 1) * $opt(hop_length) + $opt(n_relays) * $opt(relay_gap)}]
        puts "Receiver $y" 
    } elseif {[expr {$id % 2}] == 1} {
        # RX head of relay i.
        set i [expr {($id - 1) / 2}]
        set y [expr {($i + 1) * $opt(hop_length) + $i * $opt(relay_gap)}]
        puts "Relay Receiver $y" 
    } else {
        # TX head of relay i.
        set i [expr {($id - 2) / 2}]
        set y [expr {($i + 1) * $opt(hop_length) + ($i + 1) * $opt(relay_gap)}]
        puts "Relay Transmitter $y" 
    }
    $position($id) setY_ $y
    $position($id) setZ_ [lindex $opt(depths) $id]
}

################################
# Create the complete chain     #
################################

for {set id 0} {$id < $opt(nn)} {incr id} {
    createOpticalNode $id
}

################################
# Configure CBR and ARP tables  #
################################

# The source packet keeps the final receiver IP address end-to-end.  The UDP
# destination port is the port assigned to the receiver's CBR object that is
# paired with the sender.
$cbr($opt(sender_id),$opt(receiver_id)) set destAddr_ [$ipif($opt(receiver_id)) addr]
$cbr($opt(sender_id),$opt(receiver_id)) set destPort_ $portnum($opt(receiver_id),$opt(sender_id))

# MLL is the DESERT equivalent of a neighbor/MAC address table.
# It is populated for every pair so each static next-hop route
# can resolve its destination MAC.
for {set src 0} {$src < $opt(nn)} {incr src} {
    for {set dst 0} {$dst < $opt(nn)} {incr dst} {
        if {$src != $dst} {
            $mll($src) addentry [$ipif($dst) addr] [$mac($dst) addr]
        }
    }
}

################################
# Install the forced IP path    #
################################

# Every node forwards the final receiver address to the next node in the
# generated chain.  The last node routes the address to itself for local UDP
# delivery.  This is what makes the middle nodes relays without applications.
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
# Start/stop schedule           #
################################

# Start all TDMA MACs at time zero.  Each MAC internally waits for its
# assigned slot offset.  Starting them before traffic makes the frame phase
# deterministic and prevents a modem from missing the first packet.
for {set id 0} {$id < $opt(nn)} {incr id} {
    $ns at 0.0 "$mac($id) start"
    $ns at [expr {$opt(stoptime) + $opt(frame_duration) + 0.5}] "$mac($id) stop"
}

# Only the sender generates traffic.  Intermediate CBR modules are never
# started; they only supply UDP port objects for routing compatibility.
$ns at $opt(starttime) "$cbr($opt(sender_id),$opt(receiver_id)) start"
$ns at $opt(stoptime)  "$cbr($opt(sender_id),$opt(receiver_id)) stop"

################################
# End-of-run diagnostics        #
################################

proc finish {} {
    global ns opt cbr mac

    set sender_cbr $cbr($opt(sender_id),$opt(receiver_id))
    set receiver_cbr $cbr($opt(receiver_id),$opt(sender_id))
    set sent [$sender_cbr getsentpkts]
    set received [$receiver_cbr getrecvpkts]

    if {$opt(verbose)} {
        puts "----------------------------------------"
        puts "Multi-hop optical TDMA simulation"
        puts "relay couples: $opt(n_relays)"
        puts "modem nodes: $opt(nn), hops: $opt(n_hops)"
        puts "hop length: $opt(hop_length) m, relay gap: $opt(relay_gap) m"
        puts "depth: $opt(depth) m"
        puts "depths: $opt(depths) m"
        puts "TDMA frame: $opt(frame_duration) s, guard: $opt(guard_time) s"
        puts "attenuation c per hop: $opt(attenuation_c_per_hop) 1/m"
        puts "attenuation scale factor: $opt(attenuation_scale)"
        puts "sent packets: $sent"
        puts "received packets: $received"
        puts "forward trip time mean: [$receiver_cbr getftt] s"
        puts "forward trip time std: [$receiver_cbr getfttstd] s"
        puts "cbr throughput: [$receiver_cbr getthr] bit/s"
        puts "per-hop MAC counters (sent received):"
        for {set id 0} {$id < $opt(nn)} {incr id} {
            puts "  modem $id: [$mac($id) get_sent_pkts] [$mac($id) get_recv_pkts]"
            puts "  modem $id final queue: [$mac($id) get_buffer_size]"
        }
        puts "----------------------------------------"
    }

    $ns flush-trace
    close $opt(tracefile)
    close $opt(cltracefile)
}

################################
# Run the simulation           #
################################

puts "Starting multi-hop optical TDMA simulation with LUT beam patterns"
puts "Path has $opt(n_hops) hops and $opt(n_relays) relay couples"
$ns at [expr {$opt(stoptime) + $opt(frame_duration) + 1.0}] "finish; $ns halt"
$ns run
