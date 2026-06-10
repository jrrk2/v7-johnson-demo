// Bare-metal port of the lowRISC ethernet driver register interface
// (linux drivers/net/ethernet/lowrisc/lowrisc_100MHz.{c,h}) for picosoc.
//
// The hardware is 64-bit; picosoc's bus is 32-bit, so every 64-bit word
// is accessed as two 32-bit halves (low at +0, high at +4).  Registers
// hold their value in the low half; control writes only need the low
// word (the RTL gates register writes on be[3:0] all-set).
#ifndef ETH_H
#define ETH_H
#include <stdint.h>

#define ETH_BASE        0x04000000

#define TXBUFF_OFFSET   0x1000   /* Transmit buffer (4KB window)        */
#define MACLO_OFFSET    0x0800   /* MAC address low 32 bits             */
#define MACHI_OFFSET    0x0808   /* MAC high 16 bits + control          */
#define TPLR_OFFSET     0x0810   /* Tx packet length / busy (bit 31)    */
#define TFCS_OFFSET     0x0818   /* Tx FCS (read)                       */
#define MDIOCTRL_OFFSET 0x0820   /* MDIO bit-bang control               */
#define RFCS_OFFSET     0x0828   /* Rx FCS (read) / lastbuf (write)     */
#define RSR_OFFSET      0x0830   /* Rx status (read) / firstbuf (write) */
#define RPLR_OFFSET     0x0C00   /* Rx packet length array [32]         */
#define RXBUFF_OFFSET   0x10000  /* Receive buffers (32 x 2KB)          */

#define MACHI_COOKED_MASK     0x00010000
#define MACHI_LOOPBACK_MASK   0x00020000
#define MACHI_ALLPKTS_MASK    0x00400000   /* promiscuous */
#define MACHI_IRQ_EN          0x00800000

#define TPLR_BUSY_MASK        0x80000000

#define RSR_RECV_FIRST_MASK   0x0000001F
#define RSR_RECV_NEXT_MASK    0x000003E0
#define RSR_RECV_LAST_MASK    0x00007C00
#define RSR_RECV_DONE_MASK    0x00008000
#define RSR_RECV_IRQ_MASK     0x00010000

#define MDIO_MDCLK  0x1
#define MDIO_MDOUT  0x2
#define MDIO_MDOEN  0x4
#define MDIO_MDIN   0x8

static inline volatile uint32_t *eth_reg(uint32_t off) {
    return (volatile uint32_t *)(ETH_BASE + off);
}
static inline uint32_t eth_read(uint32_t off)            { return *eth_reg(off); }
static inline void     eth_write(uint32_t off, uint32_t v) { *eth_reg(off) = v; }

#endif
