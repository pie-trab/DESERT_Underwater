#
# Multi-hop underwater optical chain with dual-modem relay nodes (v3).
#
# WHY THIS FILE EXISTS
# --------------------
# v2 modelled every relay as ONE optical modem with a single head that both
# received from its predecessor and transmitted to its successor.  That is a
# convenient abstraction, but a narrow-beam optical head cannot physically
# point at two opposite neighbours at once.  A real optical relay is a box
# with TWO modems (heads): an upstream-facing receiver and a
# downstream-facing transmitter.  v3 models that hardware explicitly.
#
# TOPOLOGY
# --------
#   source -> [ relay 1 ] -> [ relay 2 ] -> ... -> [ relay n ] -> sink
#
# Every relay is ONE DESERT M_Node (one IP address, one routing table) but it
# owns TWO independent modem stacks:
#
#                 +-----------------------------+
#                 |  UW/STATICROUTING           |
#                 |  UW/IP                      |
#                 |  UW/MULTI_DESTINATION       |
#                 +-----------+-----------------+
#                             |
#              +--------------+--------------+
#              |                             |
#         UW/MLL (up)                 UW/MLL (down)
#         UW/TDMA  head 0             UW/TDMA  head 1
#         UW/OPTICAL/PHY              UW/OPTICAL/PHY
#         face = upstream             face = downstream
#
# The upstream head only receives.  The downstream head only transmits.  The
# UW/MULTI_DESTINATION module (DESERT_Addons/uwmulti_destination) hands every
# packet coming up from either head to the shared IP layer, and every packet
# coming down from IP to the downstream head.  The relay hand-over is an
# internal IP forwarding operation: it is NOT re-transmitted through water
# and it does NOT consume an extra optical hop.
#
# TDMA
# ----
# Only modems that transmit need a slot.  The source and the n downstream
# relay heads own slots 0..n.  The sink gets a dummy slot n + 1 and the n
# upstream heads get dummy slot 0, because none of them ever transmits.  The
# frame therefore has (n + 2) slots, exactly as in v2.  The pipeline is:
#
#   source slot 0 -> relay 1 upstream RX -> IP forwarding ->
#   relay 1 downstream TX in slot 1 -> relay 2 upstream RX -> ...
#   -> relay n downstream TX in slot n -> sink RX
#
# This reproduces v2's one-slot-per-water-hop schedule with twice the modem
# hardware.  The two heads of a relay are never active at the same time, so
# the simulator's PHY half-duplex constraint is respected without any extra
# guard.  Full-duplex relaying (receiving and transmitting in the same slot)
# is deliberately NOT claimed: the plain optical model has no head-direction
# isolation, so concurrent co-located heads would interfere at distance zero.
#
# RUNNING
# -------
#   source <DESERT_build>/environment
#   ns optical_chain_dual.tcl \
#       n_relays cbr_period packet_size hop_length depth stop_time \
#       rngstream poisson_traffic attenuation_scale optical_txpower \
#       optical_acq_threshold_db optical_theta [ambient_il [guard_time]]
#
# The argument list is identical to v2's optical_chain.tcl.  The runner
# derives hop_length = total_distance / (n_relays + 1).
#

################################
# User-changeable parameters    #
################################

# Traffic and schedule.
set opt(starttime)          0.1       ;# s: sender application start time
set opt(stoptime)           1000.0    ;# s: sender application stop time
set opt(cbr_period)         0.25      ;# s: mean inter-packet time (Poisson)
set opt(pktsize)            125       ;# byte: application payload
set opt(poisson_traffic)    1         ;# 0=periodic CBR, 1=Poisson CBR
set opt(rngstream)          1         ;# RNG substream (one per repetition)

# Topology.  n_relays is the number of relay BOXES, not modem nodes.
set opt(n_relays)           1         ;# relay boxes with two heads each
set opt(hop_length)         50.0      ;# m: distance between physical nodes
set opt(depth)              -10.0     ;# m: shared depth of every modem

# Water channel (analytic fixed c; identity for CLI runs).
set opt(attenuation_c_default) 0.3    ;# 1/m: clear-water reference
set opt(attenuation_scale)  1.0       ;# multiplicative scale for sweeps

