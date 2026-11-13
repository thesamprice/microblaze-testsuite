/* QEMU's -kernel loads the ELF where it is linked, in the board's DDR.  */
ENTRY (_start)
MEMORY { ram : ORIGIN = 0x90000000, LENGTH = 32M }
SECTIONS
{
  .text : { *(.text*) _etext = .; } > ram
  .rodata : { *(.rodata*) } > ram
  .data : { *(.data*) *(.sdata*) } > ram
  .bss : { __bss_start = .; *(.sbss*) *(.bss*) *(COMMON); . = ALIGN (4); __bss_end = .; } > ram
  . = ALIGN (16);
  _stack_top = . + 0x10000;
}
