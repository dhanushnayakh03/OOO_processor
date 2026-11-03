.section .text.init
.globl _start

_start:
    # Initialize registers
    li   x3, 0          # counter i = 0
    li   x4, 0x1000     # data pointer = 0x1000

loop1:
    andi x31, x3, 1     # check if odd
    bne  x31, x0, loop2 # if odd, skip store

    sd   x3, 0(x4)      # store 64-bit doubleword to memory
    addi x4, x4, 8      # increment pointer by 8 bytes

loop2:
    addi x3, x3, 1      # i = i + 1
    li   x5, 16
    blt  x3, x5, loop1  # repeat while i < 16

    # Finished: Halt processor
    wfi