# ethloop open-flow artifacts (2026-07-08 campaign)

- `pip_blacklist_ethloop_stage2.txt` — the blacklist that brings the OPEN
  ethloop RX path fully alive on silicon (8 INT_R bounce/jump pips + 25
  comparable-class suspects + 248 CLK_HROW lane-1 assignment pips: lane B1's
  INT CLK-entry segbits are comparability-broken; golden never uses B0/B1).
  Use: PIP_BLACKLIST=$PWD/pip_blacklist_ethloop_stage2.txt ../build_r0_ethloop.sh
- `txcone_suspects_stage2.txt` — 57 never-golden-validated pip types in the
  TX cone of the stage-2 routing (TX still dead there); dominated by
  long-line LV/LH/LVB entries + bounce family.  Blacklisting all of them
  (stage 3) rerolled the routing and broke RX => ddmin with an RX-alive gate,
  or Vivado-fuzz these encodings, is the way forward.

nextpnr fixes this campaign (deps/nextpnr-xilinx):
- pack_carry_xc7.cc: don't stamp PRECYINIT_CONST when CYINIT is a live net
  (Vivado chain roots have CIN=GND + CYINIT=<net>) — was killing every
  down-counter/comparator carry chain.
- fasm.cc: FDSE/FDPE default INIT=1 (Vivado omits default params) — was
  ZINI-ing reset synchronizers and INIT=1 startup FSMs to 0.
prjxray DB fixes (~/prjxray/database/virtex7):
- segbits_lioi{,_tbytesrc,_tbyteterm}.db: added ILOGIC_Y0.ZINV_D 29_109 /
  ILOGIC_Y1.ZINV_D 28_18 (ground-truthed from golden frames).
- ppips_{l,r}ioi*.db: removed ILOGIC ZINV_D 'always' lines (they shadow
  segbits in fasm2frames).
