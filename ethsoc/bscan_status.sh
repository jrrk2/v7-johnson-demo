#!/bin/bash
# Read the ethsoc BSCANE2 USER1 debug register over JTAG (no UART needed).
# Layout: {hb[1:0], mmcm_locked, resetn, gpio[3:0], pcspma_status[15:0], 8'hA5}
v=$(openocd -f <(cat <<'CFG'
adapter driver ftdi
ftdi vid_pid 0x0403 0x6010
ftdi channel 0
ftdi layout_init 0x0088 0x008b
adapter speed 10000
transport select jtag
jtag newtap xc7 tap -irlen 6 -expected-id 0x03687093
init
irscan xc7.tap 0x02
set v [drscan xc7.tap 32 0]
echo "USER1_DR=$v"
shutdown
CFG
) 2>&1 | grep -oE "USER1_DR=[0-9a-f]+" | cut -d= -f2)
[ -z "$v" ] && { echo "JTAG read failed"; exit 1; }
python3 - "$v" <<'PY'
import sys
v = int(sys.argv[1], 16)
sig = v & 0xFF
st  = (v >> 8) & 0xFFFF
print(f"raw=0x{v:08x} sig=0x{sig:02x} {'OK' if sig==0xA5 else 'BAD CHAIN'}")
print(f"pcspma_status=0x{st:04x} link={'UP' if st&1 else 'DOWN'}")
print(f"gpio[3:0]={(v>>24)&0xF} resetn={(v>>28)&1} mmcm_locked={(v>>29)&1} hb={(v>>30)&3:02b}")
PY
