F = {"/home/jonathan/v7-johnson-demo/ethsoc/pcs_pma_flat.v"}
p = svd.parse("verible", "gig_ethernet_pcs_pma_0", F)
-- the top PCS module has the status_vector const ties
print(svd.bir(svd.pick(p, "gig_ethernet_pcs_pma_0")))
