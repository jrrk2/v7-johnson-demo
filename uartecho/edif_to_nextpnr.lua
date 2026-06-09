-- Read Vivado's synthesized EDIF for the UART echo `top` and emit nextpnr JSON
-- for the open backend (nextpnr place+route -> fasm2frames -> bit).
local edif = "/tmp/uartecho_synth.edif"
local prog = svd.read_edif_structural(edif)
print("  read edif: " .. svd.module_names(prog))
local flat = svd.flatten_struct(prog, "top")
local out  = svd.write_nextpnr_json(flat, "/tmp/uartecho.json")
print("  wrote " .. out)
