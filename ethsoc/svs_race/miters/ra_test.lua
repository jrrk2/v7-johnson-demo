S = "/home/jonathan/v7-johnson-demo/ethsoc/ip/gen/gig_ethernet_pcs_pma_0/synth/"
function try(name, files, style)
  local spec
  if style == "raw" then spec = svd.parse("verible", name, files)
  else
    local q = svd.parse("verible", name, files)
    q = svd.unroll(q); q = svd.inline(q); q = svd.iflift(q)
    q = svd.blocking_subst(q); q = svd.meminfer(q); q = svd.memlower(q)
    spec = svd.augment_xil_models(q)
  end
  local p = svd.parse("verible", name, files)
  p = svd.unroll(p); p = svd.inline(p); p = svd.iflift(p)
  p = svd.blocking_subst(p); p = svd.meminfer(p); p = svd.memlower(p)
  local im = svd.augment_xil_models(svd.mapped_to_prog(svd.gate_map(svd.pick(p, name), 6, 0)))
  print("  " .. name .. " [" .. style .. "] -> " .. svd.miter(svd.pick(spec, name), svd.pick(im, name)))
end
n = "gig_ethernet_pcs_pma_0_rx_rate_adapt"
f = {S.."sgmii_adapt/gig_ethernet_pcs_pma_0_rx_rate_adapt.v"}
try(n, f, "raw")
try(n, f, "piped")
