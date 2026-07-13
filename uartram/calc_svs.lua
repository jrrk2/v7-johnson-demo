-- calc_svs.lua : SVS-native synthesis of the UART DSP calculator (no Vivado).
-- Per-module flow: gate-map each LEAF behavioral submodule, splice its
-- structural form back, then flatten_struct recurses top -> calc_inner ->
-- leaves, pulling all primitives up with vector-correct port rewriting.
-- (`top` and `calc_inner` are pure structural wrappers — not gate-mapped.)
--   run from uartram/:  MEMLOWER_FPGA=1 sv_suite.exe script calc_svs.lua <svs_dir>
--   BEST QOR (44->71 MHz, 5380 LUTs, routes clean):
--     BALANCED_CASE=1 GATE_MAP_AIG_BALANCE=3 GATE_MAP_MODE=mixed:2 GATE_MAP_LUTPACK=1
--   (BALANCED_CASE: parallel-tree lowering of provably-disjoint case arms;
--    GATE_MAP_AIG_BALANCE: AND-supergate depth balancing; mixed: timing-driven
--    cover.)  Still < board clock; MUXF7/8 mapping (task #10) is the next lever.
--   AVOID GATE_MAP_MODE=mixed + GATE_MAP_MFS2_VAR together (comb loop — task #9).
TOP = "top"
KLUT = 6                                  -- cover LUT size; k=7/8 -> MUXF7/8 cones
if os.getenv("KLUT") then KLUT = tonumber(os.getenv("KLUT")) end
FILES = {
    "calc_core.sv",
    "byte_fifo.sv",
    "lfsr_div.sv",
    "uart_rx_lfsr.sv",
    "uart_src/uart_transmitter.sv",
    "uart_src/slib_input_sync.sv",
    "top_min.sv",
}

print("== parse (verible-ext) ==")
prog = svd.parse("verible-ext", TOP, FILES)
print("  modules: " .. svd.module_names(prog))

print("== behavioral pipeline (NO inline; keep module boundaries) ==")
prog = svd.unroll(prog)
prog = svd.iflift(prog)
prog = svd.blocking_subst(prog)
prog = svd.meminfer(prog)
prog = svd.memlower(prog)
print("  pipeline done")

function mapsplice(name)
  print("  mapsplice " .. name)
  m = svd.gate_map(svd.pick(prog, name), KLUT, 0)
  prog = svd.splice(prog, name, svd.mapped_to_prog(m))
end

print("== gate_map + splice each LEAF submodule ==")
mapsplice("por_gen")
mapsplice("tx_drain")
mapsplice("slib_input_sync")
mapsplice("lfsr_div__W7_T96_S127_T119")
mapsplice("lfsr_div__W4_T12_S15_T9")
mapsplice("uart_rx_lfsr")
mapsplice("byte_fifo")
mapsplice("calc_core__A1")
mapsplice("uart_transmitter")

print("== flatten_struct (recurses top -> calc_inner -> leaves) + write ==")
flat = svd.flatten_struct(prog, TOP)
svd.write_nextpnr_json(flat, "/tmp/calc_svs.json")
svd.write_netlist_edif(flat, "/tmp/calc_svs.edif")
print("DONE")