# Optical physical-layer parameters.
set opt(freq)               7.59e14       ;# Hz: blue-light carrier
set opt(bw)                 1000000       ;# Hz: signal bandwidth
set opt(bitrate)            1000000       ;# bit/s
set opt(txpower)            10.0          ;# W: optical transmit power
set opt(acq_threshold_db)   15.0          ;# dB: acquisition threshold
set opt(theta)              0.524         ;# rad: beam half-divergence
set opt(id)                 1.0e-9        ;# A: photodiode dark current
set opt(il)                 1.0e-6        ;# A: ambient background photocurrent
set opt(shunt_resistance)   1.49e9        ;# ohm: receiver shunt resistance
set opt(sensitivity)        0.26          ;# A/W: photodiode sensitivity
set opt(temperature)        313.15        ;# K: receiver temperature
set opt(rx_area)            330.06e-6     ;# m^2: receiver aperture area
set opt(tx_area)            36e-6         ;# m^2: transmitter aperture area

# TDMA parameters.
set opt(frame_duration)     0.1           ;# s: replaced by derived frame
set opt(auto_frame_duration) 1
set opt(guard_time)         0.001         ;# s: common fixed TDMA guard
set opt(max_packet_per_slot) 1            ;# packets per modem per slot
set opt(queue_size)         32            ;# packets buffered per modem
set opt(drop_old_)          0             ;# drop the newly arriving packet

# Diagnostics and traces.
set opt(verbose)            1
set opt(debug)              0
set opt(trace_files)        0
set opt(trace_prefix)       "multi_hop_optical_dual"
set opt(maxinterval)        1.0           ;# s: interference history window

################################
# Optional command-line values  #
################################

if {$argc > 0} {
    if {$argc != 12 && $argc != 13 && $argc != 14} {
        puts "Usage: ns optical_chain_dual.tcl n_relays cbr_period packet_size hop_length depth stop_time rngstream poisson_traffic attenuation_scale txpower acq_threshold_db theta \[ambient_il \[guard_time\]\]"
        exit 1
    }
    set opt(n_relays)         [lindex $argv 0]
    set opt(cbr_period)       [lindex $argv 1]
    set opt(pktsize)          [lindex $argv 2]
    set opt(hop_length)       [lindex $argv 3]
    set opt(depth)            [lindex $argv 4]
    set opt(stoptime)         [lindex $argv 5]
    set opt(rngstream)        [lindex $argv 6]
    set opt(poisson_traffic)  [lindex $argv 7]
    set opt(attenuation_scale) [lindex $argv 8]
    set opt(txpower)          [lindex $argv 9]
    set opt(acq_threshold_db) [lindex $argv 10]
    set opt(theta)            [lindex $argv 11]
    if {$argc >= 13} {
        set opt(il)           [lindex $argv 12]
    }
    if {$argc == 14} {
        set opt(guard_time)   [lindex $argv 13]
    }
}

# Physical nodes: source + relay boxes + sink.  Modems: one per endpoint plus
# two per relay box.
set opt(nn)            [expr {$opt(n_relays) + 2}]
set opt(n_modems)      [expr {2 * $opt(n_relays) + 2}]
set opt(sender_id)     0
set opt(receiver_id)   [expr {$opt(nn) - 1}]
set opt(n_hops)        [expr {$opt(nn) - 1}]
set opt(n_tx_slots)    [expr {$opt(n_relays) + 2}]

# Unique MAC addresses: 1 = source, 2i/2i+1 = relay i upstream/downstream,
# 2n+2 = sink.  Every node's *ingress* MAC is the one the previous node
# targets, so the ARP tables map node IP -> ingress MAC.
proc ingressMac {id} {
    global opt
    if {$id == 0} {
        return 1
    } elseif {$id == $opt(receiver_id)} {
        return [expr {2 * $opt(n_relays) + 2}]
    } else {
        return [expr {2 * $id}]
    }
}

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
load libuwmll.so
load libuwudp.so
load libuwcbr.so
load libuwtdma.so
load libuwem_channel.so
load libuwoptical_propagation.so
load libuwoptical_channel.so
load libuwoptical_phy.so
load libuwmulti_destination.so
# Data-quality workaround inherited from v2: libuwopticalbeampattern is
# loaded even in plain mode because DESERT's packet-header binding order
# otherwise lets another module overwrite hdr_uwcbr::sn with a per-transmission
# counter.  The plain optical PHY is still the one instantiated below.
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

