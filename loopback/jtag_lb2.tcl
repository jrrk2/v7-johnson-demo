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
    set r 0x[drscan xc7.tap 40 [expr {($cmd << 8) | $data}]]
    runtest 8
    return $r
}
proc decode {r} {
    return [format "sig=%02x status=%02x rd_byte=%02x rd_cnt=%02x hb=%02x" \
        [expr {$r & 0xFF}] [expr {($r >> 8) & 0xFF}] [expr {($r >> 16) & 0xFF}] \
        [expr {($r >> 24) & 0xFF}] [expr {($r >> 32) & 0xFF}]]
}
echo "idle       : [decode [lbx 0x00 0x00]]"
echo "gpio<=0xAA : [decode [lbx 0x05 0xAA]]"
after 50
echo "gpio read  : [decode [lbx 0x06 0x00]]"
after 20
echo "result     : [decode [lbx 0x00 0x00]]  <- rd_byte should be aa, LEDs 10101010"
echo "set-lb     : [decode [lbx 0x02 0x01]]"
echo "uart tx 41 : [decode [lbx 0x01 0x41]]"
after 50
echo "uart rx pop: [decode [lbx 0x03 0x00]]"
after 20
echo "result     : [decode [lbx 0x00 0x00]]  <- rd_byte should be 41"
echo "gpio<=0x55 : [decode [lbx 0x05 0x55]]"
after 50
echo "gpio read  : [decode [lbx 0x06 0x00]]"
after 20
echo "result     : [decode [lbx 0x00 0x00]]  <- rd_byte 55, LEDs 01010101"
shutdown
