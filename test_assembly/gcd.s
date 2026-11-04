.section .text
.globl _start

_start:
    # ------------------------------------------------
    # Load input numbers from memory
    # ------------------------------------------------
    la      x10, num_a
    la      x11, num_b

    ld      x5, 0(x10)          # x5 = A
    ld      x6, 0(x11)          # x6 = B

    # ------------------------------------------------
    # GCD using Euclidean Algorithm
    # A % B is computed using repeated subtraction
    # ------------------------------------------------
gcd_loop:
    beq     x6, x0, gcd_done    # If B == 0, GCD found

    addi    x7, x5, 0           # x7 = A (remainder)

mod_loop:
    bltu    x7, x6, mod_done    # If remainder < B, stop

    sub     x7, x7, x6          # remainder -= B

    jal     x0, mod_loop

mod_done:
    addi    x5, x6, 0           # A = B
    addi    x6, x7, 0           # B = remainder

    jal     x0, gcd_loop

    # ------------------------------------------------
    # Store GCD result into memory
    # ------------------------------------------------

gcd_done:
    la      x10, result
    sd      x5, 0(x10)

    wfi


# ====================================================
# Data Section
# ====================================================

.section .data
.align 3

num_a:
    .dword  48

num_b:
    .dword  18

result:
    .dword  0