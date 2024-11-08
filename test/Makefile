# Makefile
# See https://docs.cocotb.org/en/stable/quickstart.html for more info

# defaults
SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../src

# Updated project sources for HH with STDP
PROJECT_SOURCES = \
    defines.v \
    exp_lut_gen.v \
    math_functions.v \
    hh_state.v \
    hodgkin_huxley.v \
    stdp_synapse.v \
    tt_um_hh_stdp.v

# RTL simulation settings
ifneq ($(GATES),yes)
    SIM_BUILD = sim_build/rtl
    VERILOG_SOURCES += $(addprefix $(SRC_DIR)/,$(PROJECT_SOURCES))
    COMPILE_ARGS += -I$(SRC_DIR)
    
    # Add defines for RTL simulation
    COMPILE_ARGS += -DRTL_SIM
    COMPILE_ARGS += -DENABLE_DEBUG_OUTPUTS
    COMPILE_ARGS += -DPIPELINE_MONITORING
    
    # Icarus-specific flags for fixed-point support
    ifeq ($(SIM),icarus)
        COMPILE_ARGS += -DICARUS_VERILOG
    endif

# Gate level simulation settings
else
    SIM_BUILD = sim_build/gl
    COMPILE_ARGS += -DGL_TEST
    COMPILE_ARGS += -DFUNCTIONAL
    COMPILE_ARGS += -DUSE_POWER_PINS
    COMPILE_ARGS += -DSIM
    COMPILE_ARGS += -DUNIT_DELAY=\#1
    
    # PDK sources
    VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v
    VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v
    
    # Gate level netlist
    VERILOG_SOURCES += $(PWD)/gate_level_netlist.v
endif

# Include the testbench sources
VERILOG_SOURCES += $(PWD)/tb.v

# Testbench configuration
TOPLEVEL = tb
MODULE = test

# Special configurations for the HH model
COMPILE_ARGS += -DFIXED_POINT_WIDTH=16
COMPILE_ARGS += -DDECIMAL_BITS=7
COMPILE_ARGS += -DLUT_SIZE=256

# Simulation time step for neuron dynamics
COMPILE_ARGS += -DTIME_STEP=0.01

# Waveform dumping options (uncomment to enable)
#COMPILE_ARGS += -DVCD_DUMP
#COMPILE_ARGS += -DFST_DUMP

# Additional simulator-specific options
ifeq ($(SIM),verilator)
    EXTRA_ARGS += --trace --trace-structs
    COMPILE_ARGS += -DVERILATOR
endif

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim

# Additional targets for convenience
.PHONY: clean_all wave

clean_all: clean
	rm -rf sim_build
	rm -rf __pycache__
	rm -rf results.xml
	rm -rf *.vcd
	rm -rf *.fst

wave:
	gtkwave dump.vcd wave.gtkw &