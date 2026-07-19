name="mreg"; files={"/tmp/eb/mreg.v"}
p=svd.parse("verible",name,files)
p=svd.unroll(p);p=svd.inline(p);p=svd.iflift(p)
p=svd.blocking_subst(p);p=svd.meminfer(p);p=svd.memlower(p)
g=svd.mapped_to_prog(svd.gate_map(svd.pick(p,name),6,0))
print("== gate-mapped mreg ==")
print(svd.insts(svd.pick(g,name)))
