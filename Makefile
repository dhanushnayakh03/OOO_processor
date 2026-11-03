# ==============================================================================
# Makefile for Scalar RV64IM Out-of-Order (OoO) Processor
# Standard: Pure Verilog-2001 (-g2001)
# Simulator: Icarus Verilog (iverilog)
# Structure: src/ (RTL modules), tb/ (Testbenches), test_assembly/ (Assembly tests)
# ==============================================================================

# Toolchain definitions
CC       = riscv64-unknown-elf-gcc
OBJCOPY  = riscv64-unknown-elf-objcopy
OBJDUMP  = riscv64-unknown-elf-objdump
PYTHON   = python3
IVERILOG = iverilog
VVP      = vvp

# Directories
SRC_DIR  = src
TB_DIR   = tb
ASM_DIR  = test_assembly

# Flags
CFLAGS   = -march=rv64im -mabi=lp64 -nostdlib -nostartfiles -T linker.ld
VFLAGS   = -g2001 -I$(SRC_DIR) -I$(TB_DIR)

# Source RTL Files
RTL_SRCS = $(SRC_DIR)/defs.v \
           $(SRC_DIR)/branch_predictor.v \
           $(SRC_DIR)/fetch_stage.v \
           $(SRC_DIR)/map_table.v \
           $(SRC_DIR)/arch_map_table.v \
           $(SRC_DIR)/free_list.v \
           $(SRC_DIR)/physical_regfile.v \
           $(SRC_DIR)/rob.v \
           $(SRC_DIR)/store_queue.v \
           $(SRC_DIR)/reservation_station.v \
           $(SRC_DIR)/dispatch_stage.v \
           $(SRC_DIR)/issue_stage.v \
           $(SRC_DIR)/fu_alu.v \
           $(SRC_DIR)/fu_mult.v \
           $(SRC_DIR)/fu_branch.v \
           $(SRC_DIR)/fu_load.v \
           $(SRC_DIR)/complete_stage.v \
           $(SRC_DIR)/retire_stage.v \
           $(SRC_DIR)/core.v \
           $(SRC_DIR)/memory.v

# Testbench Files
TB_SRCS  = $(TB_DIR)/tb_core.v

ALL_SRCS = $(RTL_SRCS) $(TB_SRCS)

# Resolve assembly source file: checks current directory first, then test_assembly/
SOURCE   ?= test_evens_64.s
ASM_FILE = $(if $(wildcard $(SOURCE)),$(SOURCE),$(if $(wildcard $(ASM_DIR)/$(SOURCE)),$(ASM_DIR)/$(SOURCE),$(error Error: Assembly file '$(SOURCE)' not found in '.' or '$(ASM_DIR)')))

# ------------------------------------------------------------------------------
# Run custom/single-step testbench directly:
#   make simtest                      (defaults to tb_single_step.v)
#   make simtest tb_single_step.v
#   make simtest TB=tb_single_step.v
# ------------------------------------------------------------------------------
TB ?= tb_single_step.v

# If invoked as 'make simtest <file.v>', capture argument and register no-op rule
ifeq (simtest,$(firstword $(MAKECMDGOALS)))
  TB_ARG := $(word 2,$(MAKECMDGOALS))
  ifneq ($(TB_ARG),)
    TB := $(TB_ARG)
    $(eval $(TB_ARG):;@:)
  endif
endif

TB_TARGET = $(if $(wildcard $(TB)),$(TB),$(if $(wildcard $(TB_DIR)/$(TB)),$(TB_DIR)/$(TB),$(TB)))

simtest:
	@echo "--- Compiling $(TB_TARGET) with RTL sources ---"
	$(IVERILOG) $(VFLAGS) -o sim_test $(RTL_SRCS) $(TB_TARGET)
	@echo "--- Running Simulation ($(TB_TARGET)) ---"
	@./sim_test
	@rm -f sim_test

all: sim


# ------------------------------------------------------------------------------
# Build and Run with Branch Predictor ENABLED (Built-in Test Suite)
# ------------------------------------------------------------------------------
simv: $(ALL_SRCS)
	$(IVERILOG) $(VFLAGS) -P tb_core.ENABLE_BP=1 -o simv $(ALL_SRCS)

