# Scalar RV64IM Out-of-Order (OoO) Processor

A complete, synthesizable, high-performance **Scalar Out-of-Order (OoO) Processor** core implementing the **RV64IM** instruction set architecture, written **strictly in pure Verilog-2001** (`.v`).

---

## 1. Architectural Highlights

- **ISA**: Full 64-bit integer core (`XLEN = 64`), 32-bit instructions (`ILEN = 32`) with **RV64M hardware multiplier**.
- **Register Renaming (R10K Unified PRF Style)**:
  - 32 Architectural Registers (`x0 - x31`).
  - 64 Unified Physical Registers (`p0 - p63`), with `p0` hardwired to zero.
  - Speculative Register Alias Table (**RAT**) with CDB snooping and instantaneous rollback.
  - Architectural Retirement Register Alias Table (**RRAT**) for committed state.
  - 32-entry **Free List** FIFO with instantaneous bitmask reconstruction on branch recovery.
- **Out-of-Order Queues**:
  - **Reorder Buffer (ROB)**: 32 entries, in-order dispatch, out-of-order completion, in-order retirement.
  - **Reservation Station (RS)**: 16 entries with continuous tag snooping on Common Data Bus (CDB) and Functional Unit backpressure tracking.
  - **Store Queue (SQ)**: 16 entries with **Store-to-Load Forwarding** and **Memory Disambiguation**.
- **Branch Prediction & Recovery**:
  - Parameterized **2-bit Saturating Counter Branch Target Buffer (BTB)**.
  - Easily toggled with `ENABLE_BRANCH_PREDICTOR = 1/0`.
  - Instantaneous recovery from RRAT committed mappings on branch misprediction retirement.
- **Execution Units**:
  - **ALU**: 64-bit integer arithmetic/logic and store effective address/byte-mask computation.
  - **MULT**: 2-cycle pipelined hardware multiplier (`MUL`, `MULH`, `MULHSU`, `MULHU`).
  - **BRANCH**: Direct branch resolution, target evaluation (`JAL` / `JALR`), and predictor training.
  - **LOAD**: Effective address calculation, SQ forwarding query, and byte sign/zero extension.
- **Complete Stage**:
  - Priority Common Data Bus (**CDB**) Arbiter (`MULT > LOAD > BRANCH > ALU`) with ungranted result buffering.

---

## 2. Directory Structure & File Map

The codebase is organized into **`src/`** for RTL modules and **`tb/`** for testbenches:

```text
OOO_processor/
├── Makefile
├── README.md
├── src/
│   ├── defs.v                 # Global constants, RV64 opcodes, funct3, ALU operations
│   ├── branch_predictor.v     # Dynamic 2-bit Saturating Counter BTB (parameter togglable)
│   ├── fetch_stage.v          # PC generation, branch predictor mux, IF/ID register
│   ├── dispatch_stage.v       # RV64IM decoder, hazard detection, register renaming
│   ├── map_table.v            # Speculative RAT (32 entries), CDB tag snooping
│   ├── arch_map_table.v       # Architectural RRAT (32 entries) for committed state
│   ├── free_list.v            # 32-entry Free List FIFO, instantaneous recovery reconstruction
│   ├── physical_regfile.v     # 64-entry x 64-bit PRF with write-forwarding (p0 = 0)
│   ├── rob.v                  # 32-entry circular Reorder Buffer with flat parallel arrays
│   ├── store_queue.v          # 16-entry Store Queue with Store-to-Load forwarding
│   ├── reservation_station.v  # 16 waiting slots, tag snooping, ready issue arbiter
│   ├── issue_stage.v          # PRF operand fetch and muxing (PC / Imm / Register Data)
│   ├── fu_alu.v               # Single-cycle 64-bit ALU & store address/byte alignment
│   ├── fu_mult.v              # 2-cycle pipelined 64-bit multiplier (MUL, MULH)
│   ├── fu_branch.v            # Branch condition tester, JAL/JALR target calculator, BP training
│   ├── fu_load.v              # Load execution, SQ forwarding query, byte extension
│   ├── complete_stage.v       # Priority CDB arbiter and broadcast logic
│   ├── retire_stage.v         # In-order retirement, RRAT commit, Told freeing, recovery
│   ├── core.v                 # Top-level processor core wiring all submodules
│   └── memory.v               # Dual-port unified memory (Port A: fetch, Port B: D-mem)
└── tb/
    └── tb_core.v              # Comprehensive self-checking testbench
```

