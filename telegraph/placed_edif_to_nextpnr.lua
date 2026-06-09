-- Convert Vivado's PLACED netlist EDIF to nextpnr JSON.  Same as
-- edif_to_nextpnr.lua but reads the post-place EDIF so cell names line up
-- with the placement map dumped by vivado_place.tcl.
local edif = "/tmp/tg_placed.edif"
local prog = svd.read_edif_structural(edif)
print("  read edif: " .. svd.module_names(prog))
local flat = svd.flatten_struct(prog, "top")
local out  = svd.write_nextpnr_json(flat, "/tmp/tg_placed.json")
print("  wrote " .. out)
