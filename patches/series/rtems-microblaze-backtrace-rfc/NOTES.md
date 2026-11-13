# rtems-microblaze-backtrace-rfc

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#32 (tracker #30).
For: devel@rtems.org / GitLab MR, marked RFC (`[RFC PATCH n/2]`).

Base: RTEMS `origin/main` 53d56d9494b25ddaf22d6c2868bdcb51d66ae545.
Branch `rtems-new-backtrace` (worktree `work/src/rtems-new-backtrace`).
Independent of the CFI series textually; the demonstration combined both in
branch `rtems-new-combo` (worktree `work/src/rtems-new-combo`, which also has
uncommitted demo tests `btdemo1..3`, copied to `demo/`).

## Patches

1. `libmisc: Add rtems_backtrace()`: `<rtems/backtrace.h>`,
   `cpukit/libmisc/backtrace/backtrace.c`, `spec/build/cpukit/objbacktrace.yml`
   (built with `-funwind-tables`, linked into librtemscpu).
   `int rtems_backtrace(void **addresses, int size)` (glibc `backtrace()`
   signature) and `void rtems_backtrace_print(void)` (printk, for
   rtems-addr2line). Uses `_Unwind_Backtrace()`/`_Unwind_GetIPInfo()`; skips
   its own frame; reports pc-1 for normal frames, exact pc for signal frames.
2. `libtests/backtrace01: New test`: f1->f2->f3 nested, asserts order, size
   limit, size 0. Built with `-funwind-tables`.

The cover letter explains the choices (unwinder, unwind tables, API shape,
symbolization, fatal-path integration) and the alternatives.

## Testing (exact)

petalogix_s3adsp1800, upstream QEMU (qemu-system-microblazeel).

- RTEMS 7 tools (`~/rtems/7`, GCC 12.4.1, Xilinx binutils 2.36), backtrace
  branch alone, BUILD_LIBTESTS: backtrace01 PASS; print shows
  `Init init.c:113` then `_Thread_Entry_adaptor_numeric` (walk ends one
  frame into RTEMS, which has no unwind tables).
- Combo (CFI series + this RFC), CFI-capable as/ld via `-B` (binutils master
  19c3a4c423b + patches/binutils), `OPTIMIZATION_FLAGS = -O2 -g
  -fasynchronous-unwind-tables`: backtrace01 PASS, walk ends at
  `_MicroBlaze_Thread_start`. Demos (`demo/demo-output.txt`, symbolized with
  microblaze-rtems7-addr2line):
  - btdemo3: timer service routine -> watchdog -> clock handler ->
    bsp_interrupt_dispatch -> `_ISR_Handler` -> g2 (busy loop, exact PC) ->
    g1 -> Init -> ... -> `_MicroBlaze_Thread_start` (16 frames).
  - btdemo1: fatal extension after `brki r17, 0x8` -> rtems_fatal ->
    `_exception_handler` -> g2 (the brki line) -> g1 -> Init -> ... (12).
  - btdemo2: same with `brki r16, 0x18` via `_debug_sw_break_handler` (12).
  "L0" in place of the asm function names is a symbol-table artefact of the
  patched gas (see CFI series NOTES).

## What is not demonstrated

- Upstream toolchain: no released binutils accepts MicroBlaze CFI (2.47
  checked: no `TARGET_USE_CFIPOP` in tc-microblaze.h), so walks through RTEMS
  asm need the not-yet-upstream gas patch (binutils 0003, issue #20).
- The GCC 15 / binutils 2.47 toolchain from the RSB series: not tested with
  this RFC.
- Hardware exceptions; any non-MicroBlaze architecture (code is generic;
  not built for ARM/others).
- .eh_frame size cost of `-fasynchronous-unwind-tables` for cpukit: not
  measured.

## Open questions (for the RFC discussion)

- RTEMS-native API vs `<execinfo.h>`; callable API vs fatal extension;
  build option for unwind tables vs user CFLAGS; offline vs on-target
  symbolization. All in the cover letter.
- Whether `rtems_backtrace_print()` should accept a starting depth or
  print to a `rtems_printer`.