Module/UW/CBR set packetSize_     $opt(pktsize)
Module/UW/CBR set period_         $opt(cbr_period)
Module/UW/CBR set PoissonTraffic_ $opt(poisson_traffic)
Module/UW/CBR set debug_          $opt(debug)

# tot_slots counts transmitting modems plus the sink's dummy slot:
# source + n downstream relay heads + sink = n + 2.
Module/UW/TDMA set frame_duration      $opt(frame_duration)
Module/UW/TDMA set guard_time          $opt(guard_time)
Module/UW/TDMA set tot_slots           $opt(n_tx_slots)
Module/UW/TDMA set fair_mode           1
Module/UW/TDMA set max_packet_per_slot $opt(max_packet_per_slot)
Module/UW/TDMA set queue_size_         $opt(queue_size)
Module/UW/TDMA set drop_old_           $opt(drop_old_)
Module/UW/TDMA set sea_trial_          0
Module/UW/TDMA set mac2phy_delay_      [expr {1.0e-9}]
Module/UW/TDMA set debug_              $opt(debug)

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

# One shared optical channel: TDMA prevents simultaneous transmissions and
# the MAC destination field discards packets heard by non-destined modems.
set channel [new Module/UW/Optical/Channel]
set data_mask [new MSpectralMask/Rect]
$data_mask setFreq      $opt(freq)
$data_mask setBandwidth $opt(bw)

################################
# Node-construction procedures #
################################

# Create one optical modem head below an already-created MLL.  Each head is
# a complete UW/TDMA + optical PHY stack with its own MAC address and slot.
proc addOpticalHead {node_id face mac_addr slot_id} {
    global ns channel opt node mac phy propagation interf_data data_mask

    set mac($node_id,$face) [new Module/UW/TDMA]
    set phy($node_id,$face) [new Module/UW/OPTICAL/PHY]
    $node($node_id) addModule 2 $mac($node_id,$face) 1 "MAC"
    $node($node_id) addModule 1 $phy($node_id,$face) 1 "PHY"
    $node($node_id) setConnection $mac($node_id,$face) $phy($node_id,$face) 1
    $node($node_id) addToChannel $channel $phy($node_id,$face) 1

    # Propagation object dedicated to this receiving modem.  c is the same
    # analytic fixed-c water model as v2; the two heads of a relay are
    # colocated, so there is no synthetic intra-relay water gap.
    set propagation($node_id,$face) [new Module/UW/OPTICAL/Propagation]
    $propagation($node_id,$face) setAr    $opt(rx_area)
    $propagation($node_id,$face) setAt    $opt(tx_area)
    $propagation($node_id,$face) setTheta $opt(theta)
    $propagation($node_id,$face) setC [expr {$opt(attenuation_c_default) * $opt(attenuation_scale)}]
    $propagation($node_id,$face) setFixedC
    $propagation($node_id,$face) set debug_ $opt(debug)
    $phy($node_id,$face) setPropagation $propagation($node_id,$face)

    set interf_data($node_id,$face) [new MInterference/MIV]
    $interf_data($node_id,$face) set maxinterval_ $opt(maxinterval)
    $interf_data($node_id,$face) set debug_ $opt(debug)
    $phy($node_id,$face) setInterference $interf_data($node_id,$face)
    $phy($node_id,$face) setSpectralMask $data_mask

    $mac($node_id,$face) setMacAddr $mac_addr
    $mac($node_id,$face) setSlotNumber $slot_id
}

