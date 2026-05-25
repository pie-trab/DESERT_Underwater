#/bin/bash

# Run the client
# structure
# server ==> relay ==> client
#   1          2          3

# temporary: 
# server ==> client
#   1          3

# Usage:
#  
# ns test_uwlumax_application.tcl node_id dest_id start stop traffic_period modem_ip modem_port pkt_size ?UDP|TCP? ?bitrate_bps? ?tx_overhead_s? ?CLIENT|SERVER?"
# 
# Arguments:"
#   node_id        DESERT node/MAC/IP address of this node"
#   dest_id        DESERT destination node address"
#   start          application start time in seconds"
#   stop           application stop time in seconds"
#   traffic_period CBR packet period in seconds; use 0 for receive-only"
#   modem_ip       IP address of the local LumaX modem"
#   modem_port     socket port exposed by the local LumaX modem"
#   pkt_size       CBR payload size in bytes"
#   UDP|TCP        optional connector protocol, default UDP"
#   bitrate_bps    optional TX-duration estimate, default 0/unknown"
#   tx_overhead_s  optional fixed TX-duration overhead, default 0"
#   CLIENT|SERVER  optional socket role; SERVER is useful for local loopback tests"

ns test_uwlumax_application.tcl 3 1 5 60 5 "$MODEM_IP" "$MODEM_PORT" 16 "$PROTOCOL" 0 0 CLIENT
