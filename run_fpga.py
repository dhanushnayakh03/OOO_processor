#!/usr/bin/env python3
# ==============================================================================
# File: run_fpga.py
# Description: Host verification & control script for Scalar RV64IM OoO Core
#              running on the PYNQ-Z2 FPGA board.
# Usage:
#   python3 run_fpga.py program.mem
#   python3 run_fpga.py --source test_assembly/test_evens_64.s
# ==============================================================================

import os
import sys
import time
import argparse
import subprocess

try:
    from pynq import Overlay
except ImportError:
    Overlay = None


class OoOProcessorFPGA:
    def __init__(self, bitstream="ooo_scalar.bit"):
        if Overlay is None:
            raise RuntimeError(
                "pynq library not found! Please run this script on the PYNQ-Z2 board "
                "or install the pynq package."
            )
        print(f"[PYNQ] Downloading bitstream: {bitstream} ...")
        self.ol = Overlay(bitstream)
        # Find the ooo_axi_wrapper IP core instance
        if hasattr(self.ol, "ooo_axi_wrapper_0"):
            self.ip = self.ol.ooo_axi_wrapper_0
        elif hasattr(self.ol, "ooo_axi_wrapper"):
            self.ip = self.ol.ooo_axi_wrapper
        else:
            # Fallback: find by IP name
            ip_names = [k for k in self.ol.ip_dict.keys() if "ooo" in k.lower()]
            if not ip_names:
                raise RuntimeError(f"Could not find ooo_axi_wrapper IP. Available IPs: {list(self.ol.ip_dict.keys())}")
            self.ip = getattr(self.ol, ip_names[0])
            print(f"[PYNQ] Connected to IP: {ip_names[0]}")

    def reset_core(self):
        """Puts core in reset and clears performance counters"""
        self.ip.write(0x00, 0x3)  # bit 0 = reset, bit 1 = clear perf counters
        time.sleep(0.001)
        self.ip.write(0x00, 0x1)  # keep in reset, release perf counter clear

    def release_core(self):
        """Releases reset to start core execution"""
        self.ip.write(0x00, 0x0)

    def is_halted(self):
        """Checks if WFI / HALT has been committed"""
        status = self.ip.read(0x04)
        return bool(status & 0x1)

    def write_mem_dword(self, byte_addr, dword_val):
        """Writes a 64-bit doubleword to BRAM at byte_addr"""
        lo = dword_val & 0xFFFFFFFF
        hi = (dword_val >> 32) & 0xFFFFFFFF
        self.ip.write(0x14, byte_addr & 0xFFFF)
        self.ip.write(0x18, lo)
        self.ip.write(0x1C, hi)
        self.ip.write(0x20, 0x1)  # Trigger write strobe

    def read_mem_dword(self, byte_addr):
        """Reads a 64-bit doubleword from BRAM at byte_addr"""
        self.ip.write(0x14, byte_addr & 0xFFFF)
        # Wait a tiny moment for synchronous BRAM latching
        lo = self.ip.read(0x24)
        hi = self.ip.read(0x28)
        return (hi << 32) | lo

    def read_arch_reg(self, reg_idx):
        """Reads a committed architectural register x0 - x31"""
        self.ip.write(0x30, reg_idx & 0x1F)
        lo = self.ip.read(0x34)
        hi = self.ip.read(0x38)
        return (hi << 32) | lo

    def load_program_mem(self, mem_file):
        """Loads a .mem hex file into FPGA Block RAM"""
        self.reset_core()
        if not os.path.exists(mem_file):
            raise FileNotFoundError(f"Memory file '{mem_file}' not found!")

        with open(mem_file, "r") as f:
            lines = [l.strip() for l in f if l.strip()]

        count = 0
        for i, line in enumerate(lines):
            val = int(line, 16)
            self.write_mem_dword(i * 8, val)
            count += 1

        print(f"[PYNQ] Successfully loaded {count} doublewords ({count*8} bytes) into BRAM.")

    def run(self, timeout_sec=5.0):
        """Runs the core and waits for WFI / Halt"""
        print("[PYNQ] Releasing processor reset. Running at 50 MHz...")
        start_time = time.time()
        self.release_core()

        while not self.is_halted():
            if time.time() - start_time > timeout_sec:
                print(f"\n[ERROR] Core execution timed out after {timeout_sec} seconds! Halting.")
                self.reset_core()
                return False
            time.sleep(0.001)

        elapsed = time.time() - start_time
        print(f"[PYNQ] Core HALT detected in {elapsed*1000:.2f} ms.")
        return True

    def print_results(self, max_mem_words=2048):
        """Prints performance metrics, registers, and unified memory dump"""
        cycles  = self.ip.read(0x08)
        retired = self.ip.read(0x0C)
        mispred = self.ip.read(0x10)

        print("\n==================================================================")
        print("   SIMULATION SUCCESS: WFI / HALT instruction committed!")
        print("==================================================================")
        print("   Execution Summary:")
        print(f"   - Total Cycles:          {cycles}")
        print(f"   - Retired Instructions:  {retired + 1}")
        print(f"   - Branch Mispredictions: {mispred}")
        if cycles > 0:
            print(f"   - Final IPC:             {(retired + 1.0) / cycles:.6f}")
            print(f"   - Final CPI:             {cycles / (retired + 1.0):.6f}")
        print("==================================================================")
        print("   Committed Architectural Registers (x0 - x31):")
        for i in range(0, 32, 4):
            vals = [self.read_arch_reg(i + j) for j in range(4)]
            print(f"   x{i:02d}: 0x{vals[0]:016x}  x{i+1:02d}: 0x{vals[1]:016x}  "
                  f"x{i+2:02d}: 0x{vals[2]:016x}  x{i+3:02d}: 0x{vals[3]:016x}")
        print("==================================================================")
        print("@@@ Unified Memory contents hex on left, decimal on right: ")
        print("@@@")

        # Read back non-zero memory lines
        for i in range(max_mem_words):
            byte_addr = i * 8
            val = self.read_mem_dword(byte_addr)
            if val != 0:
                print(f"@@@ mem[{byte_addr:5d}] = {val:016x} : {val}")

        print("@@@")
        print("@@@ System halted on WFI instruction\n")


