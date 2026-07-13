#!/bin/bash
# xsim FSM smoke test for vc707_ethloop.v (processor-free eth<->UART bridge).
# Uses the REAL Vivado UNISIM primitives (IBUFDS/BUFG/MMCME2_ADV + glbl); the
# eth core is the behavioural bus-level double framing_top_sgmii_sim.v (PHY out
# of scope for a bus test -- full-design verification is the Vivado HW build).
set -eu
ETH=/home/jonathan/v7-johnson-demo/ethsoc
export XILINX_VIVADO=/home/Xilinx/Vivado/2020.1
export PATH=$XILINX_VIVADO/bin:$PATH
WORK=/tmp/ethloop_xsim; rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK"
GLBL=/home/Xilinx/Vivado/2020.1/data/verilog/src/glbl.v

xvlog -sv "$ETH/vc707_ethloop.v" "$ETH/framing_top_sgmii_sim.v" "$ETH/tb_ethloop.v" \
      > xvlog.log 2>&1 || { echo "XVLOG FAIL"; tail -30 xvlog.log; exit 1; }
xvlog "$GLBL" >> xvlog.log 2>&1
echo "xvlog OK"
xelab tb glbl -L unisims_ver -L secureip -timescale 1ns/1ps -s tbsim \
      > xelab.log 2>&1 || { echo "XELAB FAIL"; tail -40 xelab.log; exit 1; }
echo "xelab OK"
xsim tbsim -R > xsim.log 2>&1 || true
grep -vE "^#|INFO:|WARNING:|Vivado|xsim|^$" xsim.log | head -80
echo "(full log: $WORK/xsim.log)"
