# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
PWD=$(shell pwd)
SRC_DIR = $(PWD)/../src

# Source files
VERILOG_SOURCES = $(SRC_DIR)/tt_um_two_lif_stdp.v
VERILOG_SOURCES += $(PWD)/tb.v

# RTL simulation settings
ifneq ($(GATES),yes)
    SIM_BUILD = sim_build/rtl
    COMPILE_ARGS += -I$(SRC_DIR)
else
    # Gate level simulation settings
    SIM_BUILD = sim_build/gl
    COMPILE_ARGS += -DGL_TEST
    COMPILE_ARGS += -DFUNCTIONAL
    COMPILE_ARGS += -DUSE_POWER_PINS
    COMPILE_ARGS += -DSIM
    COMPILE_ARGS += -DUNIT_DELAY=\#1
    VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v
    VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v
endif

# DUT settings
TOPLEVEL = tb
MODULE = test

# Simulation variables
WAVES ?= 1
COMPILE_ARGS += -g2012 

# For Icarus Verilog only
ifeq ($(SIM), icarus)
    ifeq ($(WAVES), 1)
        VVPFLAGS += -fst
    endif
endif

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim

# Extend the default clean target
clean::
	rm -rf __pycache__
	rm -f results.xml
	rm -f *.vcd
	rm -f *.fst
	rm -f *.coverage