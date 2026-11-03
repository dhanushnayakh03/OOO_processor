# ============================================================================
# RV64I Insertion Sort
#
# Formatted with clean separation:
#   .section .text -> Instructions begin at 0x0000 (_start)
#   .section .data -> Array data begins at 0x1000 (4096)
# ============================================================================

.section .text
.globl _start

_start:
    li      x6, 1               # i = 1
    la      x10, array          # Base address of array
    addi    x10, x10, 8         # x10 points to a[1] (i=1)
    li      x22, 16             # Array length = 16 elements

iloop:
    ld      x4, 0(x10)          # temp = a[i]
    addi    x7, x6, 0           # j = i
    addi    x20, x10, 0         # pointer to a[j]
    addi    x19, x20, -8        # pointer to a[j-1]

jloop:
    ld      x15, 0(x19)         # load a[j-1]
    sltu    x12, x15, x4        # if (a[j-1] < temp) break
    bne     x12, x0, ifinish

    sd      x15, 0(x20)         # a[j] = a[j-1]

    addi    x19, x19, -8        # point to previous element (j-2)
    addi    x20, x20, -8        # point to previous position (j-1)

    addi    x7, x7, -1          # j--
    beq     x7, x0, ifinish     # if (j == 0) break
    j       jloop

ifinish:
    sd      x4, 0(x20)          # a[j] = temp
    addi    x10, x10, 8         # advance pointer to next element a[i+1]
    addi    x6, x6, 1           # i++

    blt     x6, x22, iloop      # loop while i < 16

    # Finished: Halt processor
    wfi


# ============================================================================
# Data Section: Array located at address 0x1000 (4096 decimal)
# ============================================================================
.section .data
.align 3

array:
    .dword  3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5, 8, 9, 7, 9, 3