# OpenTimer STA for open-flow xc7 designs

Open static timing analysis of a nextpnr/prjxray open-flow design, to find
critical paths the open flow can't check (nextpnr reports only single-edge
Fmax and treats hierarchy-port clock aliases as unrelated domains).

## Why prjxray SDF, not RapidWright
RapidWright ships a delay model for **UltraScale+ only**
(`timing/ultrascaleplus/*`); it has **no 7-series timing data**.  The real xc7
silicon cell timing lives in the prjxray SDF (`~/prjxray/database/virtex7/
timings/*.sdf`: FF setup/hold + clk->Q, LUT, CARRY4, BRAM, IO).  RapidWright's
role for xc7 is device node/pip *geometry* to scale interconnect (future
refinement of route2spef).

## Flow (`run_ot.sh <netlist_y.v> <top> <fasm> <clk_port> <period_ns> [pfx]`)
1. `sdf2lib.py`  -> `xc7fabric.lib`  : Liberty for the fabric cells, arc delays
   = prjxray SDF worst-case (slow) numbers.  Scalar NLDM; FF setup/hold use a
   `cst` template (constrained/related_pin_transition) -- a cap-based template
   is rejected by OpenTimer for constraints.
2. `netlist2ot.py` -> `<pfx>.v` + `.conn` : flattens the Vivado netlist
   (strip #()-params & (* *)-attrs, expand CARRY4 buses to scalar pins
   DI0..S3/O0..CO3, tie VCC/GND->const0/1, CUT MMCME2/IBUFDS/GTX/IOBUF so their
   fabric nets become primary inputs / clock sources).  Undriven used nets =
   primary inputs; OBUF outputs = primary outputs.
3. `route2spef.py` -> `<pfx>.spef` : per-net lumped interconnect delay via
   Elmore R*C (kohm*pf=ns), delay = (design-avg INT hops/net from the FASM pip
   census) x (avg per-hop, long lines 0.12 / ordinary 0.06 ns).  FIRST-ORDER
   (no per-net routing yet).
4. SDC (auto): create_clock + input slews on every PI (else OpenTimer slews =
   nan -> no paths) + loads/output_delay on POs.
5. OpenTimer: update_timing; report_wns/tns; report_timing.

## json2ot.py (preferred ingest -- flattened design)
The Vivado `write_verilog` netlist is HIERARCHICAL (`top` only has the top FSM;
the eth BRAM/MAC are in the `framing_top_sgmii` submodule).  Use the yosys/
nextpnr FLATTENED JSON instead: `json2ot.py /tmp/r0_ethloop.json el` reads the
4434-cell flattened design, auto-derives the Liberty from each cell's actual
`port_directions` (buses per-bit -> indexed pins), CUTs GT/PHY, and emits
`el.{v,lib,conn}`.  Sequential cells (FD*, RAMB, SRL) need an `ff()` group +
clk->Q arc; RAMD/RAMS/LUT/MUXF/CARRY4 are combinational (async LUTRAM read).

## Calibration from the golden Vivado database (realistic, not one-off)
A single `write_sdf` back-annotates delays for ONE load per net.  For the real
CHARACTERISTIC:
- `sdf_calibrate.py golden.sdf` (from `write_sdf` on the DCP) -> per-cell-family
  clk->Q / setup / hold / comb (SETUPHOLD-aware, ps->ns).  -> calib.json.
- `extract_char.tcl` + `char2calib.py arcs.tsv`: iterate **every placed timing
  arc** via `get_timing_arcs`, bulk-read `DELAY_SLOW_MAX_RISE` (slow corner) and
  `DELAY_FAST_MIN_RISE` (fast corner) + output-net fanout.  37k arcs -> per-type
  delay DISTRIBUTION vs load; use **p95** (worst realistic load).  Reveals e.g.
  LUT6 0.043->0.138ns across loads (3x), RAMB read flat 1.8ns, FDRE setup
  0.002->0.399ns.  Merged into calib.json (json2ot auto-applies).
- `netchar.py golden.sdf` -> routing-delay-vs-fanout from the 19842 SDF
  INTERCONNECT net delays (median 610ps, p95 2089ps, fit ~0.71+0.0015*fanout ns
  -- MUCH bigger than a per-hop guess).  -> netchar.json; route2spef auto-uses
  it (each open net gets the golden p95 delay for its fanout).  `write_spef` on
  the DCP also dumps the golden RC parasitics (golden_ethloop.spef).
Vivado commands for the model: `get_timing_arcs`+`report_property` (per-arc
delay at both corners/edges = load+slew-resolved), `report_timing -input_pins`
(per-node slew/ramp + net load), `write_sdf`/`write_spef` (annotated delays/RC).
Caveat: golden = Vivado ROUTING quality; the open nextpnr routing may be worse,
so netchar is a calibrated LOWER bound until the open routing is extracted.

## Status
- **PIPELINE BUILT + VALIDATED on uartstream (50MHz)**: real cell+interconnect
  delays, WNS +13.9 MET.  Full flow: sdf2lib/netlist2ot/route2spef/run_ot.sh.
- **ethloop ingests fully** (json2ot: 4434 cells, 22 types, auto-lib; clocks
  correctly typed RAMB->CLKARDCLK; cell delays compute -- FF clk->Q 0.235ns
  verified).  BLOCKED: full-chip report_timing = nan/no-path.  Root not yet
  found; leads: (a) userclk2 BUFG clock-propagation (clkout0 PI -> bufg_userclk2
  -> eth_clk -> FF.C shows nan arrival though cpu_clk's identical BUFG chain
  works -- possible OpenTimer multi-BUFG / long-name issue); (b) a complex-cell
  (RAMB/RAMD/SRL) output arc poisoning the TX-cone data arrival with nan;
  (c) CDC between cpu_clk(write) and userclk2(read) BRAM ports needing
  set_clock_groups -asynchronous (OpenTimer support?).  DEBUG: report_at on a
  known userclk2 FF:C and the RX-BRAM DOBDO; compare vs the working uartstream
  single-BUFG case.  SPEF also needs per-net *CONN fix (rctree "pin not found"
  warnings) -- run ideal (no read_spef) while debugging.
- **uartstream (50 MHz) VALIDATED**: full flow runs, real cell+interconnect
  delays (FF clk->Q 0.139 ns, OBUF 0.096 ns, clock-net 2.1 ns, data-net 1.0 ns),
  WNS +13.9 ns MET (expected -- it's a working design at 50 MHz).
- **ethloop TX cone (125 MHz) -- TODO**: needs cell models + bus-expansion for
  RAMB36E1 (20 pins incl wide ADDR/DI/DO buses; the TX buffer, central to the
  path), SRL16E/SRLC32E, RAM64M/RAM32M, and MUXF7/8 (MUXF done).  Add them to
  `FAB` in netlist2ot.py (with bus-expanded pins like CARRY4) and to sdf2lib
  (BRAM from BRAM_L.sdf RAMBFIFO36E1 CLK->DO + ADDR/DI setup).  Then run at 8 ns
  on userclk2, plus a 4 ns half-cycle check for the IS_CLKARDCLK_INVERTED port A.
  That yields the TX-cone reg->reg critical paths -- the open hold/timing test.
