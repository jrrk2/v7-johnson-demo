name = "logop_bit"; files = {"/tmp/eb/logop_bit.v"}
spec = svd.parse("verible", name, files)
p = svd.parse("verible", name, files)
p = svd.unroll(p); p = svd.inline(p); p = svd.iflift(p)
p = svd.blocking_subst(p); p = svd.meminfer(p); p = svd.memlower(p)
im = svd.augment_xil_models(svd.mapped_to_prog(svd.gate_map(svd.pick(p, name), 6, 0)))
print("logop_bit & -> " .. svd.miter(svd.pick(spec, name), svd.pick(im, name)))