# Standard single-head endpoint: CBR -> UDP -> StaticRouting -> IP -> MLL
# -> one MAC/PHY.  face is "down" for the source and "up" for the sink.
proc createEndpoint {node_id face mac_addr slot_id} {
    global ns channel opt node cbr udp ipr ipif mll mac phy
    global propagation interf_data data_mask portnum

    set node($node_id) [$ns create-M_Node $opt(tracefile) $opt(cltracefile)]
    set cbr($node_id)  [new Module/UW/CBR]
    set udp($node_id)  [new Module/UW/UDP]
    set ipr($node_id)  [new Module/UW/StaticRouting]
    set ipif($node_id) [new Module/UW/IP]
    set mll($node_id)  [new Module/UW/MLL]

    $node($node_id) addModule 8 $cbr($node_id)  1 "CBR"
    $node($node_id) addModule 7 $udp($node_id)  1 "UDP"
    $node($node_id) addModule 6 $ipr($node_id)  1 "IPR"
    $node($node_id) addModule 5 $ipif($node_id) 1 "IPF"
    $node($node_id) addModule 3 $mll($node_id)  1 "MLL"
    addOpticalHead $node_id $face $mac_addr $slot_id

    set portnum($node_id) [$udp($node_id) assignPort $cbr($node_id)]
    $node($node_id) setConnection $cbr($node_id) $udp($node_id) 0
    $node($node_id) setConnection $udp($node_id) $ipr($node_id) 1
    $node($node_id) setConnection $ipr($node_id) $ipif($node_id) 1
    $node($node_id) setConnection $ipif($node_id) $mll($node_id) 1
    $node($node_id) setConnection $mll($node_id) $mac($node_id,$face) 1

    $ipif($node_id) addr [expr {$node_id + 1}]

    set position($node_id) [new Position/BM]
    $node($node_id) addPosition $position($node_id)
    $position($node_id) setX_ 0.0
    $position($node_id) setY_ [expr {$node_id * $opt(hop_length)}]
    $position($node_id) setZ_ $opt(depth)
}

# Dual-head relay box: one IP/static-routing stack, one MULTI_DESTINATION
# controller, two MLL/MAC/PHY head pairs.  The controller sends every
# downstream packet to the downstream head by construction, and every
# received packet up to the shared IP layer.
proc createDualRelay {node_id} {
    global ns channel opt node udp ipr ipif ctr mll mac phy
    global propagation interf_data data_mask position

    set node($node_id) [$ns create-M_Node $opt(tracefile) $opt(cltracefile)]
    set udp($node_id)  [new Module/UW/UDP]
    set ipr($node_id)  [new Module/UW/StaticRouting]
    set ipif($node_id) [new Module/UW/IP]
    set ctr($node_id)  [new Module/UW/MULTI_DESTINATION]
    set mll($node_id,up)   [new Module/UW/MLL]
    set mll($node_id,down) [new Module/UW/MLL]

    $node($node_id) addModule 7 $udp($node_id)  1 "UDP"
    $node($node_id) addModule 6 $ipr($node_id)  1 "IPR"
    $node($node_id) addModule 5 $ipif($node_id) 1 "IPF"
    $node($node_id) addModule 4 $ctr($node_id)  1 "CTR"
    $node($node_id) addModule 3 $mll($node_id,up)   1 "MLL_UP"
    $node($node_id) addModule 3 $mll($node_id,down) 1 "MLL_DOWN"

    # Upstream head: ingress only, dummy slot 0 (it never transmits).
    # Downstream head: egress only, slot = node index (1..n).
    addOpticalHead $node_id up   [expr {2 * $node_id}]     0
    addOpticalHead $node_id down [expr {2 * $node_id + 1}] $node_id

    $node($node_id) setConnection $udp($node_id)  $ipr($node_id)  1
    $node($node_id) setConnection $ipr($node_id)  $ipif($node_id) 1
    $node($node_id) setConnection $ipif($node_id) $ctr($node_id)  1
    $node($node_id) setConnection $ctr($node_id)  $mll($node_id,up)   1
    $node($node_id) setConnection $ctr($node_id)  $mll($node_id,down) 1
    $node($node_id) setConnection $mll($node_id,up)   $mac($node_id,up)   1
    $node($node_id) setConnection $mll($node_id,down) $mac($node_id,down) 1

    # All downstream traffic leaves through the downstream head.  Incoming
    # packets from either head are passed up to IP by the controller.
    $ctr($node_id) setManualLowerlId [$mll($node_id,down) Id_]

    $ipif($node_id) addr [expr {$node_id + 1}]

    set position($node_id) [new Position/BM]
    $node($node_id) addPosition $position($node_id)
    $position($node_id) setX_ 0.0
    $position($node_id) setY_ [expr {$node_id * $opt(hop_length)}]
    $position($node_id) setZ_ $opt(depth)
}

for {set id 0} {$id < $opt(nn)} {incr id} {
    if {$id == $opt(sender_id)} {
        createEndpoint $id down 1 0
    } elseif {$id == $opt(receiver_id)} {
        createEndpoint $id up [ingressMac $id] [expr {$opt(nn) - 1}]
    } else {
        createDualRelay $id
    }
}

