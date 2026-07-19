S = "/home/jonathan/v7-johnson-demo/ethsoc/ip/gen/gig_ethernet_pcs_pma_0/synth/"
name = "gig_ethernet_pcs_pma_0_sync_block"
files = {S.."gig_ethernet_pcs_pma_0_sync_block.v"}
p = svd.parse("verible", name, files)
p = svd.unroll(p); p = svd.inline(p); p = svd.iflift(p)
p = svd.blocking_subst(p); p = svd.meminfer(p); p = svd.memlower(p)
g = svd.mapped_to_prog(svd.gate_map(svd.pick(p, name), 6, 0))
print("== gate-mapped sync_block instances ==")
print(svd.insts(svd.pick(g, name)))