---

## 3. How to Examine the Pipeline Flow

To trace how an instruction moves through this out-of-order engine:

```
+---------------+     +--------------------+     +------------------------+
|  fetch_stage  | --> |   dispatch_stage   | --> |  reservation_station   |
| (PC, BP, IF)  |     | (Decode, RAT, ROB) |     |  (Waiting slots, CDB)  |
+---------------+     +--------------------+     +------------------------+
                                                              |
                                                    (Operands Ready)
                                                              v
                                                 +------------------------+
                                                 |      issue_stage       |
                                                 |    (PRF Read, Mux)     |
                                                 +------------------------+
                                                              |
                  +---------------+---------------+-----------+
                  |               |               |           |
                  v               v               v           v
             +---------+     +---------+     +---------+ +---------+
             | fu_alu  |     | fu_mult |     |fu_branch| | fu_load |
             | (1 cyc) |     | (2 cyc) |     | (1 cyc) | | (1 cyc) |
             +---------+     +---------+     +---------+ +---------+
                  |               |               |           |
                  +---------------+---------------+-----------+
                                  |
                                  v
                     +------------------------+
                     |     complete_stage     |
                     |      (CDB Arbiter)     |
                     +------------------------+
                                  |
                +-----------------+-----------------+
                | (Tag Broadcast)                   | (Mark ROB Complete)
                v                                   v
+-------------------------------+       +------------------------+
|  RAT & RS tag wake-up, PRF W  |       |      retire_stage      |
+-------------------------------+       | (In-Order ROB Commit)  |
                                        +------------------------+
                                                    |
                                    +---------------+---------------+
                                    |                               |
                              (Normal Commit)              (Mispredicted Branch)
                                    v                               v
                        +-----------------------+       +-----------------------+
                        | RRAT update, Told free|       | Flush pipeline, roll  |
                        | SQ commit to D-Memory |       | back RAT & FreeList   |
                        +-----------------------+       +-----------------------+
```

---

## 4. How to Run Simulations

### A. Run with Branch Predictor ENABLED (Default)
```bash
make sim
```
Runs the test suite using the dynamic 2-bit saturating counter BTB.

### B. Run with Branch Predictor DISABLED (Static Not-Taken)
```bash
make sim_no_bp
```
Runs the test suite with the branch predictor disabled to evaluate baseline performance.

### C. Compare Branch Predictor Performance Directly
```bash
make compare
```
Runs both simulations sequentially and summarizes the IPC and misprediction count:
```
==================================================================
 [1/2] RUNNING WITH BRANCH PREDICTOR ENABLED
==================================================================
   - Total Cycles:          73
   - Retired Instructions:  29
   - Branch Mispredictions: 2
   - Final IPC:             0.397260
   - Final CPI:             2.517241
==================================================================
 [2/2] RUNNING WITH BRANCH PREDICTOR DISABLED
==================================================================
   - Total Cycles:          81
   - Retired Instructions:  29
   - Branch Mispredictions: 4
   - Final IPC:             0.358025
   - Final CPI:             2.793103
==================================================================
```

### D. Assemble and Run Any Custom Assembly Program (`make prog_o`)

You can write any `.s` file into `test_assembly/` (or current directory) and run:
```bash
make prog_o SOURCE=example.s
```
Examples:
```bash
make prog_o SOURCE=test_evens_64.s
make prog_o SOURCE=test_fib_64.s
make prog_o SOURCE=test_hazards_64.s
make prog_o SOURCE=insertion_sort_64.s
```
This automated workflow:
1. Compiles the `.s` file with `riscv64-unknown-elf-gcc` using `linker.ld` (`ENTRY(_start)`, text at `0x0`).
2. Dumps assembly with `riscv64-unknown-elf-objdump` (`program.dump`).
3. Extracts raw binary with `riscv64-unknown-elf-objcopy` (`program.bin`).
4. Converts binary into 64-bit doubleword hexadecimal format with `make_hex.py` (`program.mem`).
5. Executes the Out-of-Order processor, retiring instructions, printing retirement trace, and upon `WFI / HALT` commits, dumps:
   - Total Cycles, Retired Instructions, Branch Mispredictions
   - Final IPC & Final CPI
   - Complete table of committed architectural registers `x0 - x31`.
