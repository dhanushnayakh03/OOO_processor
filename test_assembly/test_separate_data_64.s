# ============================================================================
# Example: Separate .text and .data Sections
#
# Notice:
# 1. NO "j start" or "nop" needed at the beginning!
# 2. Code lives cleanly in .text (starts at address 0x0000)
# 3. Data lives cleanly in .data (starts at address 0x1000 = 4096)
# ============================================================================

.section .text
.globl _start

_start:
    # Load base addresses of our data arrays (defined in .data below)
    la   x1, my_input       # x1 points to my_input (address 0x1000 / 4096)
    la   x2, my_output      # x2 points to my_output (address 0x1020 / 4128)

    li   x3, 0              # Loop index i = 0
    li   x4, 4              # Array size = 4 elements

loop:
    ld   x5, 0(x1)          # Load input[i]
    addi x6, x5, 100        # Transform: output[i] = input[i] + 100
    sd   x6, 0(x2)          # Store to output[i]

    addi x1, x1, 8          # Advance input pointer by 8 bytes
    addi x2, x2, 8          # Advance output pointer by 8 bytes
    addi x3, x3, 1          # i++
    blt  x3, x4, loop       # Repeat while i < 4

    # Done: Halt processor
    wfi


# ============================================================================
# Data Section: Everything here is placed at address 0x1000 (4096 decimal)
# ============================================================================
.section .data
.align 3

my_input:
    .dword 10, 20, 30, 40   # 4 elements: 10, 20, 30, 40

my_output:
    .dword  0,  0,  0,  0   # Destination buffer initialized to 0
