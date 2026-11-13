# gdb-sim-microblaze-rslr

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#52

Upstream base: binutils-gdb master `b6272d0e90717f2b96a748feaba7c5d41fe4ac15`
("Automatic date update in version.in", 2026-11-13).

Send to: gdb-patches@sourceware.org (sim/ is part of the gdb tree; sim
maintainer for MicroBlaze per the issue: Michael Eager).  Not binutils@.

## Patch

`0001-sim-microblaze-give-SLR-and-SHR-their-own-storage.patch`

- `sim/microblaze/microblaze.h`: `SA` (the special register `mts`/`mfs`
  access) was `CPU.spregs[IMM & 0x1]`, so SPR 0x800 (SLR) and 0x802 (SHR)
  hit the PC.  It now selects `CPU.slr`/`CPU.shr` for those two SPR
  numbers (low 14 bits of the immediate) and keeps the old behaviour for
  every other number.
- `sim/microblaze/microblaze-sim.h`: two new fields `slr`, `shr` placed
  after `spregs[2]`, so `microblaze_reg_fetch`/`microblaze_reg_store`
  (indexed `rn - NUM_REGS`, `NUM_SPECIAL` = 2) are unchanged.
- `sim/testsuite/microblaze/spr-slr-shr.s`: new test.  Writes the address
  of a branch-to-fail to each register; with the bug the `mts` jumps
  there (PC = value, then +4, so both slots branch to fail).  Then reads
  both back with `mfs` and compares.

Precedent/idiom: none copied.  The Xilinx patch (meta-xilinx rel-v2026.2
gdb mb32/0001, Aayush Misra) was read only to confirm the bug; this fix
was written from the bug.  It does not include that patch's unrelated
`tracing`/MB_SIM_TRACE hunk.

The issue text says newlib's crti.S does the `mts`; it is actually
libgcc's `libgcc/config/microblaze/crti.S` (`__init`: `mts rshr, r11`,
`mts rslr, r11`).  The commit message says libgcc.  I grepped
gcc/libgcc/config/microblaze and newlib/libgloss/microblaze in
work/src: those two are the only `mts` instructions, which is the basis
for "nothing in libgcc or newlib writes them [the other SPRs]".

## Testing (macOS arm64 host, build dir work/build/binutils-new/elf,
configured --target=microblaze-elf --enable-sim)

- `make check-sim` (serial; `-j8` fails in sim's check-DEJAGNU-parallel
  on this host, a harness problem, not a test failure):
  - base: `PASS: microblaze fail.s`, `PASS: microblaze pass.s` (2 passes)
  - patched: the same two plus `PASS: microblaze spr-slr-shr.s` (3 passes)
  - the 5 sim "common" unit tests pass in both runs.
- The new test against the unpatched sim, run by hand
  (`as-new`/`ld-new`/`run`): prints `fail`, exit status 1.
- newlib hello world through `sim/microblaze/run`, linked with the
  installed toolchain (work/install, gcc 17.0.0 20261107 + newlib) and a
  scratch replacement for libxil.a whose `outbyte` uses the sim's write
  syscall (`brki r14, 8`, r12 = 5, as testutils.inc does), because the
  installed libxil.a writes to the QEMU board's UART at 0x84000000 which
  the sim does not map:
  - unpatched sim: no output, killed by `timeout 30` (status 137)
  - patched sim: prints `hello, world`, exit status 0
- gas/ld/binutils suites: not affected (sim-only change); not rerun.

## Untested / open

- gdb itself was not built (`--disable-gdb`), so no gdb.base run on the
  sim target.  gdb still cannot read SLR/SHR through the sim
  (`microblaze_reg_fetch` only knows r0-r31, PC, MSR); exposing them
  would mean matching gdb's MICROBLAZE_REG_SLR/SHR numbers (51/50) and is
  left out.
- Other SPRs (EAR 0x3, ESR 0x5, FSR 0x7, BTR 0xb, EDR 0xd) still alias
  the MSR, and PVRs etc. alias the PC or MSR by low bit.  Not touched;
  said so in the commit message.
- The sim check-DEJAGNU-parallel failure with `make -j8 check-sim` was
  not investigated.
- binutils-gdb policy on LLM-written code applies to gdb too; the
  human sending this should decide.  `Assisted-by:` is in the trailer;
  `Signed-off-by:` must be added by the sender.
