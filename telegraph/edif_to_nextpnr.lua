-- Read Vivado's synthesized EDIF for `top` and emit nextpnr JSON, so the
-- open backend (nextpnr -> fasm -> bit) runs on Vivado's synthesis.  This
-- isolates SVS synthesis from the open backend: if this transmits but the
-- SVS-synth telegraph doesn't, SVS's FSM netlist is the bug.
local edif = "/tmp/telegraph_synth.edif"
local prog = svd.read_edif_structural(edif)
print("  read edif: " .. svd.module_names(prog))
local flat = svd.flatten_struct(prog, "top")
local out  = svd.write_nextpnr_json(flat, "/tmp/telegraph_edif.json")
print("  wrote " .. out)
