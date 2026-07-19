F = {"/home/jonathan/v7-johnson-demo/ethsoc/pcs_pma_flat.v"}
p = svd.parse("verible", "gig_ethernet_pcs_pma_0", F)
print(svd.bir(svd.pick(p, "gig_ethernet_pcs_pma_0_support")))
