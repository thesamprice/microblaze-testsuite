/* Vectors in the LMB BRAM at 0, everything else in the board's DDR.
   QEMU's -kernel loads both segments and starts at _start.  */
ENTRY (_start)
MEMORY { bram : ORIGIN = 0, LENGTH = 0x100
         ram : ORIGIN = 0x90000000, LENGTH = 32M }
SECTIONS
{
  .vectors : { KEEP (*(.vectors)) } > bram
  .text : { *(.text*) } > ram
  .rodata : { *(.rodata*) } > ram
  .data : { *(.data*) *(.sdata*) } > ram
  .bss : { __bss_start = .; *(.sbss*) *(.bss*) *(COMMON); . = ALIGN (4); __bss_end = .; } > ram
  . = ALIGN (16);
  _stack_top = . + 0x10000;
}
