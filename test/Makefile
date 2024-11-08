# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src

# Source files
PROJECT_SOURCES = tt_um_hh_stdp.v

# RTL simulation settings
ifneq ($(GATES),yes)
    SIM_BUILD = sim_build/rtl
    VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))
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
    VERILOG_SOURCES += $(PWD)/gate_level_netlist.v
endif

# Include the testbench sources
VERILOG_SOURCES += $(PWD)/tb.v

TOPLEVEL = tb
MODULE = test

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim