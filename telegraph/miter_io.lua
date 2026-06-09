-- Confound-free Z3 miter: nextpnr's ROUTED output vs its own INPUT (both the
-- same Vivado synthesis / same FSM encoding, so no state re-encoding confound).
-- Asks: did nextpnr pack+place+route+writeback preserve the logic?
spec = svd.read_nextpnr_json("/tmp/tg_placed_locked.json")
spec = svd.augment_xil_models(spec)
impl = svd.read_nextpnr_json("/tmp/tg_ro_post.json")
impl = svd.augment_xil_models(impl)
print("VERDICT: " .. svd.miter(svd.prep_for_z3(svd.pick(spec,"top")),
                               svd.prep_for_z3(svd.pick(impl,"top"))))
