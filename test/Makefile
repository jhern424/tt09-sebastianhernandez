# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# source directory
SIM_BUILD = sim_build/$(GATES)
PWD=$(shell pwd)
SRC_DIR = $(PWD)/../src

# source files
VERILOG_SOURCES = $(SRC_DIR)/tt_um_two_lif_stdp.v
VERILOG_SOURCES += $(PWD)/tb.v

# DUT
TOPLEVEL = tb
MODULE = test

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim

# Custom clean target
clean:
	rm -rf sim_build
	rm -rf __pycache__
	rm -rf results.xml
	rm -f *.vcd
	rm -f .coverage