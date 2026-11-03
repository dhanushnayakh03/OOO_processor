.section .text.init
.globl _start

# ============================================================================
# Compute first 10 Fibonacci numbers and store them in memory starting at 0x1000
# F(0)=0, F(1)=1, F(2)=1, F(3)=2, F(4)=3, F(5)=5, F(6)=8, F(7)=13, F(8)=21, F(9)=34
# ============================================================================

_start:
    li   x1, 0          # F(n-2) = 0
    li   x2, 1          # F(n-1) = 1
    li   x3, 0x1000     # Memory pointer

    # Store F(0) and F(1)
    sd   x1, 0(x3)      # mem[0x1000] = 0
    sd   x2, 8(x3)      # mem[0x1008] = 1
    addi x3, x3, 16     # advance pointer

    li   x4, 2          # counter = 2
    li   x5, 10         # limit = 10

fib_loop:
    add  x6, x1, x2     # F(n) = F(n-1) + F(n-2)
    sd   x6, 0(x3)      # store F(n)
    addi x3, x3, 8      # advance pointer

    # Shift for next iteration
    addi x1, x2, 0      # F(n-2) = F(n-1)
    addi x2, x6, 0      # F(n-1) = F(n)

    addi x4, x4, 1      # counter++
    blt  x4, x5, fib_loop

    # Halt
    wfi
