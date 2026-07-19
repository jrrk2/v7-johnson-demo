D = "/home/jonathan/v7-johnson-demo/ethsoc/"
FILES = {D.."arp_ctrl.sv",D.."framing_top_sgmii.sv",D.."sgmii_soc.sv",D.."eth_mac_1g.sv",
  D.."axis_gmii_rx.sv",D.."axis_gmii_tx.sv",D.."rgmii_lfsr.sv",D.."dualmem_widen.sv",D.."dualmem_widen8.sv",
  D.."eth_macro.sv",D.."async_fifo.v",D.."dualmem64.sv",D.."ramb16_compat.v",D.."eth_stream_conv.v",D.."pcs_pma_flat.v",D.."vc707_arp.v"}
pass=0; fail=0
function wm(name)
  local spec = svd.parse("verible", name, FILES)
  local p = svd.parse("verible", name, FILES)
  p = svd.unroll(p); p = svd.inline(p); p = svd.iflift(p)
  p = svd.blocking_subst(p); p = svd.meminfer(p); p = svd.memlower(p)
  local im = svd.augment_xil_models(svd.mapped_to_prog(svd.gate_map(svd.pick(p, name), 6, 0)))
  local r = svd.miter(svd.pick(spec, name), svd.pick(im, name))
  if r == "EQUIVALENT" then pass=pass+1 else fail=fail+1 end
  print("  " .. name .. " -> " .. r)
end
print("== PCS-glue + framing wrapper self-miter ==")
wm("sgmii_soc")
wm("eth_macro")
wm("framing_top_sgmii")
print("== pass=" .. pass .. " fail=" .. fail .. " ==")
