# Rung 3 exerciser: drive the SGMII ethernet entirely over JTAG.
# Sequence: wait for link -> set MAC -> send ARP request for the host
# (192.168.0.106) from 192.168.0.51 -> poll RX -> dump the reply.
adapter driver ftdi
transport select jtag
ftdi vid_pid 0x0403 0x6010
ftdi channel 0
ftdi layout_init 0x0088 0x008b
adapter speed 2000
reset_config none
jtag newtap xc7 tap -irlen 6 -expected-id 0x03687093 -ignore-version
init
irscan xc7.tap 0x02

proc lbx {cmd addr data} {
    set req [expr {($data << 32) | ($addr << 8) | $cmd}]
    set r [drscan xc7.tap 72 $req]
    runtest 8
    return $r
}
# r is an 18-hex-digit string (72 bits), MSB first:
#   [hb:4][rd_cnt:2][rdata:8][status:2][sig:2]
proc field {r lo nbytes} {
    set hexlen [string length $r]
    set start [expr {$hexlen - ($lo + $nbytes) * 2}]
    return [string range $r $start [expr {$start + $nbytes*2 - 1}]]
}
proc sig {r}   { return [field $r 0 1] }
proc stat {r}  { return [field $r 1 1] }
proc rdata {r} { return [field $r 2 4] }
proc rdcnt {r} { return [field $r 6 1] }
proc eth_wr {addr data} { lbx 0x01 $addr $data; after 2 }
proc eth_rd {addr} {
    lbx 0x02 $addr 0
    after 2
    return 0x[rdata [lbx 0x00 0 0]]
}
proc eth_status {} {
    lbx 0x04 0 0
    after 2
    return 0x[string range [rdata [lbx 0x00 0 0]] 4 7]
}
proc flags {} { return 0x[stat [lbx 0x00 0 0]] }

echo "sig check: 0x[sig [lbx 0x00 0 0]] (want a5)"
echo "flags    : [flags] (bit0 locked, bit1 rst_n, bit3 link)"

# wait for SGMII link (autoneg ~up to 60s after configuration)
for {set i 0} {$i < 60} {incr i} {
    set st [eth_status]
    if {[expr {$st & 1}]} { break }
    after 1000
}
echo "pcspma   : $st (bit0 = link up)"

# eth_init: MAC 00:23:01:00:89:07
eth_wr 0x0800 0x01008907
eth_wr 0x0808 0x00000023
eth_wr 0x0828 31

# ARP request: who-has 192.168.0.106 tell 192.168.0.51
set frame {
  0xffffffff 0x2300ffff 0x07890001 0x01000608
  0x04060008 0x23000100 0x07890001 0x33000ac0
  0x00000000 0xc0000000 0x6a00a8
}
# (little-endian word packing of the 42-byte frame, padded)
set words {0xffffffff 0x0023ffff 0x00890107 0x06080100 0x00080106 0x01000604 0x01002300 0xc0078900 0x0033a8 0x00000000 0xa8c00000 0x6a00}
# build precisely instead: bytes LSB-first per 32-bit word
set bytes [list \
  0xff 0xff 0xff 0xff 0xff 0xff  0x00 0x23 0x01 0x00 0x89 0x07  0x08 0x06 \
  0x00 0x01 0x08 0x00 0x06 0x04 0x00 0x01 \
  0x00 0x23 0x01 0x00 0x89 0x07  0xc0 0xa8 0x00 0x33 \
  0x00 0x00 0x00 0x00 0x00 0x00  0xc0 0xa8 0x00 0x6a \
  0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00]
set n [llength $bytes]
for {set i 0} {$i < $n} {incr i 4} {
    set w 0
    for {set j 0} {$j < 4} {incr j} {
        if {[expr {$i + $j}] < $n} {
            set w [expr {$w | ([lindex $bytes [expr {$i + $j}]] << (8 * $j))}]
        }
    }
    eth_wr [expr {0x1000 + $i}] $w
}
# trigger send: TPLR = length (60 = min frame, no FCS)
eth_wr 0x0810 60
after 100
echo "tx done  : TPLR=[eth_rd 0x0810] (busy bit31 clear?)"

# poll RSR for a received frame
for {set i 0} {$i < 50} {incr i} {
    set rsr [eth_rd 0x0830]
    if {[expr {$rsr & 0x8000}]} { break }
    after 100
}
echo "rsr      : $rsr (bit15 = recv done)"
if {[expr {$rsr & 0x8000}]} {
    set b [expr {$rsr & 0x1F}]
    set len [eth_rd [expr {0x0C00 + ($b << 3)}]]
    echo "rx buf $b len=$len"
    set base [expr {0x10000 + ($b << 11)}]
    set dump ""
    for {set i 0} {$i < 48} {incr i 4} {
        append dump "[eth_rd [expr {$base + $i}]] "
    }
    echo "rx data  : $dump"
    # advance firstbuf
    eth_wr 0x0830 [expr {($b + 1) & 0x1F}]
}
shutdown
