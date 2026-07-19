F={"/home/jonathan/v7-johnson-demo/ethsoc/pcs_pma_flat.v"}
p=svd.parse("verible","gig_ethernet_pcs_pma_0",F)
b=svd.bir(svd.pick(p,"gig_ethernet_pcs_pma_0"))
-- print the header (params/signals) lines
print(strsub(b,1,600))