set effective_phy_class [$phy(0,down) info class]
set effective_channel_class [$channel info class]
set effective_propagation_class [$propagation(1,up) info class]
puts "EFFECTIVE optical: topology=dual_head phy_class=$effective_phy_class channel_class=$effective_channel_class propagation_class=$effective_propagation_class bitrate=$opt(bitrate) txpower=$opt(txpower) acquisition_db=$opt(acq_threshold_db) theta=$opt(theta) attenuation_c=[expr {$opt(attenuation_c_default) * $opt(attenuation_scale)}] relay_boxes=$opt(n_relays) modems=$opt(n_modems)"

# Derive one TDMA slot from the complete simulated protocol packet and the
# worst-case one-hop optical propagation time.  Same rule and same guard as
# v2; the water hop is hop_length, not the (zero) intra-relay distance.
set opt(cbr_header_bytes) [$cbr(0) getcbrheadersize]
set opt(udp_header_bytes) [$udp(0) getudpheadersize]
set opt(ip_header_bytes)  [$ipif(0) getipheadersize]
set opt(header_bytes) [expr {$opt(cbr_header_bytes) +
    $opt(udp_header_bytes) + $opt(ip_header_bytes)}]
set opt(packet_bytes) [expr {$opt(pktsize) + $opt(header_bytes)}]
set opt(airtime) [expr {8.0 * $opt(packet_bytes) / $opt(bitrate)}]
set opt(packet_time) $opt(airtime)
set opt(propagation_speed) 225000000.0
set opt(propagation_delay) [expr {$opt(hop_length) /
    $opt(propagation_speed)}]
set opt(slot_duration) [expr {$opt(airtime) + $opt(propagation_delay) +
    $opt(guard_time)}]
set opt(frame_duration) [expr {$opt(n_tx_slots) * $opt(slot_duration)}]
for {set id 0} {$id < $opt(nn)} {incr id} {
    if {$id == $opt(sender_id) || $id == $opt(receiver_id)} {
        set face [expr {$id == $opt(sender_id) ? "down" : "up"}]
        $mac($id,$face) set frame_duration $opt(frame_duration)
    } else {
        $mac($id,up)   set frame_duration $opt(frame_duration)
        $mac($id,down) set frame_duration $opt(frame_duration)
    }
}
set opt(sim_end) [expr {$opt(stoptime)
    + ($opt(n_hops) + 2) * $opt(frame_duration) + 0.5}]
puts "TDMA timing: technology=optical_dual relay_boxes=$opt(n_relays) physical_nodes=$opt(nn) modems=$opt(n_modems) tdma_slots=$opt(n_tx_slots) water_hops=$opt(n_hops) header_bytes=$opt(header_bytes) packet_bytes=$opt(packet_bytes) airtime_s=$opt(airtime) propagation_s=$opt(propagation_delay) guard_s=$opt(guard_time) slot_s=$opt(slot_duration) frame_s=$opt(frame_duration)"

################################
# Configure CBR and addresses  #
################################

# Only the two endpoints run an application.
$cbr($opt(sender_id)) set destAddr_ [$ipif($opt(receiver_id)) addr]
$cbr($opt(sender_id)) set destPort_ $portnum($opt(receiver_id))
$cbr($opt(receiver_id)) set destAddr_ [$ipif($opt(sender_id)) addr]
$cbr($opt(receiver_id)) set destPort_ $portnum($opt(sender_id))

# MLL next-hop resolution.  Every transmitting MLL maps every physical
# node's IP to that node's INGRESS MAC (the head that receives the packet).
# Upstream relay MLLs never transmit, but populating them is harmless and
# keeps the example reusable.
for {set src 0} {$src < $opt(nn)} {incr src} {
    set mlls {}
    if {$src == $opt(sender_id) || $src == $opt(receiver_id)} {
        lappend mlls $mll($src)
    } else {
        lappend mlls $mll($src,up) $mll($src,down)
    }
    foreach m $mlls {
        for {set dst 0} {$dst < $opt(nn)} {incr dst} {
            # Every node IP resolves to the ingress head that receives for
            # it.  The node's own entry is harmless and avoids an ARP miss
            # if a local delivery ever targets it.
            $m addentry [$ipif($dst) addr] [ingressMac $dst]
        }
    }
}

