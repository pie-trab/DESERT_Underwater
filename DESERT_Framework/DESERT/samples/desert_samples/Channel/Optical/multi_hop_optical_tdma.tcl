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
# Source the DESERT environment first, then run this file from this directory:
#
#   source <DESERT_build>/environment
#   ns multi_hop_optical_tdma.tcl
#
# Optional command-line arguments are:
#
#   ns multi_hop_optical_tdma.tcl \
#       n_relays cbr_period packet_size hop_length relay_gap depth stop_time \
#       rngstream attenuation_scale poisson_traffic
#
# All other parameters, including the per-hop attenuation list, are changed
# in the parameter section below.  The ordinary optical PHY is intentionally
# used here: it needs no WOSS, beam LUT, attenuation LUT, or noise LUT.
#
# ATTENUATION PER HOP
# -------------------
# opt(attenuation_c_per_hop) is a Tcl list.  Element 0 is the first link
# (sender -> relay_0_rx), element 1 is the relay-0 internal link, and so on.
# If the list is empty, opt(attenuation_c_default) is used for every link.  If
# the list is shorter than the chain, its last value is reused for the
# remaining links.  This makes the script safe when n_relays is changed while
# still allowing each link to be configured independently.
#

################################
# User-changeable parameters    #
################################

# Number of relay couples.  Each couple contributes two optical modem nodes.
set opt(n_relays)              2

# Traffic and simulation timing.
set opt(starttime)             0.1       ; # s: sender application start time
set opt(stoptime)              20.0      ; # s: sender application stop time
set opt(cbr_period)            2.0       ; # s: packet generation period
set opt(pktsize)               1400      ; # byte: CBR payload size
set opt(poisson_traffic)       1         ; # 0=periodic CBR, 1=Poisson CBR
set opt(rngstream)             1         ; # random-number substream

# Geometry.  All modem heads are on the Y axis at one common depth.
set opt(hop_length)            20.0      ; # m: normal inter-head hop
set opt(relay_gap)             1.5       ; # m: distance inside each relay pair
set opt(depth)                 -10.0     ; # m: negative Z coordinate

# The first value is used only as a fallback for the source modem.  The
# receiving modem of each hop gets the corresponding value from the list.
set opt(attenuation_c_default) 0.043     ;# 1/m: clear-water fallback
set opt(attenuation_c_per_hop) {0.043 0.0 0.043 0.0 0.043}
set opt(attenuation_scale)   1.0       ; # scale factor for the above list

# Optical physical-layer parameters.
set opt(freq)                  7.59e14   ; # Hz: center frequency (c/395 nm - blue light carrier)
set opt(bw)                    10000000  ; # Hz: signal bandwidth (10MHz)
set opt(bitrate)               10000000  ; # bit/s (10Mb/s)
set opt(txpower)               10.0      ; # W: optical transmit power
set opt(acq_threshold_db)      10.0      ; # dB: receiver acquisition threshold
set opt(id)                    1.0e-9    ; # A: photodiode dark current
set opt(il)                    1.0e-6    ; # A: fixed background photocurrent
set opt(shunt_resistance)      1.49e9    ; # ohm: receiver shunt resistance
set opt(sensitivity)           0.26      ; # A/W: photodiode sensitivity
set opt(temperature)           313.15    ; # K: receiver temperature (40°C)
set opt(rx_area)               330.06e-6 ; # m^2: receiver area
set opt(tx_area)               36e-6     ; # m^2: transmitter area
set opt(theta)                 0.524     ; # rad: analytical beam divergence (30 deg half-angle, 60 full-angle)

# TDMA parameters.  The frame is automatically enlarged when necessary so a
# slot can contain one complete packet plus its guard time.  Set
# auto_frame_duration to 0 to enforce frame_duration manually.
set opt(frame_duration)        2.0       ; # s: common TDMA frame duration
set opt(auto_frame_duration)   1         ; # 2=protect slots automatically
set opt(guard_time)            0.01      ; # s: guard time between slots
set opt(max_packet_per_slot)   2         ; # packets sent by one modem per slot
set opt(queue_size)            32        ; # packets buffered by each modem
set opt(maxinterval)           10.0      ; # s: interference history window

# Diagnostics and trace output.
set opt(verbose)               1         ; # 1=print the final summary
set opt(debug)                 0         ; # 1=enable optical/CBR debug output
set opt(trace_files)           0         ; # 1=write .tr and .cltr traces
set opt(trace_prefix)          "multi_hop_optical_tdma"

################################
# Optional command-line values  #
################################

