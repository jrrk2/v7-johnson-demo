S = "/home/jonathan/v7-johnson-demo/ethsoc/ip/gen/gig_ethernet_pcs_pma_0/synth/"
function pipe(p)
  p = svd.unroll(p); p = svd.inline(p); p = svd.iflift(p)
  p = svd.blocking_subst(p); p = svd.meminfer(p); p = svd.memlower(p)
  return p
end
name = "gig_ethernet_pcs_pma_0_sync_block"
files = {S.."gig_ethernet_pcs_pma_0_sync_block.v"}
spec = svd.augment_xil_models(pipe(svd.parse("verible", name, files)))
im   = svd.augment_xil_models(svd.mapped_to_prog(svd.gate_map(svd.pick(pipe(svd.parse("verible", name, files)), name), 6, 0)))
print("sync_block (spec piped) -> " .. svd.miter(svd.pick(spec, name), svd.pick(im, name)))