def compile_assembly(asm_path, output_mem="program.mem"):
    """Compiles .s file to .mem using riscv64-unknown-elf toolchain"""
    print(f"[TOOLCHAIN] Assembling {asm_path} ...")
    subprocess.check_call(
        ["riscv64-unknown-elf-gcc", "-march=rv64im", "-mabi=lp64", "-nostdlib",
         "-nostartfiles", "-T", "linker.ld", asm_path, "-o", "program.elf"]
    )
    subprocess.check_call(["riscv64-unknown-elf-objdump", "-d", "program.elf"], stdout=open("program.dump", "w"))
    subprocess.check_call(["riscv64-unknown-elf-objcopy", "-O", "binary", "program.elf", "program.bin"])
    subprocess.check_call(["python3", "make_hex.py", "program.bin", output_mem])
    print(f"[TOOLCHAIN] Generated {output_mem} successfully.")


def main():
    parser = argparse.ArgumentParser(description="Run Scalar RV64IM OoO Processor on PYNQ-Z2")
    parser.add_argument("mem_file", nargs="?", default="program.mem", help="Path to program.mem file")
    parser.add_argument("--source", "-s", default=None, help="Path to .s assembly file to compile & run")
    parser.add_argument("--bitstream", "-b", default="ooo_scalar.bit", help="Path to FPGA bitstream (.bit)")
    parser.add_argument("--timeout", "-t", type=float, default=5.0, help="Execution timeout in seconds")
    args = parser.parse_args()

    mem_target = args.mem_file
    if args.source:
        compile_assembly(args.source, "program.mem")
        mem_target = "program.mem"

    fpga = OoOProcessorFPGA(bitstream=args.bitstream)
    fpga.load_program_mem(mem_target)
    if fpga.run(timeout_sec=args.timeout):
        fpga.print_results()


if __name__ == "__main__":
    main()
