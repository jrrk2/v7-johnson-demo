-- v7-johnson-demo: telegraph — output-path smoke test
--
-- Run from this directory with the top-level Makefile's invocation:
--     sv_suite.exe script recipe.lua
--
-- That writes top.json (consumed by nextpnr-xilinx) and top.edif
-- (golden-reference netlist) into this directory.  The Makefile then
-- drives the rest of the open-flow pipeline.

TOP    = "top"
CHILD  = "uarttest_core"
FILES  = {
    "uarttest_core.v",
    "top.v",
}
OUTDIR = "."

execute("mkdir -p " .. OUTDIR)

-- The recipe library is at a known path inside the SVS submodule.
-- Resolution order: an explicit SVS_ROOT env var (os.getenv is a native
-- binding in sv_suite's lua-ml), then the submodule path the Makefile
-- passes as the first script argument (ARGV[1]), then the in-tree
-- relative path for running by hand from this directory.
local svs_root = os.getenv("SVS_ROOT")
   or (ARGN and ARGN >= 1 and ARGV[1])
   or "../deps/System-Verilog-suite"

dofile(svs_root .. "/recipes/wrapped_inner_to_nextpnr.lua")
