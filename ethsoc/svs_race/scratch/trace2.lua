F = {"/home/jonathan/v7-johnson-demo/ethsoc/pcs_pma_flat.v"}
function has(pp, mod)
  local ins = svd.insts(svd.pick(pp, mod))
  if strfind(ins, "SYNC_ASYNC_RESET_RECCLK", 1, 1) then return "PRESENT" else return "GONE" end
end
p = svd.parse("verible", "gig_ethernet_pcs_pma_0", F)
print("after parse  v16_2_0: " .. has(p, "gig_ethernet_pcs_pma_v16_2_0"))
p = svd.unroll(p)
print("after unroll v16_2_0: " .. has(p, "gig_ethernet_pcs_pma_v16_2_0"))
p = svd.inline(p)
print("after inline support: " .. has(p, "gig_ethernet_pcs_pma_0_support"))
p = svd.iflift(p)
print("after iflift support: " .. has(p, "gig_ethernet_pcs_pma_0_support"))
