D="/home/jonathan/v7-johnson-demo/ethsoc/"
FILES={D.."arp_ctrl.sv",D.."framing_top_sgmii.sv",D.."sgmii_soc.sv",D.."eth_mac_1g.sv",D.."axis_gmii_rx.sv",D.."axis_gmii_tx.sv",D.."rgmii_lfsr.sv",D.."dualmem_widen.sv",D.."dualmem_widen8.sv",D.."eth_macro.sv",D.."async_fifo.v",D.."dualmem64.sv",D.."ramb16_compat.v",D.."eth_stream_conv.v",D.."pcs_pma_flat.v",D.."vc707_arp.v"}
p=svd.parse("verible","top",FILES)
p=svd.unroll(p);p=svd.inline(p);p=svd.iflift(p);p=svd.blocking_subst(p);p=svd.meminfer(p);p=svd.memlower(p)
print(svd.bir(svd.pick(p,"sgmii_soc")))
