# ==============================================================================
# Benchmark Test 2: Demonstrating Out-of-Order (OoO) Architectural Advantages
#
# Key Features that penalize In-Order but accelerate in Out-of-Order:
# 1. LOAD-USE LATENCY HIDING:
#    - In-Order: Each load immediately followed by a dependent instruction stalls
#      the entire 5-stage pipeline for 1 bubble cycle.
#    - Out-of-Order: Dependent instructions wait in Reservation Stations (RS);
#      subsequent independent instructions (pointers, counters, next loads) bypass
#      and execute immediately out-of-order!
#
# 2. FALSE DEPENDENCY ELIMINATION (WAR / WAW via Register Renaming):
#    - Stream 1 and Stream 2 both intentionally reuse temporary registers x5, x6.
#    - In-Order: Reusing registers creates false anti- and output-dependencies.
#    - Out-of-Order: Map Table & Free List rename x5/x6 to separate physical
#      registers (e.g. p34, p35 vs p37, p38), allowing parallel execution!
#
# 3. DYNAMIC 2-BIT BRANCH PREDICTION (BTB):
#    - In-Order: Every taken loop branch incurs a 2-cycle pipeline squash penalty
#      (15 iterations x 2 = 30 wasted cycles!).
#    - Out-of-Order: The 2-bit BTB saturating counter quickly predicts TAKEN with
#      ZERO bubble cycles!
# ==============================================================================

.section .text
.globl _start

_start:
    # Initialize array pointers and constants
    la      x10, array_a        # Base pointer for Array A (0x1000)
    la      x11, array_b        # Base pointer for Array B (0x1080)
    li      x12, 0x1100         # Destination pointer for Array C (0x1100)

    li      x1, 0               # Loop counter i = 0
    li      x2, 16              # Loop limit = 16 iterations

loop:
    # --------------------------------------------------------------------------
    # Stream 1: Process element from Array A
    # --------------------------------------------------------------------------
    ld      x5, 0(x10)          # Load A[i]
    slli    x6, x5, 2           # [LOAD-USE RAW]: In-Order STALLS 1 cycle!
    addi    x7, x6, 7           # x7 = (A[i] << 2) + 7

    # --------------------------------------------------------------------------
    # Stream 2: Process element from Array B (Reusing registers x5, x6!)
    # --------------------------------------------------------------------------
    ld      x5, 0(x11)          # [WAR / WAW on x5]: Renamed to new PRF tag in OoO!
    addi    x6, x5, 13          # [LOAD-USE RAW]: In-Order STALLS 1 cycle! (x6 renamed)

    # --------------------------------------------------------------------------
    # Combine results and store to Array C
    # --------------------------------------------------------------------------
    xor     x8, x7, x6          # Combine Stream 1 and Stream 2
    sd      x8, 0(x12)          # Store C[i] = x8

    # --------------------------------------------------------------------------
    # Independent Bookkeeping (Executes Out-of-Order while loads are in flight!)
    # --------------------------------------------------------------------------
    addi    x10, x10, 8         # Advance Array A pointer
    addi    x11, x11, 8         # Advance Array B pointer
    addi    x12, x12, 8         # Advance Array C pointer
    addi    x1, x1, 1           # Increment counter: i++

    # --------------------------------------------------------------------------
    # Loop Branch: Taken 15 times, not taken on 16th
    # - In-Order: Flushes IF/ID and ID/EX (2 wasted cycles per taken branch = 30 cycles!)
    # - OoO BTB:  Predicts TAKEN at Fetch stage with 0 bubble cycles!
    # --------------------------------------------------------------------------
    blt     x1, x2, loop

    # Finish simulation
    wfi

# ==============================================================================
# Data Section: Arrays A and B (16 quadwords each = 128 bytes each)
# ==============================================================================
.section .data
.align 3

array_a:
    .dword  1,  2,  3,  4,  5,  6,  7,  8
    .dword  9, 10, 11, 12, 13, 14, 15, 16

array_b:
    .dword  10, 20, 30, 40, 50, 60, 70, 80
    .dword  90, 100, 110, 120, 130, 140, 150, 160
