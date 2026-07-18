-- Open flow, corrected: gate_map the behavioral WRAPPERS, but PASS THROUGH the
-- pre-flattened primitive PCS netlist unchanged (skip gate_map on pcs modules).
local D="/home/jonathan/v7-johnson-demo/ethsoc/"
local FILES = {D.."arp_ctrl.sv",D.."framing_top_sgmii.sv",D.."sgmii_soc.sv",D.."eth_mac_1g.sv",
  D.."axis_gmii_rx.sv",D.."axis_gmii_tx.sv",D.."rgmii_lfsr.sv",D.."dualmem_widen.sv",D.."dualmem_widen8.sv",
  D.."eth_macro.sv",D.."async_fifo.v",D.."dualmem64.sv",D.."ramb16_compat.v",D.."eth_stream_conv.v",D.."pcs_pma_flat.v",D.."vc707_arp.v"}
local p = svd.parse("verible", "top", FILES)
p = svd.unroll(p); p=svd.inline(p); p=svd.iflift(p)
p = svd.blocking_subst(p); p=svd.meminfer(p); p=svd.memlower(p); p=svd.srl_infer(p)
local names = svd.module_names(p)
NT={}; local cnt=0; local i=1; local n=strlen(names)
while i<=n do local j=strfind(names,",",i,1); local nm
  if j then nm=strsub(names,i,j-1); i=j+1 else nm=strsub(names,i,n); i=n+1 end
  if strlen(nm)>0 then cnt=cnt+1; NT[cnt]=nm end
end
local result=p; local k=1
while k<=cnt do
  local M=NT[k]
  -- pass through the primitive PCS modules unchanged; gate_map only the wrappers
  if strfind(M, "gig_ethernet_pcs_pma", 1, 1)  then
    print("PASS-THROUGH "..M)
  else
    print("gate_map "..M)
    result = svd.splice(result, M, svd.mapped_to_prog(svd.gate_map(svd.pick(result,M),6,0)))
  end
  k=k+1
end
local net = svd.flatten_struct(result, "arp_ctrl__FM2199028187441_FI3232235876")
svd.write_netlist_edif(net, "/tmp/eb/arpsim/arp_ctrl.edf")
print("WROTE /tmp/eb/arpsim/arp_ctrl.edf")
