# rtems-microblaze-asm-cfi

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#31 (tracker #30).
For: devel@rtems.org / GitLab MR against rtems/rtos/rtems.

Base: RTEMS `origin/main` 53d56d9494b25ddaf22d6c2868bdcb51d66ae545
(fetched 2026-11-12). Branch `rtems-new-asm-cfi` in worktree
`work/src/rtems-new-asm-cfi`.

## Patches

1. `microblaze: Add CFI macros for the assembly code`: new option
   `spec/build/cpukit/optmicroblazeasmcfi.yml` that compiles
   `__asm__(".cfi_startproc\n.cfi_endproc")` at configure time and defines
   `MICROBLAZE_ASM_CFI` in cpuopts.h; `CFI_*` macros in the MicroBlaze
   `<rtems/asm.h>` that expand to nothing otherwise; `CFI_INTERRUPTED_FRAME()`
   for interrupt/exception frames (signal frame, return column 36,
   `DW_CFA_val_expression` = saved PC - 8 because libgcc adds
   RETURN_ADDR_OFFSET 8).
2. `microblaze: Add CFI to the context functions`: context switch/restore,
   validate, volatile clobber; r15 undefined in the resume functions.
3. `microblaze: Always build the ISR stack frame`: code change in
   `_ISR_Handler` so both paths (switch / already on interrupt stack) build the
   ISR stack frame; return path always reloads r1 from it.
4. `microblaze: Add CFI to the interrupt entry`: `_interrupt_handler` and
   `_ISR_Handler`, including a `DW_CFA_def_cfa_expression` while the ISR stack
   frame is in place.
5. `bsps/microblaze: Add CFI to the exception entries`: exception/debug entries,
   plus `braid` -> `bralid r15` to the C handler so the walk enters the entry's
   FDE (handlers end in rtems_fatal()).
6. `bsps/microblaze: Add CFI to the start code`: `_crtinit` frame, r15
   undefined in `_start1`.
7. `microblaze: Start threads at the entry point`: bug fix found on the way;
   `context->r15 = entry_point` with `rtsd r15, 8` started threads 8 bytes into
   `_Thread_Handler`, skipping `addik r1,r1,-48; swi r15,r1,0` (disassembly in
   the commit). SPARC precedent: `o7 = entry_point - 8`
   (cpukit/score/cpu/sparc/cpu.c:282).
8. `microblaze: End the unwind at the start of a thread`: new asm
   `_MicroBlaze_Thread_start` (entry point in r19, CFI_UNDEFINED(r15)); without
   it a walk past `_Thread_Handler` repeated the frame of `_Thread_Get` until
   the buffer was full (observed).

## Design / precedent

- Guard: glibc's 0008 uses a configure probe (`HAVE_MICROBLAZE_ASM_CFI`); same
  idea here with RTEMS waf `script` action (precedent for `script` options:
  `spec/build/cpukit/optgcc.yml`). `__GCC_HAVE_DWARF2_CFI_ASM` (libitm
  `asmcfi.h`, libsanitizer) was rejected: GCC never defines it for MicroBlaze
  because `ASM_PREFERRED_EH_DATA_FORMAT` gives `DW_EH_PE_aligned`
  (gcc/config/microblaze/microblaze.h:208) and `dwarf2out_do_cfi_asm()` then
  returns false. Checked: GCC master built against a CFI-capable gas
  (`work/install`) does not define it even with `-g`.
- The probe runs in the cpukit configure stage, before BSP ABI_FLAGS are known,
  so it cannot see `-B` style flags in ABI_FLAGS. Fine for a real toolchain.
- Return address: GCC `DWARF_FRAME_RETURN_COLUMN` r15,
  `DWARF_ALT_FRAME_RETURN_COLUMN` 36, `RETURN_ADDR_OFFSET` 8
  (microblaze.h:176-196); libgcc's linux-unwind.h also uses column 36 for the
  signal frame PC.
