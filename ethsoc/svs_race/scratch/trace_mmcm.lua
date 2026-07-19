D="/home/jonathan/v7-johnson-demo/ethsoc/"
FILES={D.."arp_ctrl.sv",D.."framing_top_sgmii.sv",D.."sgmii_soc.sv",D.."eth_mac_1g.sv",D.."axis_gmii_rx.sv",D.."axis_gmii_tx.sv",D.."rgmii_lfsr.sv",D.."dualmem_widen.sv",D.."dualmem_widen8.sv",D.."eth_macro.sv",D.."async_fifo.v",D.."dualmem64.sv",D.."ramb16_compat.v",D.."eth_stream_conv.v",D.."pcs_pma_flat.v",D.."vc707_arp.v"}
p=svd.parse("verible","top",FILES)
p=svd.unroll(p);p=svd.inline(p);p=svd.iflift(p);p=svd.blocking_subst(p);p=svd.meminfer(p);p=svd.memlower(p);p=svd.srl_infer(p)
names=svd.module_names(p);NT={};cnt=0;i=1;n=strlen(names)
while i<=n do j=strfind(names,",",i,1);local nm
 if j then nm=strsub(names,i,j-1);i=j+1 else nm=strsub(names,i,n);i=n+1 end
 if strlen(nm)>0 then cnt=cnt+1;NT[cnt]=nm end end
result=p;k=1
while k<=cnt do M=NT[k]
 result=svd.splice(result,M,svd.mapped_to_prog(svd.gate_map(svd.pick(result,M),6,0)));k=k+1 end
net=svd.flatten_struct(result,"top")
print(svd.insts(net))
