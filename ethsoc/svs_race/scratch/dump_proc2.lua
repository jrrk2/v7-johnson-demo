F = {"/home/jonathan/v7-johnson-demo/ethsoc/pcs_pma_flat.v"}
p = svd.parse("verible", "gig_ethernet_pcs_pma_0", F)
for _,mod in ipairs({"gig_ethernet_pcs_pma_0","gig_ethernet_pcs_pma_0_support"}) do
  print("===== "..mod.." =====")
  local b = svd.bir(svd.pick(p, mod))
  -- print only lines mentioning 'process' or assignment ':='
  print(b)
end
