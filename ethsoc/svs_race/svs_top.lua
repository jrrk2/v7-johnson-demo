local D="/home/jonathan/v7-johnson-demo/ethsoc/"
local FILES = {D.."vc707_arp.v"}
local p = svd.parse("verible", "top", FILES)
p = svd.unroll(p); p=svd.inline(p); p=svd.iflift(p)
p = svd.blocking_subst(p); p=svd.meminfer(p); p=svd.memlower(p); p=svd.srl_infer(p)
local result = svd.splice(p, "top", svd.mapped_to_prog(svd.gate_map(svd.pick(p,"top"),6,0)))
local net = svd.flatten_struct(result, "top")
svd.write_netlist_edif(net, "/tmp/eb/topsim/top_only.edf")
print("WROTE /tmp/eb/topsim/top_only.edf")
