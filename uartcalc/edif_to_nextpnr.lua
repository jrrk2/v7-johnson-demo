local edif = "/tmp/uartcalc_synth.edif"
local prog = svd.read_edif_structural(edif)
print("  read edif: " .. svd.module_names(prog))
local flat = svd.flatten_struct(prog, "top")
print("  wrote " .. svd.write_nextpnr_json(flat, "/tmp/uartcalc.json"))