################################
# Install the forced IP path   #
################################

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
    if {$id == $opt(sender_id) || $id == $opt(receiver_id)} {
        set face [expr {$id == $opt(sender_id) ? "down" : "up"}]
        $ns at 0.0 "$mac($id,$face) start"
        $ns at $opt(sim_end) "$mac($id,$face) stop"
    } else {
        $ns at 0.0 "$mac($id,up) start"
        $ns at 0.0 "$mac($id,down) start"
        $ns at $opt(sim_end) "$mac($id,up) stop"
        $ns at $opt(sim_end) "$mac($id,down) stop"
    }
}
$ns at $opt(starttime) "$cbr($opt(sender_id)) start"
$ns at $opt(stoptime)  "$cbr($opt(sender_id)) stop"

################################
# End-of-run metrics block     #
################################

# Machine-readable summary parsed by the v3 runner.  Semantics:
#   sent_packets     CBR packets generated at the source
#   received_packets CBR packets delivered to the sink
#   modem lines: one per physical optical modem (head)
#     tx      : transmissions handed down to the PHY
#     rx      : packets whose MAC destination is this modem
#     up_rx   : packets the IP layer handed down to this MAC
#     q       : residual MAC queue at stop
proc finish {} {
    global ns opt cbr mac

    set sent     [$cbr($opt(sender_id)) getsentpkts]
    set received [$cbr($opt(receiver_id)) getrecvpkts]

    puts "=== METRICS v3 ==="
    puts "sim_topology: dual_head"
    puts "sim_relay_boxes: $opt(n_relays)"
    puts "sim_physical_nodes: $opt(nn)"
    puts "sim_modems: $opt(n_modems)"
    puts "sim_water_hops: $opt(n_hops)"
    puts "sim_tdma_slots: $opt(n_tx_slots)"
    puts "sim_hop_length_m: $opt(hop_length)"
    puts "sim_packet_time_s: $opt(packet_time)"
    puts "sim_frame_duration_s: $opt(frame_duration)"
    puts "sent_packets: $sent"
    puts "received_packets: $received"
    puts "ftt_mean_s: [$cbr($opt(receiver_id)) getftt]"
    puts "ftt_std_s: [$cbr($opt(receiver_id)) getfttstd]"
    puts "cbr_thr_bps: [$cbr($opt(receiver_id)) getthr]"
    puts "modem_stats:"
    set modem_id 0
    for {set id 0} {$id < $opt(nn)} {incr id} {
        if {$id == $opt(sender_id)} {
            puts "  modem $modem_id node=$id face=down mac=[$mac($id,down) addr] tx=[$mac($id,down) get_sent_pkts] rx=[$mac($id,down) get_recv_pkts] up_rx=[$mac($id,down) get_upper_data_pkts_rx] q=[$mac($id,down) get_buffer_size]"
            incr modem_id
        } elseif {$id == $opt(receiver_id)} {
            puts "  modem $modem_id node=$id face=up mac=[$mac($id,up) addr] tx=[$mac($id,up) get_sent_pkts] rx=[$mac($id,up) get_recv_pkts] up_rx=[$mac($id,up) get_upper_data_pkts_rx] q=[$mac($id,up) get_buffer_size]"
            incr modem_id
        } else {
            puts "  modem $modem_id node=$id face=up mac=[$mac($id,up) addr] tx=[$mac($id,up) get_sent_pkts] rx=[$mac($id,up) get_recv_pkts] up_rx=[$mac($id,up) get_upper_data_pkts_rx] q=[$mac($id,up) get_buffer_size]"
            incr modem_id
            puts "  modem $modem_id node=$id face=down mac=[$mac($id,down) addr] tx=[$mac($id,down) get_sent_pkts] rx=[$mac($id,down) get_recv_pkts] up_rx=[$mac($id,down) get_upper_data_pkts_rx] q=[$mac($id,down) get_buffer_size]"
            incr modem_id
        }
    }
    puts "=== END ==="

    $ns flush-trace
    close $opt(tracefile)
    close $opt(cltracefile)
}

################################
# Run the simulation           #
################################

puts "Starting dual-head multi-hop optical chain (v3)"
puts "Path has $opt(n_hops) water hops, $opt(n_relays) dual-head relay boxes"
$ns at [expr {$opt(sim_end) + 1.0}] "finish; $ns halt"
$ns run
