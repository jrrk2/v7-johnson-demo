local prog = svd.read_edif_structural("/tmp/ua4_placed.edif")
print("  read edif: " .. svd.module_names(prog))
local flat = svd.flatten_struct(prog, "top")
print("  wrote " .. svd.write_nextpnr_json(flat, "/tmp/ua4_placed.json"))
