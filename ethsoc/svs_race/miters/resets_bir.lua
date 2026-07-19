S="/home/jonathan/v7-johnson-demo/ethsoc/ip/gen/gig_ethernet_pcs_pma_0/synth/"
name="gig_ethernet_pcs_pma_0_resets"
p=svd.parse("verible",name,{S.."gig_ethernet_pcs_pma_0_resets.v"})
p=svd.unroll(p);p=svd.inline(p);p=svd.iflift(p);p=svd.blocking_subst(p)
print(svd.bir(svd.pick(p,name)))
