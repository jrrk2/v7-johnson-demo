-- FULL production pipeline (multi-level gate_map + single flatten at top),
-- eth_macro blackboxed so the result runs in xsim with the frame player.
local D="/home/jonathan/v7-johnson-demo/ethsoc/"
local FILES = {D.."arp_ctrl.sv",D.."framing_top_sgmii.sv",D.."dualmem_widen.sv",D.."dualmem_widen8.sv",
  D.."async_fifo.v",D.."dualmem64.sv",D.."ramb16_compat.v",D.."vc707_arp.v"}
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
  print("gate_map "..M)
  result = svd.splice(result, M, svd.mapped_to_prog(svd.gate_map(svd.pick(result,M),6,0)))
  k=k+1
end
local net = svd.flatten_struct(result, "top")
svd.write_netlist_edif(net, "/tmp/eb/topsim/full_nogt.edf")
print("WROTE /tmp/eb/topsim/full_nogt.edf")
