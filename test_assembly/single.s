.section .text
.globl _start

_start:
    # Set up operands
    addi x1, x0, 7
    addi x2, x0, 9

    # Multiplier instruction under test (4 cycles pipelined)
    mul  x3, x1, x2

    # Halt
    wfi

.section .data
.align 3
test_data:
    .dword 0x0000000000000000
