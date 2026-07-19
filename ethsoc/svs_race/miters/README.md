# Cross-flow Z3 miters + bug-finding harnesses (2026-07 SVS eth-arp campaign)

These are the `sv_suite.exe script <file>` recipes that found the 15 synthesis
bugs.  They read RTL from ../../ (ethsoc/*.sv, pcs_pma_flat.v) and emit EDIF /
nextpnr-json / Z3 miters to a /tmp work area (regenerable; override the output
paths inside each file).

- *_miter.lua   : Vivado-netlist vs SVS-gate-mapped Z3 equivalence miters
                  (core/pcs/wrap/passthru/xflow) — the cross-flow proofs.
- synth_eb.lua  : elastic-buffer synth probe.
- resets_*, sb_*, ra_*, mreg*, logop* : targeted reset-polarity / bitbus /
  register / logic-op test harnesses used to localize individual bugs.

The maintained, load-bearing recipes live one level up in svs_race/ (arp_open.lua
for the open flow, svs_*.lua + tb_*.v for the xsim races).  These are the raw
investigation scripts, kept for provenance and reuse.
