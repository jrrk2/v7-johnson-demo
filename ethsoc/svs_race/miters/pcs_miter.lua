S = "/home/jonathan/v7-johnson-demo/ethsoc/ip/gen/gig_ethernet_pcs_pma_0/synth/"
pass = 0; fail = 0
function selfmiter(name, files)
  local spec = svd.augment_xil_models(svd.parse("verible", name, files))
  local p    = svd.parse("verible", name, files)
  p = svd.unroll(p); p = svd.inline(p); p = svd.iflift(p)
  p = svd.blocking_subst(p); p = svd.meminfer(p); p = svd.memlower(p)
  -- srl_infer disabled (separately proven); keeps FF-chain state aligned
  local im = svd.augment_xil_models(svd.mapped_to_prog(svd.gate_map(svd.pick(p, name), 6, 0)))
  local res = svd.miter(svd.pick(spec, name), svd.pick(im, name))
  if res == "EQUIVALENT" then pass = pass + 1 else fail = fail + 1 end
  print("  " .. name .. "  -> " .. res)
end
print("== bottom-up PCS self-miter: pure-logic leaves ==")
selfmiter("gig_ethernet_pcs_pma_0_sync_block",     {S.."gig_ethernet_pcs_pma_0_sync_block.v"})
selfmiter("gig_ethernet_pcs_pma_0_reset_sync",     {S.."gig_ethernet_pcs_pma_0_reset_sync.v"})
selfmiter("gig_ethernet_pcs_pma_0_johnson_cntr",   {S.."sgmii_adapt/gig_ethernet_pcs_pma_0_johnson_cntr.v"})
selfmiter("gig_ethernet_pcs_pma_0_rx_rate_adapt",  {S.."sgmii_adapt/gig_ethernet_pcs_pma_0_rx_rate_adapt.v"})
selfmiter("gig_ethernet_pcs_pma_0_tx_rate_adapt",  {S.."sgmii_adapt/gig_ethernet_pcs_pma_0_tx_rate_adapt.v"})
selfmiter("gig_ethernet_pcs_pma_0_resets",         {S.."gig_ethernet_pcs_pma_0_resets.v"})
selfmiter("gig_ethernet_pcs_pma_0_reset_wtd_timer",{S.."transceiver/gig_ethernet_pcs_pma_0_reset_wtd_timer.v"})
selfmiter("gig_ethernet_pcs_pma_0_cpll_railing",   {S.."transceiver/gig_ethernet_pcs_pma_0_cpll_railing.v"})
print("== leaves: pass=" .. pass .. " fail=" .. fail .. " ==")
