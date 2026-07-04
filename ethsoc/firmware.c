// ethsoc M2 firmware: bare-metal port of the lowRISC lowrisc_100MHz.c
// driver semantics + ARP/ICMP-echo responder, packet log on the UART.
//
// rv32i only: no multiplies (shifts/adds), no libgcc, no memcpy.
#include <stdint.h>
#include "eth.h"

#define reg_uart_clkdiv (*(volatile uint32_t*)0x02000004)
#define reg_uart_data   (*(volatile uint32_t*)0x02000008)
#define reg_leds        (*(volatile uint32_t*)0x03000000)
#define reg_pcspma      (*(volatile uint32_t*)0x03000004)

// Our identity (MAC mirrors the RTL's reset default pattern)
static const uint8_t my_mac[6] = {0x00, 0x23, 0x01, 0x00, 0x89, 0x07};
static const uint8_t my_ip[4]  = {192, 168, 0, 51};

static void putchar_(char c) { reg_uart_data = c; }
static void print(const char *s) { while (*s) putchar_(*s++); }
static void print_hex(uint32_t v, int digits) {
    for (int i = (digits - 1) * 4; i >= 0; i -= 4)
        putchar_("0123456789abcdef"[(v >> i) & 0xF]);
}
static void print_dec(uint32_t v) {
    char b[10]; int i = 0;
    do {
        uint32_t q = 0, r = v;            // divide by 10 without mul/div
        while (r >= 10000) { r -= 10000; q += 1000; }
        while (r >= 1000)  { r -= 1000;  q += 100;  }
        while (r >= 100)   { r -= 100;   q += 10;   }
        while (r >= 10)    { r -= 10;    q += 1;    }
        b[i++] = '0' + r; v = q;
    } while (v && i < 10);
    while (i) putchar_(b[--i]);
}

// ------------------------------------------------------------------
//  Driver core (ported from lowrisc_100MHz.c)
// ------------------------------------------------------------------
static void eth_init(const uint8_t *mac) {
    // MACLO = htonl(mac[2..5]); MACHI = htons(mac[0..1])
    uint32_t lo = ((uint32_t)mac[2] << 24) | ((uint32_t)mac[3] << 16)
                | ((uint32_t)mac[4] << 8)  |  (uint32_t)mac[5];
    uint32_t hi = ((uint32_t)mac[0] << 8)  |  (uint32_t)mac[1];
    eth_write(MACLO_OFFSET, lo);
    eth_write(MACHI_OFFSET, hi);          // control bits clear: no promisc/irq
    eth_write(RFCS_OFFSET, 31);           // use all 32 rx buffers
}

static int eth_tx_busy(void) { return eth_read(TPLR_OFFSET) & TPLR_BUSY_MASK; }

static void eth_send(const uint8_t *data, int len) {
    while (eth_tx_busy()) ;
    // copy out as 32-bit words (the hw is 64-bit; halves at +0/+4)
    int words = (len + 3) >> 2;
    for (int i = 0; i < words; i++) {
        uint32_t w = (uint32_t)data[(i << 2) + 0]
                   | ((uint32_t)data[(i << 2) + 1] << 8)
                   | ((uint32_t)data[(i << 2) + 2] << 16)
                   | ((uint32_t)data[(i << 2) + 3] << 24);
        eth_write(TXBUFF_OFFSET + (i << 2), w);
    }
    eth_write(TPLR_OFFSET, len);
}

// returns length (>0) and fills buf if a frame is pending, else 0
static int eth_recv(uint8_t *buf, int maxlen) {
    uint32_t rsr = eth_read(RSR_OFFSET);
    if (!(rsr & RSR_RECV_DONE_MASK))
        return 0;
    uint32_t b = rsr & RSR_RECV_FIRST_MASK;
    int len = (int)eth_read(RPLR_OFFSET + (b << 3)) - 4;   // strip FCS
    if (len > 0) {
        int n = len < maxlen ? len : maxlen;
        uint32_t base = RXBUFF_OFFSET + (b << 11);          // 2KB per buffer
        for (int i = 0; i < n; i += 4) {
            uint32_t w = eth_read(base + i);
            buf[i] = w;
            if (i + 1 < n) buf[i + 1] = w >> 8;
            if (i + 2 < n) buf[i + 2] = w >> 16;
            if (i + 3 < n) buf[i + 3] = w >> 24;
        }
    }
    eth_write(RSR_OFFSET, b + 1);                           // acknowledge
    return len;
}

// ------------------------------------------------------------------
//  Minimal ARP + ICMP echo
// ------------------------------------------------------------------
static uint8_t pkt[1536];
static uint8_t out[1536];

static uint32_t csum_add(uint32_t s, const uint8_t *p, int n) {
    for (int i = 0; i + 1 < n; i += 2) s += ((uint32_t)p[i] << 8) | p[i + 1];
    if (n & 1) s += (uint32_t)p[n - 1] << 8;
    return s;
}
static uint16_t csum_fin(uint32_t s) {
    while (s >> 16) s = (s & 0xFFFF) + (s >> 16);
    return ~s & 0xFFFF;
}

static int ip_match(const uint8_t *p) {
    return p[0]==my_ip[0] && p[1]==my_ip[1] && p[2]==my_ip[2] && p[3]==my_ip[3];
}

