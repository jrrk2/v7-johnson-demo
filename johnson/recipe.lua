-- v7-johnson-demo: slowed-LFSR 28-bit counter -> 8-bit Johnson -> 8 LEDs
--
-- Run from this directory with the top-level Makefile's invocation:
--     sv_suite.exe script recipe.lua
--
-- That writes top.json (consumed by nextpnr-xilinx) and top.edif
-- (golden-reference netlist) into this directory.  The Makefile
-- then drives the rest of the open-flow pipeline.

TOP    = "top"
CHILD  = "counter25_core"
FILES  = {
    "counter25_core.v",
    "top.v",
}
OUTDIR = "."

execute("mkdir -p " .. OUTDIR)

-- The recipe library is at a known path inside the SVS submodule.
local svs_root = os.getenv("SVS_ROOT")
   or (os.getenv("V7DEMO_ROOT") and (os.getenv("V7DEMO_ROOT") .. "/deps/System-Verilog-suite"))
   or (os.getenv("HOME") .. "/v7-johnson-demo/deps/System-Verilog-suite")

dofile(svs_root .. "/recipes/wrapped_inner_to_nextpnr.lua")