sim: simv
	@echo "--- Running Simulation (Branch Predictor ENABLED) ---"
	./simv

# ------------------------------------------------------------------------------
# Build and Run with Branch Predictor DISABLED (Static Not-Taken)
# ------------------------------------------------------------------------------
simv_no_bp: $(ALL_SRCS)
	$(IVERILOG) $(VFLAGS) -P tb_core.ENABLE_BP=0 -o simv_no_bp $(ALL_SRCS)

sim_no_bp: simv_no_bp
	@echo "--- Running Simulation (Branch Predictor DISABLED) ---"
	./simv_no_bp

# ------------------------------------------------------------------------------
# Assemble and Run ANY assembly file from test_assembly/ or custom path
# Usage: 
#   make program SOURCE=single.s          (Detailed cycle-by-cycle tracer)
#   make prog_o SOURCE=example.s          (Default: BP=1)
#   make prog_o SOURCE=example.s BP=0     (Branch Predictor DISABLED)
#   make prog_o SOURCE=example.s BP=1     (Branch Predictor ENABLED)
#   make prog_o_no_bp SOURCE=example.s    (Convenience target without BP)
#   make compare_prog SOURCE=example.s    (Compare BP enabled vs disabled on assembly)
# ------------------------------------------------------------------------------
BP       ?= 1
DEBUG    ?= $(if $(filter single.s,$(notdir $(ASM_FILE))),1,0)
SIM_BIN  = $(if $(filter 0,$(BP)),simv_no_bp,simv)

program: prog_o

prog_o: $(SIM_BIN)
	@echo "=================================================================="
	@echo " Compiling Assembly: $(ASM_FILE)"
	@echo "=================================================================="
	$(CC) $(CFLAGS) $(ASM_FILE) -o program.elf
	$(OBJDUMP) -d program.elf > program.dump
	$(OBJCOPY) -O binary program.elf program.bin
	$(PYTHON) make_hex.py program.bin program.mem
	@echo "=================================================================="
	@echo " Running on Scalar RV64IM Core ($(if $(filter 0,$(BP)),BP DISABLED,BP ENABLED))"
	@echo "=================================================================="
	./$(SIM_BIN) +MEM=program.mem $(if $(filter 1,$(DEBUG)),+DEBUG,)

prog_o_no_bp:
	$(MAKE) prog_o SOURCE=$(SOURCE) BP=0

# ------------------------------------------------------------------------------
# Compare Performance With vs Without Branch Prediction
# ------------------------------------------------------------------------------
compare: simv simv_no_bp
	@echo "=================================================================="
	@echo " [1/2] RUNNING WITH BRANCH PREDICTOR ENABLED"
	@echo "=================================================================="
	./simv | grep -E "(Total Cycles|Retired Instructions|Branch Mispredictions|Final IPC|Final CPI)"
	@echo "=================================================================="
	@echo " [2/2] RUNNING WITH BRANCH PREDICTOR DISABLED"
	@echo "=================================================================="
	./simv_no_bp | grep -E "(Total Cycles|Retired Instructions|Branch Mispredictions|Final IPC|Final CPI)"
	@echo "=================================================================="

compare_prog: simv simv_no_bp
	@echo "=================================================================="
	@echo " Compiling Assembly: $(ASM_FILE)"
	@echo "=================================================================="
	$(CC) $(CFLAGS) $(ASM_FILE) -o program.elf
	$(OBJDUMP) -d program.elf > program.dump
	$(OBJCOPY) -O binary program.elf program.bin
	$(PYTHON) make_hex.py program.bin program.mem
	@echo "=================================================================="
	@echo " [1/2] RUNNING WITH BRANCH PREDICTOR ENABLED"
	@echo "=================================================================="
	./simv +MEM=program.mem | grep -E "(Total Cycles|Retired Instructions|Branch Mispredictions|Final IPC|Final CPI)"
	@echo "=================================================================="
	@echo " [2/2] RUNNING WITH BRANCH PREDICTOR DISABLED"
	@echo "=================================================================="
	./simv_no_bp +MEM=program.mem | grep -E "(Total Cycles|Retired Instructions|Branch Mispredictions|Final IPC|Final CPI)"
	@echo "=================================================================="

