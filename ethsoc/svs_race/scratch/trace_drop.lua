local F = {"/home/jonathan/v7-johnson-demo/ethsoc/pcs_pma_flat.v"}
local p = svd.parse("verible", "gig_ethernet_pcs_pma_0", F)
p = svd.unroll(p); p=svd.inline(p); p=svd.iflift(p)
p = svd.blocking_subst(p); p=svd.meminfer(p); p=svd.memlower(p)
-- after memlower, before gate_map: is SYNC_ASYNC_RESET_RECCLK still here?
local ins = svd.insts(svd.pick(p, "gig_ethernet_pcs_pma_0_support"))
if strfind(ins, "SYNC_ASYNC_RESET_RECCLK", 1, 1) then print("PRE-GATEMAP: RECCLK reset FF PRESENT")
else print("PRE-GATEMAP: RECCLK reset FF ALREADY GONE") end
