.section .text.init
.globl _start

# ============================================================================
# Hazard Verification Program:
# 1. Back-to-back RAW Data Hazards (tests EX/MEM -> EX and MEM/WB -> EX forwarding)
# 2. Load-Use Data Hazard (tests 1-cycle stall bubble)
# 3. Branch Squashing (tests 2-instruction flush on taken branch)
# ============================================================================

_start:
    # --- Test 1: RAW Data Forwarding (EX->EX) ---
    li   x1, 10
    li   x2, 20
    add  x3, x1, x2     # x3 = 30 (Computed in EX)
    sub  x4, x3, x1     # x4 = 20 (Immediately uses x3! Must forward from EX/MEM)
    xor  x5, x4, x3     # x5 = 20 ^ 30 = 10 (Uses x4 from EX/MEM, x3 from MEM/WB)

    # --- Test 2: Load-Use Hazard Stall ---
    li   x12, 0x1000
    sd   x5, 0(x12)     # Store 10 to 0x1000
    ld   x6, 0(x12)     # Load 10 into x6
    addi x7, x6, 5      # x7 = 15 (Immediately uses x6! MUST STALL 1 cycle!)

    # --- Test 3: Branch Squashing ---
    li   x8, 15
    beq  x7, x8, branch_target # 15 == 15 -> TAKEN!
    addi x9, x0, 99     # Should be SQUASHED!
    addi x10, x0, 99    # Should be SQUASHED!

branch_target:
    li   x11, 42        # Executed! x11 = 42
    sd   x7, 8(x12)     # Store 15 to 0x1008
    sd   x11, 16(x12)   # Store 42 to 0x1010

    # Halt
    wfi