- No RTEMS precedent: only `bsps/x86_64/amd64/start/start.S` has `.cfi_*`
  (issue #31 said zero; it did not check x86_64).

## Testing (exact)

BSP `microblaze/petalogix_s3adsp1800` (upstream QEMU machine), QEMU
`work/build/qemu/qemu-system-microblazeel-unsigned`, `BUILD_SPTESTS` +
`BUILD_SAMPLES` (235 programs, `.norun` excluded), runner: own script, 4 in
parallel, 120 s timeout, host load average 50-220 during the runs.

Toolchains: "old" = `~/rtems/7` (GCC 12.4.1, Xilinx binutils 2.36.1,
RSB 105f43d). "CFI" = same GCC with `-B` to `work/install` microblaze-elf `as`
and `ld` (binutils master 19c3a4c423b + `patches/binutils` series). Probe
result: old "no", CFI "yes".

| build | pass | fail | timeout |
|---|---|---|---|
| unpatched (origin/main), old tools | 220 | 7 | 8 |
| series, old tools | 222 | 8 | 5 |
| series, CFI tools | 214 | 8 | 13 |

Programs not passing in a patched run but passing unpatched were rerun alone
(300 s): sp53, sppps01, sp01, sp05, spedfsched01, spnsext01 pass in all
builds; cdtest hangs in the CFI build after the first C++ throw
(passes with old tools). The same hang occurs with the CFI tools on a tree
without this series (origin/main + backtrace RFC, samples only), so it comes
from mixing GCC 12's libgcc/libstdc++ with the new ld, not from the series; sp04 fails intermittently in both patched builds (cfi-old 2/4,
cfi-new 1/4 failing; unpatched 4/4 pass). sp04's one-tick timer can fire
before TA1 (prio 1) blocks, so HIGH runs before LOW; I believe this is a race
exposed by changed timing, **not proven**. spnsext01 also failed once
unpatched (timecounter going backwards under load).

Object code check (old tools, before patches 7/8 existed): only
`_exception_handler.o`, `_debug_sw_break_handler.o` and `cpu_asm.o` .text
changed versus unpatched; no `.eh_frame` in any asm object.

CFI check: `readelf --debug-dump=frames-interp` on cpu_asm.o (CFI tools)
shows CFA r1+56 / r4+56 / exp / r1+56 / r1+0 at offsets 0/0x4c/0x54/0x8c/0xfc,
matching the instructions in the linked hello.exe.

Unwind demonstration: see `../rtems-microblaze-backtrace-rfc/demo/`. With
the series + backtrace RFC + `-fasynchronous-unwind-tables`, walks from a
timer service routine (through `_ISR_Handler`), and from fatal extensions
after `brki r17,0x8` / `brki r16,0x18` (through `_exception_handler` /
`_debug_sw_break_handler`) reach the interrupted function and end at
`_MicroBlaze_Thread_start`.

## Not tested

- Hardware exceptions (unaligned, illegal opcode, divide) - only `brki`
  software exceptions; exceptions in a delay slot (PC from BTR) are not
  handled specially: the reported PC is r17.
- Nested interrupts (path changed by 3/8 never exercised: nothing re-enables
  interrupts in an ISR on this BSP).
- kcu105 / kcu105_qemu (needs Xilinx QEMU); big-endian.
- Linker relaxation of CFI: rules after an advance_loc are wrong if ld relaxes
  an instruction before them; the `_Per_CPU_Information` accesses are not
  relaxed at 0x80000000/0x90000000. Upstream binutils relax-safe CFI
  (patches/binutils 0011/0012) not assumed.
- With GCC 15.2 / binutils 2.47 from the RSB series (#15, host load ~20):
  probe "no", builds with 0 warnings, 230 pass / 4 fail / 1 timeout vs
  231 / 2 / 2 unpatched with the same tools. Reruns alone: sp04 pass,
  spfatal12 pass, sptimecounter03 FAIL in the series build (passes
  unpatched; not investigated, timing test), cdtest hangs in both (linker
  relaxation, see RSB NOTES). This toolchain cannot exercise the CFI itself.

## Findings / open questions

- The patched gas (relax-safe CFI series) leaves fake labels `L0\001` and
  `$LCFI*`/`$LBB*` in the symbol table; addr2line then names functions "L0"
  (seen in all demo backtraces). Worth reporting against the binutils series.
- `_CPU_Context_validate` uses r3 instead of the argument register r5 and
  returns with `bra r15` (not `rtsd r15, 8`); not fixed here.
- The ISR nested path previously let `bsp_interrupt_dispatch()` use the saved
  r4-r9 slots as its argument home area; 3/8 fixes it as a side effect.
- Commit trailer: no RTEMS GitLab issue number exists; add `Update #NNNN` if
  one is opened.
