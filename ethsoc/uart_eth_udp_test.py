#!/usr/bin/env python3
# Sudo-free HW test of the vc707_ethloop processor-free eth<->UART bridge.
#
# TX proof (board -> wire): craft a real Ethernet+IPv4+UDP packet addressed to
# THIS host, hex-encode it, and inject it over the board UART.  The board's
# TX-load FSM writes it into the eth TX buffer and the MAC transmits it; the
# host kernel delivers the UDP payload to an ordinary socket -> recvfrom() sees
# it, no root needed.
#
# RX proof (wire -> board): sendto() a UDP broadcast; the board (promiscuous)
# receives the Ethernet frame and dumps it as hex on the UART -> read it back
# and find our payload.
#
#   ./uart_eth_udp_test.py [tty] [dst_ip] [src_ip]
import socket, struct, sys, time, os

TTY    = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB2"
DST_IP = sys.argv[2] if len(sys.argv) > 2 else "192.168.1.106"   # eno1
SRC_IP = sys.argv[3] if len(sys.argv) > 3 else "192.168.1.42"    # board-ish
DST_MAC = bytes.fromhex("1c697aabc6a6")   # eno1
SRC_MAC = bytes.fromhex("021122334455")
PORT    = 51234
PAYLOAD = b"ETHLOOP-TX-OK"

def ip_csum(hdr):
    s = 0
    for i in range(0, len(hdr), 2):
        s += (hdr[i] << 8) | hdr[i+1]
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF

def build_frame(payload, dst_mac, dst_ip):
    udp_len = 8 + len(payload)
    udp = struct.pack("!HHHH", 12345, PORT, udp_len, 0) + payload
    ip_total = 20 + udp_len
    ip = struct.pack("!BBHHHBBH4s4s", 0x45, 0, ip_total, 0, 0, 64, 17, 0,
                     socket.inet_aton(src_ip), socket.inet_aton(dst_ip))
    ip = ip[:10] + struct.pack("!H", ip_csum(ip)) + ip[12:]
    return dst_mac + SRC_MAC + b"\x08\x00" + ip + udp

src_ip = SRC_IP

# ---- TX proof ----
rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
rx.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
rx.bind(("0.0.0.0", PORT))
rx.settimeout(0.5)

frame = build_frame(PAYLOAD, DST_MAC, DST_IP)
hexline = frame.hex().upper() + "\n"
print(f"[tx] frame {len(frame)}B, dst_ip={DST_IP} dport={PORT}, payload={PAYLOAD!r}")
print(f"[tx] hex: {frame.hex().upper()}")

fd = os.open(TTY, os.O_WRONLY | os.O_NOCTTY)
got = False
for n in range(40):
    os.write(fd, hexline.encode())
    try:
        data, addr = rx.recvfrom(2048)
        if PAYLOAD in data:
            print(f"[tx] *** RECEIVED via UDP from {addr}: {data!r}  -> TX PATH WORKS ***")
            got = True
            break
    except socket.timeout:
        pass
os.close(fd)
if not got:
    print("[tx] no UDP packet received after 40 tries (20s) -> TX not confirmed")
sys.exit(0 if got else 1)