static void handle_arp(int len) {
    // ARP request for our IP? (opcode 1, target = my_ip)
    if (len < 42 || pkt[20] != 0 || pkt[21] != 1) return;
    if (!ip_match(pkt + 38)) return;
    for (int i = 0; i < 6; i++) { out[i] = pkt[6 + i]; out[6 + i] = my_mac[i]; }
    out[12] = 0x08; out[13] = 0x06;
    out[14] = 0; out[15] = 1;        // htype
    out[16] = 8; out[17] = 0;        // ptype
    out[18] = 6; out[19] = 4;        // hlen/plen
    out[20] = 0; out[21] = 2;        // ARP reply
    for (int i = 0; i < 6; i++) out[22 + i] = my_mac[i];
    for (int i = 0; i < 4; i++) out[28 + i] = my_ip[i];
    for (int i = 0; i < 10; i++) out[32 + i] = pkt[22 + i];  // sender mac+ip
    eth_send(out, 42);
    print(" -> arp reply\r\n");
}

static void handle_icmp(int len) {
    int ihl = (pkt[14] & 0xF) << 2;
    if (pkt[23] != 1) return;                       // not ICMP
    if (!ip_match(pkt + 30)) return;                // not for us
    if (pkt[14 + ihl] != 8) return;                 // not echo request
    int iplen = ((int)pkt[16] << 8) | pkt[17];
    int n = 14 + iplen;
    if (n > len) n = len;
    for (int i = 0; i < n; i++) out[i] = pkt[i];
    for (int i = 0; i < 6; i++) { out[i] = pkt[6 + i]; out[6 + i] = my_mac[i]; }
    for (int i = 0; i < 4; i++) {                   // swap IP addrs
        out[26 + i] = pkt[30 + i];
        out[30 + i] = pkt[26 + i];
    }
    out[14 + ihl] = 0;                              // echo reply
    out[14 + ihl + 2] = 0; out[14 + ihl + 3] = 0;   // zero ICMP csum
    uint16_t c = csum_fin(csum_add(0, out + 14 + ihl, iplen - ihl));
    out[14 + ihl + 2] = c >> 8; out[14 + ihl + 3] = c;
    eth_send(out, n < 60 ? 60 : n);
    print(" -> echo reply\r\n");
}

// ------------------------------------------------------------------
//  MDIO bit-bang (kept as a diagnostic; the SGMII path doesn't need it)
// ------------------------------------------------------------------
static void mdio_delay(void) { for (volatile int i = 0; i < 30; i++) ; }
static void mdio_io(int oe, int o, int clk) {
    eth_write(MDIOCTRL_OFFSET, (oe ? MDIO_MDOEN : 0) | (o ? MDIO_MDOUT : 0)
                              | (clk ? MDIO_MDCLK : 0));
    mdio_delay();
}
static void mdio_bit_out(int b) { mdio_io(1, b, 0); mdio_io(1, b, 1); }
static int mdio_bit_in(void) {
    mdio_io(0, 0, 0);
    int b = (eth_read(MDIOCTRL_OFFSET) & MDIO_MDIN) ? 1 : 0;
    mdio_io(0, 0, 1);
    return b;
}
static uint16_t mdio_read(int phy, int reg) {
    int i;
    for (i = 0; i < 32; i++) mdio_bit_out(1);
    mdio_bit_out(0); mdio_bit_out(1);
    mdio_bit_out(1); mdio_bit_out(0);
    for (i = 4; i >= 0; i--) mdio_bit_out((phy >> i) & 1);
    for (i = 4; i >= 0; i--) mdio_bit_out((reg >> i) & 1);
    mdio_bit_in();
    uint16_t v = 0;
    for (i = 0; i < 16; i++) v = (v << 1) | mdio_bit_in();
    mdio_io(0, 0, 0);
    return v;
}

void main(void) {
    reg_leds = 1;
    reg_uart_clkdiv = 434;      // 115200 @ 50 MHz (single-domain MMCM build)
    reg_leds = 3;
    print("\r\nethsoc M2: ARP + ICMP echo at 192.168.0.51\r\n");

    eth_init(my_mac);

    // one-shot MDIO diagnostic (non-blocking for the data path)
    for (volatile int i = 0; i < 2500000; i++) ;
    int phy_found = 0;
    for (int a = 0; a < 32 && !phy_found; a++) {
        uint16_t id = mdio_read(a, 2);
        if (id != 0xFFFF && id != 0x0000) {
            print("mdio: phy at "); print_hex(a, 2);
            print(" id="); print_hex(id, 4);
            print_hex(mdio_read(a, 3), 4); print("\r\n");
            phy_found = 1;
        }
    }
    if (!phy_found) print("mdio: no phy (expected on SGMII; PCS/PMA autonegs)\r\n");

    uint32_t pkts = 0, last_status = ~0u;
    for (;;) {
        uint32_t st = reg_pcspma & 0xFFFF;
        if (st != last_status) {
            print("pcspma="); print_hex(st, 4);
            print(st & 1 ? " (link up)\r\n" : " (link DOWN)\r\n");
            last_status = st;
        }
        int len = eth_recv(pkt, sizeof(pkt));
        if (len <= 0) continue;
        pkts++;
        reg_leds = 3 | (pkts << 2);
        print("rx "); print_dec(len);
        print(" B ");
        for (int i = 0; i < 6; i++) { print_hex(pkt[6 + i], 2); if (i < 5) putchar_(':'); }
        print(" type ");
        print_hex(((uint32_t)pkt[12] << 8) | pkt[13], 4);
        if (pkt[12] == 0x08 && pkt[13] == 0x06) { handle_arp(len); continue; }
        if (pkt[12] == 0x08 && pkt[13] == 0x00) { handle_icmp(len); continue; }
        print("\r\n");
    }
}
