#!/usr/bin/env bash
# Build + run the 2x2 systolic_array against the provided testbench.
#
# NOTE: the spec asked for sim.tool = icarus (iverilog), but iverilog is not
# installed on this host. The testbench is plain portable SystemVerilog, so it
# is run here with Synopsys VCS instead. To use Icarus where available:
#   iverilog -g2012 -o simv systolic_array.sv systolic_controller.sv \
#            submodules/weight_stationary_pe.sv submodules/systolic_array_tb.sv \
#     && vvp simv
set -e
cd "$(dirname "$0")"

export VCS_HOME=/opt/synopsys/vcs/W-2024.09
export PATH="$VCS_HOME/bin:$PATH"
export SNPSLMD_LICENSE_FILE=27020@en-license-05.coecis.cornell.edu
export LM_LICENSE_FILE=27020@en-license-05.coecis.cornell.edu

rm -rf csrc simv simv.daidir ucli.key vc_hdrs.h

vcs -full64 -sverilog -timescale=1ns/1ns \
    systolic_array.sv systolic_controller.sv \
    submodules/weight_stationary_pe.sv submodules/systolic_array_tb.sv \
    -top systolic_array_tb -o simv -l compile.log

./simv -l run.log
