# ==============================================================================
# Benchmark Test 3: Multi-Cycle Multiplier Latency Hiding (RV64M)
#
# Comparing 4-Cycle Multiplication in In-Order vs Out-of-Order:
#
# 1. IN-ORDER BEHAVIOR:
#    - Every 'mul' instruction freezes the EX stage for 4 cycles.
#    - The hazard unit forces a 3-cycle pipeline stall (holding PC, IF/ID, ID/EX).
#    - All subsequent independent instructions are completely BLOCKED from
#      executing during those 4 cycles.
#
# 2. OUT-OF-ORDER BEHAVIOR:
#    - 'mul' is issued to the 4-cycle pipelined FU_MULT unit.
#    - Over those 4 cycles, the Issue Stage continues to issue independent
#      ALU, memory, and branch instructions from the Reservation Stations!
#    - The 4-cycle multiply latency is overlapped and hidden by independent work.
# ==============================================================================

.section .text
.globl _start

_start:
    li      x1, 0               # Loop counter i = 0
    li      x2, 10              # Loop limit = 10 iterations

    li      x10, 0x1000         # Destination memory pointer

    # Fixed coefficients
    li      x11, 3              # Multiplier constant A = 3
    li      x12, 5              # Multiplier constant B = 5

    li      x21, 0              # Independent accumulator 1
    li      x22, 0              # Independent accumulator 2

loop:
    # --------------------------------------------------------------------------
    # Multiplier 1: 4 Cycles Latency
    # --------------------------------------------------------------------------
    mul     x5, x1, x11         # x5 = i * 3 (In-Order stalls 3 cycles!)

    # --------------------------------------------------------------------------
    # Independent Arithmetic Stream
    # (OoO executes these out-of-order concurrently while mul is calculating!)
    # --------------------------------------------------------------------------
    addi    x21, x21, 10        # Independent: acc1 += 10
    addi    x22, x22, 20        # Independent: acc2 += 20
    add     x23, x21, x22       # Independent: acc1 + acc2

    # --------------------------------------------------------------------------
    # Multiplier 2: 4 Cycles Latency
    # --------------------------------------------------------------------------
    mul     x6, x1, x12         # x6 = i * 5 (In-Order stalls 3 cycles!)

    # --------------------------------------------------------------------------
    # Dependent Combine & Memory Store
    # --------------------------------------------------------------------------
    add     x7, x5, x6          # x7 = (i * 3) + (i * 5) = i * 8
    add     x8, x7, x23         # x8 = (i * 8) + independent sum
    sd      x8, 0(x10)          # Store result to memory

    # Advance pointer and counter
    addi    x10, x10, 8         # Next memory address
    addi    x1, x1, 1           # i++
    blt     x1, x2, loop        # Loop branch

    wfi
