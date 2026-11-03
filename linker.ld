/* Linker script for RV64 Bare-Metal Core */
OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x00000000;
  .text : {
    *(.text.init)
    *(.text.prologue)
    *(.text)
    *(.text.*)
  }

  . = ALIGN(0x1000);
  .rodata : {
    *(.rodata)
    *(.rodata.*)
  }

  .data : {
    *(.data)
    *(.data.*)
    *(.sdata)
    *(.sdata.*)
  }

  .bss : {
    *(.bss)
    *(.bss.*)
    *(.sbss)
    *(.sbss.*)
  }

  _end = .;
}
