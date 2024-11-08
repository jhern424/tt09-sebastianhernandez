# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src

# Source files
PROJECT_SOURCES = tt_um_two_lif_stdp.v

# RTL simulation settings
ifneq ($(GATES),yes)
    # RTL simulation build directory
    SIM_BUILD = sim_build/rtl
    
    # Source files for RTL simulation
    VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))
    
    # Include directories
    COMPILE_ARGS += -I$(SRC_DIR)
else
    # Gate level simulation settings
    SIM_BUILD = sim_build/gl
    
    # Gate level compilation arguments
    COMPILE_ARGS += -DGL_TEST
    COMPILE_ARGS += -DFUNCTIONAL
    COMPILE_ARGS += -DUSE_POWER_PINS
    COMPILE_ARGS += -DSIM
    COMPILE_ARGS += -DUNIT_DELAY=\#1
    
    # PDK-related sources for gate level simulation
    VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v
    VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v
    VERILOG_SOURCES += $(PWD)/gate_level_netlist.v
endif

# Include the testbench sources
VERILOG_SOURCES += $(PWD)/tb.v

# Top level module and test module settings
TOPLEVEL = tb
MODULE = test

# Additional simulation settings
SIM_ARGS += -DSTDP_WINDOW=10     # STDP timing window size
SIM_ARGS += -DINIT_WEIGHT=100    # Initial synaptic weight
SIM_ARGS += -DWEIGHT_MAX=63      # Maximum weight value (6 bits)

# Optional: Enable waveform dumping
WAVES ?= 1
ifeq ($(WAVES), 1)
    ifeq ($(SIM), icarus)
        SIM_ARGS += -DWAVEFILE=$(PWD)/waves.vcd
    endif
endif

# Optional: Enable more verbose logging
export COCOTB_LOG_LEVEL ?= INFO
export PYTHONPATH := $(PWD):$(PYTHONPATH)

# Cleanup targets
clean::
	rm -rf sim_build
	rm -rf __pycache__
	rm -rf results.xml
	rm -f *.vcd

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim