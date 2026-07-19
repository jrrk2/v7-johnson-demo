-- Standalone SVS synth of the rx_elastic_buffer + RAM64M lowering inspection
files = {
  "/home/jonathan/v7-johnson-demo/ethsoc/ip/gen/gig_ethernet_pcs_pma_0/synth/transceiver/gig_ethernet_pcs_pma_0_rx_elastic_buffer.v",
  "/home/jonathan/v7-johnson-demo/ethsoc/ip/gen/gig_ethernet_pcs_pma_0/synth/gig_ethernet_pcs_pma_0_sync_block.v"
}
top = "gig_ethernet_pcs_pma_0_rx_elastic_buffer"
p = svd.parse("verible", top, files)
p = svd.unroll(p); p = svd.inline(p); p = svd.iflift(p)
p = svd.blocking_subst(p); p = svd.meminfer(p); p = svd.memlower(p)
p = svd.srl_infer(p)
g = svd.gate_map(svd.pick(p, top), 6, 0)
prog = svd.mapped_to_prog(g)
insts = svd.insts(svd.pick(prog, top))
-- count primitive classes
c = ""
i = 1
n = strlen(insts)
print("== elastic buffer standalone SVS synth OK ==")
-- crude: dump instance-class histogram via external grep instead
svd.write_netlist_edif(svd.flatten_struct(prog), "/tmp/eb/eb_svs.edf", top)
print("wrote /tmp/eb/eb_svs.edf")
