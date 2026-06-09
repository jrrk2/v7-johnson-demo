-- Convert Vivado's PLACED echo EDIF to nextpnr JSON (cell names line up with
-- the placement map from vivado_place.tcl, for the locked route-only compare).
local edif = "/tmp/ue_placed.edif"
local prog = svd.read_edif_structural(edif)
print("  read edif: " .. svd.module_names(prog))
local flat = svd.flatten_struct(prog, "top")
local out  = svd.write_nextpnr_json(flat, "/tmp/ue_placed.json")
print("  wrote " .. out)
