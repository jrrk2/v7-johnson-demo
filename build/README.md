# build/ — generated bitstreams, FASM, and P&R intermediates

Everything the SVS Makefile targets produce lands here, one subdirectory per
target.  **This tree is gitignored and fully regenerable** — never edit or
commit anything under it, and never store sources here.

    build/
      svs_arp/          make svs_arp        pinned silicon-validated open flow
                        -> svs_arp.bit, arp.fasm, arp.frames, arp_stamped.json, logs
      svs_arp_synth/    make svs_arp_synth  eth-arp from SVS synthesis (open backend)
                        -> svs_arp_synth.bit, arp.fasm, arp_routed.json, svs_synth.log
      hybrid_ethmacro/  make svs_hybrid_ethmacro   golden shell + SVS eth_macro (Vivado)
      hybrid_sgmii/     make svs_hybrid_sgmii      golden shell + SVS sgmii_soc
      hybrid_framing/   make svs_hybrid_framing    golden shell + SVS framing_top
      hybrid_arp/       make svs_hybrid_arp        golden shell + SVS arp_ctrl
                        -> svs_<layer>_in_golden.bit + top.edf, <layer>.edf, logs
      diag/             make svs_diag       PCS status-observer bitstreams
                        -> diag_gold.bit, diag_svs.bit

## Conventions
- Root is `$(BUILD)`, default `$(CURDIR)/build`.  Override on the command
  line: `make svs_arp BUILD=/scratch/mybuilds`.
- Each target `mkdir -p`s its own subdir; nothing is shared, so parallel
  builds of different targets don't collide (they do share `/tmp/nextpnr.lock`
  for the router).
- Final artifacts are `<name>.bit` / `.fasm` / `.frames`; flash with the
  matching `-flash` target (`make svs_arp-flash`, `make svs_hybrid_sgmii-flash`).
- STA reads the routed JSON + FASM from here:
  `make svs_arp_synth-sta` (defaults to `build/svs_arp_synth/`).

The standalone scripts (`ethsoc/build_svs_arp.sh`, `ethsoc/svs_race/build_hybrid.sh`)
default their work dir to this tree too, so running them directly (outside make)
also stays out of /tmp.
