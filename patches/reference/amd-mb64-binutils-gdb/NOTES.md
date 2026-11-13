# AMD 64-bit MicroBlaze port (binutils, gdb): reference only

Issue #53. Copied from Xilinx/meta-xilinx `rel-v2026.2`,
`meta-microblaze/recipes-devtools/{binutils,gdb}/.../mb64/0001-Add-MicroBlaze-64-bit-support.patch`.

Not ours. AMD has to post this upstream itself; our part is review and testing
once our relax/CFI series (#46, #47) has landed, since both touch
`elf32-microblaze.c` relaxation and the relocation numbers (36-43 question, #47).
