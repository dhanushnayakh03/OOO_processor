.section .text
.globl _start

_start:
    li   x1, 12           # x1 = 12
    li   x2, 15           # x2 = 15

    # Multiply 1: 12 * 15 = 180 (Takes 4 cycles!)
    mul  x3, x1, x2       # x3 = 180

    # Independent instructions that OoO issues & executes while mul is in-flight!
    addi x10, x0, 100     # Independent
    addi x11, x0, 200     # Independent
    add  x12, x10, x11    # Independent (x12 = 300)

    # Multiply 2: 7 * 8 = 56 (Takes 4 cycles!)
    li   x4, 7
    li   x5, 8
    mul  x6, x4, x5       # x6 = 56

    # Dependent on both multiplies:
    add  x7, x3, x6       # x7 = 180 + 56 = 236

    # Store result to memory at 0x1000
    li   x20, 0x1000
    sd   x7, 0(x20)       # mem[0x1000] = 236

    wfi
