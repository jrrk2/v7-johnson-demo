# Exercise the loopback design over BSCAN USER1.
# 40-bit DR: shift {24'x, data[7:0], cmd[7:0]} LSB-first (cmd at [15:8] after capture layout);
# capture returns {hb, rx_cnt, rx_byte, status, A5}.
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
proc lbx {cmd data} {
    set req [expr {($cmd << 8) | $data}]
    set r 0x[drscan xc7.tap 40 $req]
    runtest 8
    return $r
}
proc decode {r} {
    set sig  [expr {$r & 0xFF}]
    set st   [expr {($r >> 8) & 0xFF}]
    set rxb  [expr {($r >> 16) & 0xFF}]
    set rxc  [expr {($r >> 24) & 0xFF}]
    set hb   [expr {($r >> 32) & 0xFF}]
    return [format "sig=%02x status=%02x rx_byte=%02x rx_cnt=%02x hb=%02x" $sig $st $rxb $rxc $hb]
}
echo "idle    : [decode [lbx 0x00 0x00]]"
echo "set-lb  : [decode [lbx 0x02 0x01]]"
echo "after-lb: [decode [lbx 0x00 0x00]]"
echo "tx 0x41 : [decode [lbx 0x01 0x41]]"
after 50
echo "settle  : [decode [lbx 0x00 0x00]]"
echo "pop rx  : [decode [lbx 0x03 0x00]]"
after 20
echo "result  : [decode [lbx 0x00 0x00]]  <- rx_byte should be 41"
echo "tx 0x5A : [decode [lbx 0x01 0x5A]]"
after 50
echo "pop rx  : [decode [lbx 0x03 0x00]]"
after 20
echo "result  : [decode [lbx 0x00 0x00]]  <- rx_byte should be 5a"
shutdown
