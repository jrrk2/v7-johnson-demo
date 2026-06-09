local prog = svd.read_edif_structural("/tmp/uartadd4_synth.edif")
print("  read edif: " .. svd.module_names(prog))
local flat = svd.flatten_struct(prog, "top")
print("  wrote " .. svd.write_nextpnr_json(flat, "/tmp/uartadd4.json"))
