F = {"/home/jonathan/v7-johnson-demo/ethsoc/pcs_pma_flat.v"}
M = "gig_ethernet_pcs_pma_v16_2_0"
function has(pp) 
  local ins = svd.insts(svd.pick(pp, M))
  if strfind(ins, "SYNC_ASYNC_RESET_RECCLK", 1, 1) then return "PRESENT" else return "GONE" end
end
p = svd.parse("verible", "gig_ethernet_pcs_pma_0", F)
print("parse:        " .. has(p))
p = svd.unroll(p); p = svd.inline(p); p = svd.iflift(p)
print("iflift:       " .. has(p))
p = svd.blocking_subst(p); p = svd.meminfer(p); p = svd.memlower(p)
print("memlower:     " .. has(p))
g = svd.mapped_to_prog(svd.gate_map(svd.pick(p, M), 6, 0))
local gi = svd.insts(svd.pick(g, M))
if strfind(gi, "SYNC_ASYNC_RESET_RECCLK", 1, 1) then print("gate_map:     PRESENT") else print("gate_map:     GONE") end
