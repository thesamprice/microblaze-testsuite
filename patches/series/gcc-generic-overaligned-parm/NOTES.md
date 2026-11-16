# gcc-generic-overaligned-parm

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#118. For:
gcc-patches@gcc.gnu.org. One patch, so no cover letter. Not yet sent.

A middle-end change (`gcc/function.cc`), not a MicroBlaze one: it also
fixes mips-elf (o32). gcc-patches will want a bootstrap and regression
test on a primary target (x86_64-linux or aarch64-linux) before it goes
in. That has not been done. From reading the code, nothing should change
on x86: it supports stack realignment, so the condition removed was
already true there.

## Base and dependencies

Commit `448a1320d` on branch `fix/gcc-overaligned-parm`, on gcc master
`df809a029`. No dependencies. It applies unchanged on the runner's stack:
it is `patches/gcc/0026`.

Checks: `contrib/gcc-changelog/git_check_commit.py` OK;
`contrib/check_GNU_style.sh` clean.

## What it does

`gcc.dg/pr84877.c` fails on microblaze-elf at -O2: the address of a
by-value `aligned(16)` struct parameter is only 4-byte aligned.

`assign_parm_adjust_stack_rtl` keeps an incoming stack slot that is less
aligned than the parameter's type when the slot already has
`MAX_SUPPORTED_STACK_ALIGNMENT`, even if the parameter's address is
taken, because a copy could not be aligned any better. `assign_stack_local`
now aligns a slot at run time when its alignment exceeds
`MAX_SUPPORTED_STACK_ALIGNMENT` (that is how over-aligned locals already
work on MicroBlaze), so a copy can be. The patch makes the copy whenever
the parameter's address is taken. Targets that support stack realignment,
where `MAX_SUPPORTED_STACK_ALIGNMENT` is `MAX_STACK_ALIGNMENT`, already
did.

Code for `pr84877.c` `foo` at -O2, cc1 built from `df809a029` for each
target, before and after:

| target | how the struct arrives | `&p` before | after |
|---|---|---|---|
| microblaze-elf | r5-r8, stored to the caller's r5-r10 save area | `r1+72`, 4-byte aligned | run-time aligned copy, `(r1+83)` masked |
| mips-elf (o32) | $4-$7, stored to the caller's save area | `$sp+64`, 8-byte aligned | run-time aligned copy, `($sp+71) & ~15` |
| riscv32-elf | by reference (larger than 2 x XLEN) | caller's copy, 16-byte stack | same code (byte-identical, also for the new test) |
| sparc-elf | by reference | caller's copy, aligned at run time by the caller | not affected |

On MIPS o32 the test passes only when the caller's `sp` happens to be
16-byte aligned. MIPS was only compiled, not run (no MIPS C library
here). pr84877.c is xfailed for `sparc*-*-*`; whether that xfail is
still needed was not checked.

The new test `gcc.dg/torture/overaligned-parm-1.c` covers a struct in
registers, a struct on the stack after eight `int` arguments, an
over-aligned `int` scalar (the `assign_parm_setup_stack` path) and two
structs in one call. It checks each address in a `noipa` function, so the
type's declared alignment cannot fold the check away.

## Testing

MicroBlaze, binutils/newlib/QEMU 10.2.4 from the runner, board
`microblaze-qemu`, `--no-relax`.

Before and after, on `fix/gcc-compile` (`d8df05801`: the runner's gcc
patches plus the audit and compile fixes), big-endian, `compile.exp
execute.exp dg.exp dg-torture.exp microblaze.exp`:

| | before (`d8df05801`) | after |
|---|---|---|
| PASS | 105233 | 105255 |
| FAIL | 60 | 59 |
| UNRESOLVED | 8 | 1 |

The differences: `gcc.dg/pr84877.c execution test` FAIL to PASS, the new
test's 14 PASS, and 7 `global-reg-r20-run.c` scans UNRESOLVED to PASS,
which comes from the before run predating that test's final revision, not
from this patch. No other result changes.

On the runner's stack (`df809a029` plus `patches/gcc/0001`-`0026`),
`execute.exp`, `microblaze.exp`, `dg.exp=pr84877.c` and
`dg-torture.exp=overaligned-parm-1.c`: 25557 PASS, 0 FAIL, 185
UNSUPPORTED, big- and little-endian (`0001`-`0025` gave 25541 on the
first two; the 16 more are pr84877.c and the new test). Big-endian
`compile.exp`: 14668 PASS, 0 FAIL, 312 UNSUPPORTED, as with `0001`-`0025`.

## How to reproduce

Build cc1 for another target from `df809a029` with this patch
(`configure --target=mips-elf --enable-languages=c --without-headers
--with-newlib; make all-gcc`) and compile `gcc.dg/pr84877.c` with
`gcc/cc1 -O2`, replacing `<inttypes.h>` with typedefs for `intptr_t` and
`uintptr_t`. Look at where `foo` takes `&p`.
