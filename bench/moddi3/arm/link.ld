/* micro:bit (nRF51822): 256 KB flash at 0, 16 KB RAM at 0x20000000.
   The libgcc objects, lg-*.o, go together between __lg_lo and __lg_hi,
   the range armcount.c counts.  */
MEMORY
{
  flash (rx) : ORIGIN = 0, LENGTH = 256K
  ram (rwx)  : ORIGIN = 0x20000000, LENGTH = 16K
}
ENTRY (Reset_Handler)
SECTIONS
{
  .vectors : { KEEP (*(.vectors)) } > flash
  .lg : { __lg_lo = .; *lg-*.o(.text .text.*) . = ALIGN (4); __lg_hi = .; } > flash
  .text : { *(.text .text.*) *(.rodata .rodata.*) } > flash
  .ARM.exidx : { *(.ARM.exidx*) } > flash
  .data : { *(.data .data.*) } > ram
  ASSERT (SIZEOF (.data) == 0, "bench: initialised RAM data is not copied")
  .bss : { __bss_start = .; *(.bss .bss.* COMMON) __bss_end = .; } > ram
}
