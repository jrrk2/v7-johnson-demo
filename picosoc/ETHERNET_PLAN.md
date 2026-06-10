# Plan: SGMII gigabit ethernet on open-flow PicoSoC (VC707)

Goal: port the lowRISC ethernet stack from `~/cva6-ethernet` onto the
HW-verified open-flow PicoSoC, in two phases: (A) debug the integration in
the full Vivado flow, (B) port the build to yosys/nextpnr-xilinx.

## Source architecture (from ~/cva6-ethernet, HW-proven on VC707 under cva6)

```
framing_top_sgmii.sv        memory-mapped framing layer: 17-bit addr,
  |                          64-bit data + byte enables, ce/we/sel, irq;
  |                          dualmem_widen{,8} packet buffers, MDIO master
  +-- sgmii_soc.sv          AXIS <-> GMII adapter wrapper
        +-- eth_mac_1g.sv   Forencich MAC (axis_gmii_rx/tx, FCS)
        +-- gig_ethernet_pcs_pma_0   Xilinx IP: GTX + 8b/10b + PCS + SGMII
                                     autoneg; emits userclk2 = 125 MHz MAC clk
```
Pins (cva6 vc707.xdc): SGMII data AN2/AN1 + AM8/AM7 (GTX bank 117),
refclk AH8/AH7 (MGTREFCLK0, 125 MHz from 88E1111), MDIO/MDC, phy_reset_n.
The PHY is SGMII-only on VC707 — no RGMII fallback; the GTX is unavoidable.

NOTE: cva6-ethernet HEAD (9ddc46f4) removed the generated pcs_pma files;
regenerate from the .xci (corev_apu/fpga/xilinx/gig_ethernet_pcs_pma_0 in
git history, or work-fpga/gig_ethernet_pcs_pma_0.xci) with Vivado 2020.1.

## Phase A — Vivado bring-up (debug the integration, not the flow)

A1. New `ethsoc/` dir: copy picosoc base (vc707_picosoc.v, picosoc_noflash.v,
    picorv32.v, simpleuart.v, progmem flow) + cva6-ethernet RTL
    (framing_top_sgmii, sgmii_soc, eth_mac_1g, axis_gmii_*, dualmem_widen*)
    + regenerated pcs_pma IP.
A2. Bus shim: framing_top_sgmii is 64-bit; picosoc iomem is 32-bit.
    Thin adapter: addr[2] selects word half, wstrb->be, 64-bit rdata mux.
    Map at 0x0400_0000 (gpio stays at 0x03), eth_irq -> picosoc irq_5
    (ENABLE_IRQ already on). Keep the 64-bit core untouched — it is the
    HW-proven piece.
A3. Clocking: CPU stays on sysclk/2 = 100 MHz (msoc_clk). PCS/PMA gets its
    independent free-running clock from the same divider; refclk goes
    straight to the GT quad (dedicated path, no fabric). MAC domain
    userclk2 (125 MHz) comes out of the IP; framing_top already contains
    the CDC (dualmem buffers are dual-clock).
A4. Firmware: locate the lowRISC bare-metal framing driver (lowrisc-chip
    eth test / boot code) — register map is framing_top's own. Fallback:
    retarget the f4pga picosoc_demo ARP/ICMP/TFTP stack (minimal.c) to
    framing_top registers; same author lineage, fits in the 4096-word ROM.
    Milestone firmware: (1) MDIO read of PHY ID over UART, (2) promiscuous
    RX dump of LAN traffic over UART, (3) ARP responder, (4) ICMP ping.
A5. Vivado build script modeled on demo-projects/vc707_picosoc_sgmii tcl.
A6. HW verify with direct cable + tcpdump/ping from host. Capture a golden
    .bit + .dcp + routed fasm — these are the reference artifacts Phase B
    diffs against (same methodology that fixed rx and led[4]).

## Phase B — port to yosys/nextpnr-xilinx

B1. Synthesis: yosys reads all RTL fine (it is plain SV). The pcs_pma IP:
    use the Vivado *sim netlist* (funcsim, structural unisim) as yosys
    input with GTXE2_CHANNEL/GTXE2_COMMON/IBUFDS_GTE2 (and MMCM if the IP
    config uses one) as black boxes — same trick as uartram's xil_bb.v.
B2. nextpnr: chipdb already has GTXE2_CHANNEL (56) / GTXE2_COMMON (14) /
    IBUFDS_GTE2 (28) bels. Constrain the channel to the bank-117 quad
    site golden uses. Expect arch work: GT cell pin->bel-pin mapping,
    validity, and the userclk2 (TXOUTCLK->BUFG) route — the old
    HCLK_CMT_CK_IN0.MUX_CLK_8 blacklist may bite here; check which pips
    the golden fasm uses for TXOUTCLK first.
B3. Bitgen — the real blocker, two routes (evidence gathered 2026-06-10):
    * prjxray ALREADY HAS real GTX segbits (segbits_gtx_channel_*.db,
      1675 entries; segbits_gtx_common.db) and 120/168 GTX_INT_INTERFACE
      pips are pseudo-pips. What is missing is ONLY the tilegrid frame
      addresses: every GTX* tile has bits:{}.
    * Route 1 (fast): frame-splice the GT columns wholesale from the
      Phase-A golden bit (GT config is static for a fixed IP config and
      does not depend on fabric placement). Generalize patch_rx_iob.py
      into an address-range splicer in device-db-tools. Identify GT
      column addresses as: frames present in golden bitread output but
      absent from prjxray part coverage.
    * Route 2 (proper): fill the tilegrid bits for GT columns — derive
      baseaddr/offset from golden frame addresses (or run the 005-tilegrid
      fuzzer with GT specimens overnight, as for the CLB refuzz). Then
      fasm2frames assembles GT config natively from the existing segbits.
    Do Route 1 first to de-risk; promote to Route 2 once working.
B4. Debug ladder on HW, reusing this session's methodology: golden-vs-open
    raw frame diff per column; UART-side visibility via the working
    picosoc console; LED breadcrumbs for link/autoneg status
    (pcspma_status[0] = link_up on an LED).
B5. Seed sweep for timing (125 MHz MAC domain + 100 MHz CPU domain).
B6. Snapshot DB changes + FIXES.md entries; commit splicer into
    device-db-tools.

## Known risks, ranked

1. userclk2 clock route (TXOUTCLK -> BUFG) open-flow: HCLK_CMT pip
   blacklist territory. Mitigation: read golden fasm route first; the
   needed pips may differ from the broken CK_IN mux.
2. GTX_INT_INTERFACE non-ppip pips (48 of 168) with no tilegrid bits —
   if the fabric<->GT data routes need any of them, Route 1 must splice
   those columns too (they may share the GT column address space).
3. MMCM inside the IP (config-dependent): MMCM open-flow bits were the
   suspect in the old "358 missing CLBLM bits" experiment. Prefer an IP
   config without shared-logic MMCM (BUFG-only) if possible.
4. yosys vs the funcsim netlist (size, `assign` styles, unisim corner
   cases) — mechanical but possibly fiddly.
5. 64->32 shim subtleties (byte enables across the 64-bit regs).

## Milestones

M1 (Vivado): PHY ID over MDIO printed on UART.
M2 (Vivado): RX packet dump; ARP/ping answered. Golden artifacts captured.
M3 (open):   same firmware, open-flow bit with spliced GT columns: link up.
M4 (open):   ping over the fully open build. Stretch: TFTP boot a program
             into picosoc RAM over the network.
