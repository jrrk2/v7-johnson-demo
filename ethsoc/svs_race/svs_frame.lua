-- framing_top WITHOUT eth_macro.sv: eth_macro instance becomes a blackbox,
-- so the flatten stops at it and no GT primitives appear.
local D="/home/jonathan/v7-johnson-demo/ethsoc/"
local FILES = {D.."framing_top_sgmii.sv",D.."dualmem64.sv",D.."ramb16_compat.v",D.."dualmem_widen.sv",D.."dualmem_widen8.sv",D.."async_fifo.v"}
local p = svd.parse("verible", "framing_top_sgmii", FILES)
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
local net = svd.flatten_struct(result, "framing_top_sgmii")
svd.write_netlist_edif(net, "/tmp/eb/framesim/framing_nogt.edf")
print("WROTE /tmp/eb/framesim/framing_nogt.edf")