# ------------------------------------------------------------------------------
# Modular Unit Testbenches (Verilog-2001)
# ------------------------------------------------------------------------------
test_bp:
	@$(IVERILOG) $(VFLAGS) -o sim_tb_bp $(TB_DIR)/tb_bp.v $(SRC_DIR)/branch_predictor.v
	@./sim_tb_bp
	@rm -f sim_tb_bp

test_freelist:
	@$(IVERILOG) $(VFLAGS) -o sim_tb_freelist $(TB_DIR)/tb_freelist.v $(SRC_DIR)/free_list.v
	@./sim_tb_freelist
	@rm -f sim_tb_freelist

test_maptable:
	@$(IVERILOG) $(VFLAGS) -o sim_tb_maptable $(TB_DIR)/tb_maptable.v $(SRC_DIR)/map_table.v
	@./sim_tb_maptable
	@rm -f sim_tb_maptable

test_rob:
	@$(IVERILOG) $(VFLAGS) -o sim_tb_rob $(TB_DIR)/tb_rob.v $(SRC_DIR)/rob.v
	@./sim_tb_rob
	@rm -f sim_tb_rob

test_rs:
	@$(IVERILOG) $(VFLAGS) -o sim_tb_rs $(TB_DIR)/tb_rs.v $(SRC_DIR)/reservation_station.v
	@./sim_tb_rs
	@rm -f sim_tb_rs

test_sq:
	@$(IVERILOG) $(VFLAGS) -o sim_tb_sq $(TB_DIR)/tb_sq.v $(SRC_DIR)/store_queue.v
	@./sim_tb_sq
	@rm -f sim_tb_sq

test_complete:
	@$(IVERILOG) $(VFLAGS) -o sim_tb_complete $(TB_DIR)/tb_complete.v $(SRC_DIR)/complete_stage.v
	@./sim_tb_complete
	@rm -f sim_tb_complete

test_mult:
	@$(IVERILOG) $(VFLAGS) -o sim_tb_mult $(TB_DIR)/tb_mult.v $(SRC_DIR)/fu_mult.v
	@./sim_tb_mult
	@rm -f sim_tb_mult

test_units: test_bp test_freelist test_maptable test_rob test_rs test_sq test_complete test_mult
	@echo "=================================================================="
	@echo "   >>> ALL 8 MODULAR UNIT TESTBENCHES PASSED SUCCESSFULLY! <<<"
	@echo "=================================================================="

wave:
	gtkwave sim_scalar_ooo.vcd &

clean:
	rm -f simv simv_no_bp sim_tb_* *.vcd *.elf *.bin *.dump *.mem

help:
	@echo "Available commands:"
	@echo "  make                                  - Built-in test suite (BP enabled)"
	@echo "  make sim_no_bp                        - Built-in test suite (BP disabled)"
	@echo "  make compare                          - Compare built-in suite with vs without BP"
	@echo "  make program SOURCE=file.s            - Run .s with cycle tracer (default: single.s)"
	@echo "  make prog_o SOURCE=file.s             - Run .s file with BP enabled"
	@echo "  make prog_o SOURCE=file.s BP=0        - Run .s file with BP disabled"
	@echo "  make prog_o_no_bp SOURCE=file.s       - Run .s file with BP disabled"
	@echo "  make compare_prog SOURCE=file.s       - Compare .s performance with vs without BP"
	@echo "  make wave                             - Open waveform in GTKWave"
	@echo "  make test_units                       - Run all 8 unit testbenches"
	@echo "  make test_bp                          - Test Branch Predictor"
	@echo "  make test_freelist                    - Test Physical Register Free List"
	@echo "  make test_maptable                    - Test Speculative Map Table (RAT)"
	@echo "  make test_rob                         - Test Reorder Buffer"
	@echo "  make test_rs                          - Test Reservation Station"
	@echo "  make test_sq                          - Test Store Queue & RAW Forwarding"
	@echo "  make test_complete                    - Test CDB Complete Arbiter"
	@echo "  make test_mult                        - Test RV64M Pipelined Multiplier"
	@echo "  make clean                            - Clean all compiled binaries and dumps"

.PHONY: all sim sim_no_bp program prog_o prog_o_no_bp compare compare_prog wave clean help simtest \
        test_units test_bp test_freelist test_maptable test_rob test_rs test_sq test_complete test_mult