# The list of per-hop attenuation values remains in the Tcl file because it
# has one value per generated link.  The scalar topology/traffic parameters
# can conveniently be overridden from a shell.  The last three arguments are
# optional and are useful for automated sweeps.
if {$argc > 0} {
    if {$argc != 7 && $argc != 8 && $argc != 9 && $argc != 10} {
        puts "Usage: ns multi_hop_optical_tdma.tcl n_relays cbr_period packet_size hop_length relay_gap depth stop_time ?rngstream? ?attenuation_scale? ?poisson_traffic?"
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
}

# There are two end modems plus two modem nodes for every relay couple.
set opt(nn)          [expr {2 + 2 * $opt(n_relays)}]
set opt(sender_id)   0
set opt(receiver_id) [expr {1 + 2 * $opt(n_relays)}]
set opt(n_hops)      [expr {$opt(nn) - 1}]

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

# These modules provide the IP forwarding stack, optical channel/PHY, and the
# native TDMA MAC.  No WOSS or external lookup-table library is required.
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
Module/UW/TDMA set frame_duration      $opt(frame_duration)      ; # duration of one complete TDMA frame in seconds. Every node
                                                                  # gets frame_duration/tot_slots seconds for its slot.
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
Module/UW/OPTICAL/PHY set TxPower_                 $opt(txpower)         ; # optical transmitter power in watts in this DESERT model.
Module/UW/OPTICAL/PHY set BitRate_                 $opt(bitrate)         ; # optical bit rate in bit/s. It determines packet transmission time.
Module/UW/OPTICAL/PHY set AcquisitionThreshold_dB_ $opt(acq_threshold_db) ; # minimum received SNR, in dB, needed to lock onto
                                                                           # an incoming optical packet.
Module/UW/OPTICAL/PHY set Id_                      $opt(id)              ; # photodiode dark current in amperes, contributing to receiver noise.
Module/UW/OPTICAL/PHY set Il_                      $opt(il)              ; # fixed background photocurrent in amperes. Increase it to model more
                                                                           # ambient light; it raises the receiver noise floor.
Module/UW/OPTICAL/PHY set R_                       $opt(shunt_resistance) ; # receiver shunt resistance in ohms, used in the thermal-noise model.
Module/UW/OPTICAL/PHY set S_                       $opt(sensitivity)      ; # photodiode sensitivity in A/W, converting received optical power into
                                                                           # photocurrent.
Module/UW/OPTICAL/PHY set T_                       $opt(temperature)      ; # receiver temperature in kelvin, used for the thermal-noise calculation.
Module/UW/OPTICAL/PHY set Ar_                      $opt(rx_area)          ; # receiver photodiode area in square metres.
Module/UW/OPTICAL/PHY set debug_                   $opt(debug)            ; # optical PHY diagnostic verbosity.

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
    set phy($id)  [new Module/UW/OPTICAL/PHY]

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
    # $propagation($id) setOmnidirectional
    $propagation($id) setFixedC
    $propagation($id) set debug_ $opt(debug)
    $phy($id) setPropagation $propagation($id)

    # A separate interference history is required by each PHY.  TDMA avoids
    # planned overlap; this model still detects an accidental overlap.
    set interf_data($id) [new MInterference/MIV]
    $interf_data($id) set maxinterval_ $opt(maxinterval)
    $interf_data($id) set debug_ $opt(debug)
    $phy($id) setInterference $interf_data($id)
    $phy($id) setSpectralMask $data_mask

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
    } elseif {[expr {$id % 2}] == 1} {
        # RX head of relay i.
        set i [expr {($id - 1) / 2}]
        set y [expr {($i + 1) * $opt(hop_length) + $i * $opt(relay_gap)}]
    } else {
        # TX head of relay i.
        set i [expr {($id - 2) / 2}]
        set y [expr {($i + 1) * $opt(hop_length) + ($i + 1) * $opt(relay_gap)}]
    }
    $position($id) setY_ $y
    $position($id) setZ_ $opt(depth)
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

# MLL is the DESERT equivalent of a neighbor/MAC address table.  Populate it
# for every pair so each static next-hop route can resolve its destination MAC.
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

    set sent [$cbr($opt(sender_id),$opt(receiver_id)) getsentpkts]
    set received [$cbr($opt(receiver_id),$opt(sender_id)) getrecvpkts]

    if {$opt(verbose)} {
        puts "----------------------------------------"
        puts "Multi-hop optical TDMA simulation"
        puts "relay couples: $opt(n_relays)"
        puts "modem nodes: $opt(nn), hops: $opt(n_hops)"
        puts "hop length: $opt(hop_length) m, relay gap: $opt(relay_gap) m"
        puts "depth: $opt(depth) m"
        puts "TDMA frame: $opt(frame_duration) s, guard: $opt(guard_time) s"
        puts "attenuation c per hop: $opt(attenuation_c_per_hop) 1/m"
        puts "attenuation scale factor: $opt(attenuation_scale)"
        puts "sent packets: $sent"
        puts "received packets: $received"
        puts "per-hop MAC counters (sent received):"
        for {set id 0} {$id < $opt(nn)} {incr id} {
            puts "  modem $id: [$mac($id) get_sent_pkts] [$mac($id) get_recv_pkts]"
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

puts "Starting multi-hop optical TDMA simulation"
puts "Path has $opt(n_hops) hops and $opt(n_relays) relay couples"
$ns at [expr {$opt(stoptime) + $opt(frame_duration) + 1.0}] "finish; $ns halt"
$ns run
