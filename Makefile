# File:        Makefile
# Author:      Isaac Hagedorn
# Date:        2026-10-08
# Description: Build and run the UART example on Verilator (default), Questa, Xcelium or VCS. Run `make help`.

# verilator | questa | xcelium | vcs
SIM      ?= verilator
# UVM test to run
TEST     ?= tc_direct_urx_utx
# random seed
SEED     ?= 1
# UVM verbosity
VERB     ?= UVM_LOW
# 1: dump waves (FST on Verilator, VCD elsewhere)
WAVES    ?= 0
# Verilator build jobs
JOBS     ?= $(shell nproc 2>/dev/null || echo 4)

ROOT     := $(abspath .)
# Accellera UVM 1.2 source: the UVM_Library submodule of uvm-training, or a sibling clone
UVM_HOME ?= $(firstword $(wildcard $(ROOT)/../../UVM_Library/src $(ROOT)/../UVM_Library/src))

TOP      := top_tb
INCS     := +incdir+$(UVM_HOME) +incdir+$(ROOT)/rtl +incdir+$(ROOT)/agent +incdir+$(ROOT)/test
SRCS     := $(ROOT)/rtl/comm_defs_pkg.sv $(ROOT)/rtl/uart.sv $(ROOT)/agent/uart_pkg.svh $(ROOT)/top_tb/top_tb.sv
DEPS     := $(wildcard $(ROOT)/rtl/* $(ROOT)/agent/* $(ROOT)/environment/* $(ROOT)/test/* $(ROOT)/top_tb/*)
DEFS     := +define+UVM_NO_DPI $(if $(filter 1,$(WAVES)),+define+WAVES)
PLUSARGS := +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERB)

BUILD    := $(ROOT)/build/$(SIM)$(if $(filter 1,$(WAVES)),_waves)
RUNDIR   := $(BUILD)/runs/$(TEST)_s$(SEED)
STAMP    := $(BUILD)/.built

# On CAE machines the commercial simulators only run inside these container wrappers
wrap = $(shell command -v $(1) 2>/dev/null)

ifeq ($(SIM),verilator)
  TOOL      := verilator
  HINT      := source env/setup.sh in uvm-training (or: module load conda-forge/26.3.2 && conda activate ~/.conda/envs/sb-uvm)
  BUILD_CMD := verilator --binary --timing --assert -j $(JOBS) --timescale 1ns/1ps -Wno-fatal -Wno-lint -Wno-style \
               $(if $(filter 1,$(WAVES)),--trace-fst) $(DEFS) $(INCS) $(UVM_HOME)/uvm_pkg.sv $(SRCS) \
               --top-module $(TOP) --Mdir $(BUILD)/obj -o Vtb
  RUN_CMD   := $(BUILD)/obj/Vtb $(PLUSARGS) +verilator+seed+$(SEED)
else ifeq ($(SIM),questa)
  TOOL      := vsim
  HINT      := module load mentor/suite/2026
  WRAP      := $(call wrap,mentor-run)
  BUILD_CMD := $(WRAP) sh -c "vlib work && vlog -sv -timescale 1ns/1ps $(DEFS) $(INCS) $(UVM_HOME)/uvm_pkg.sv $(SRCS)"
  RUN_CMD   := $(WRAP) vsim -c -lib $(BUILD)/work $(TOP) $(PLUSARGS) -sv_seed $(SEED) -do "run -all; quit -f"
else ifeq ($(SIM),xcelium)
  TOOL      := xrun
  HINT      := module load cadence/xcelium/2509   (the default 2603 is newer than the campus license)
  WRAP      := $(call wrap,cadence-run)
  BUILD_CMD := $(WRAP) xrun -64bit -elaborate -sv -sysv_ext +.svh -timescale 1ns/1ps \
               -uvmhome $(abspath $(UVM_HOME)/..) -uvmnocdnsextra $(DEFS) $(INCS) $(SRCS) \
               -top $(TOP) -xmlibdirname $(BUILD)/xcelium.d
  RUN_CMD   := $(WRAP) xrun -64bit -R -xmlibdirname $(BUILD)/xcelium.d $(PLUSARGS) -svseed $(SEED)
else ifeq ($(SIM),vcs)
  TOOL      := vcs
  HINT      := module load synopsys/vcs-mx/2026.03
  WRAP      := $(call wrap,synopsys-run)
  BUILD_CMD := $(WRAP) vcs -full64 -sverilog -timescale=1ns/1ps $(DEFS) $(INCS) $(UVM_HOME)/uvm_pkg.sv $(SRCS) \
               -top $(TOP) -o $(BUILD)/simv
  RUN_CMD   := $(WRAP) $(BUILD)/simv $(PLUSARGS) +ntb_random_seed=$(SEED)
else
  $(error SIM must be verilator, questa, xcelium or vcs)
endif

.PHONY: help build run waves gui clean

help:
	@echo "make build | run | waves | gui | clean"
	@echo "knobs: SIM=verilator|questa|xcelium|vcs TEST SEED VERB WAVES JOBS UVM_HOME"
	@echo "e.g.   make run SIM=questa SEED=3"

$(STAMP): $(DEPS)
	@# /usr/local/cae/bin holds warning stubs, not simulators
	@case "$$(command -v $(TOOL))" in ""|/usr/local/cae/bin/*) echo "$(TOOL) not found. Run: $(HINT)"; exit 1;; esac
	$(if $(filter verilator,$(SIM)),@v=$$(verilator --version | awk '{print $$2}'); \
	  [ "$$(printf '%s\n' 5.052 $$v | sort -V | head -1)" = 5.052 ] || { echo "verilator $$v is older than 5.052 (the version this course is tested with). Run: $(HINT)"; exit 1; })
	@test -f "$(UVM_HOME)/uvm_pkg.sv" || { echo "UVM source not found. Clone uvm-training with --recurse-submodules, or set UVM_HOME=<UVM_Library>/src"; exit 1; }
	@mkdir -p $(BUILD)
	@echo "[build] $(SIM) -> $(BUILD)"
	@cd $(BUILD) && $(BUILD_CMD) > $(BUILD)/build.log 2>&1 || { tail -40 $(BUILD)/build.log; exit 1; }
	@touch $@

build: $(STAMP)

run: $(STAMP)
	@mkdir -p $(RUNDIR)
	@echo "[run] $(TEST) seed $(SEED) -> $(RUNDIR)/sim.log"
	@cd $(RUNDIR) && $(RUN_CMD) > sim.log 2>&1; \
	  grep -E 'UVM_(ERROR|FATAL) [^:]' sim.log | head -20; \
	  if grep -qE '^(# )?UVM_ERROR :\s+0\s*$$' sim.log && grep -qE '^(# )?UVM_FATAL :\s+0\s*$$' sim.log; then \
	    echo "PASS $(TEST) seed=$(SEED) sim=$(SIM)"; \
	  else echo "FAIL $(TEST) seed=$(SEED) sim=$(SIM): see $(RUNDIR)/sim.log"; exit 1; fi

waves:
	@$(MAKE) --no-print-directory run WAVES=1
	@echo "waves: $(ROOT)/build/$(SIM)_waves/runs/$(TEST)_s$(SEED)/waves.$(if $(filter verilator,$(SIM)),fst,vcd)"

# Questa only: interactive GUI with every top-level signal in the wave window
gui: $(STAMP)
	@test "$(SIM)" = questa || { echo "gui needs SIM=questa; use 'make waves' and gtkwave elsewhere"; exit 1; }
	@mkdir -p $(RUNDIR)
	cd $(RUNDIR) && $(WRAP) vsim -lib $(BUILD)/work -voptargs=+acc $(TOP) $(PLUSARGS) -sv_seed $(SEED) \
	  -do "add wave -r /$(TOP)/*; run -all"

clean:
	rm -rf $(ROOT)/build
