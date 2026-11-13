# glibc-microblaze-runtime

All eight MicroBlaze glibc patches, rebased onto current glibc master
and ordered so that every patch builds.  The same patches are also split
into one directory per upstream submission (see "How to send" below);
those are what should go to libc-alpha.  This directory is the
integration view: apply it in order to get the tree that was tested.

- **Issues:** #12, #18, #19, #28, #29, #25, #27 in
  thesamprice/rtems-microblaze-linker-relaxation-bug.  #16 (testsuite
  baseline) is not addressed; see "Not tested".
- **Upstream base:** glibc master `30f5c72a42` ("AArch64: Fix libmvec
  archive member collisions [BZ #34946]"), fetched 2026-11-12.
- **Branch:** `glibc-microblaze-runtime` in the worktree
  `work/src/glibc-new` (clone `/Volumes/3092583379/src/claude-mb/glibc`).
- **Source:** `outbox/glibc/0001-0009` of the issues repo.  0005 ("elf:
  Terminate the .eh_frame section of ld.so") is dropped: upstream fixed
  it in `ae3f5c9cfbf` ("elf: Add a zero terminator to the .eh_frame
  section of ld.so").

## The patches

| # | subject | issue | old outbox | applies to master alone |
|---|---|---|---|---|
| 1 | microblaze: Use the generic ____longjmp_chk | #12 | 0001 | yes |
| 2 | microblaze: Pass _dl_fini to __libc_start_main | #18 | 0002 | yes |
| 3 | microblaze: Fix __syscall_cancel_arch stack arguments | #19 | 0003 | yes |
| 4 | microblaze: Tail-call __syscall_do_cancel | #19 | 0004 | yes |
| 5 | microblaze: Disable libm exception and rounding tests | #28 | 0006 | yes |
| 6 | microblaze: Implement the ucontext functions | #29 | 0007 | yes |
| 7 | microblaze: Add CFI to the assembly sources | #25 | 0008 | no: needs 2 and 6 |
| 8 | microblaze: Use the generic backtrace | #27 | 0009 | yes (no effect without 7) |

"Applies alone" was checked with `git apply --cached --check` of each
generated patch against a pristine `30f5c72a42` index.  7 applies to
master + 2 + 6.

### What each does, and what changed from the outbox version

1. Deletes the two-instruction `____longjmp_chk` stub (it returns to its
   own call, so every fortified longjmp loops) and adds
   `sysdeps/microblaze/jmpbuf-offsets.h` with `JB_FRAME_ADDRESS`, so the
   generic `sysdeps/unix/sysv/linux/____longjmp_chk.c` is used.
   Precedent: `sysdeps/riscv/jmpbuf-offsets.h`,
   `sysdeps/loongarch/jmpbuf-offsets.h`.  Changed: subject only.
2. `_start` passes `r15 + 8` (`_dl_fini`, left in r15 by
   `_dl_start_user`) as rtld_fini when r15 is non-zero.  Changed:
   subject only.
3. `__syscall_cancel_arch` loads arguments 5 and 6 from r1+28/32.
   Changed: subject (was 56 characters in lower case), message reworded,
   ChangeLog block dropped (glibc commits no longer carry one).
4. `brlid r15,__syscall_do_cancel` becomes `brid`.  Changed: subject,
   message reworded, ChangeLog block dropped, author unified to
   "Samuel Price" (the outbox had "Sam Price" on this one).
5. Adds `math-tests-exceptions.h` and `math-tests-rounding.h` as arc,
   riscv, loongarch and or1k nofpu do.  Changed: subject only.
6. getcontext/setcontext/swapcontext in assembly, makecontext in C,
   `ucontext_i.sym`.  Changed:
   - The `gen-as-const-headers` block is appended after the
     `THP-PAGE-SIZE` block that `60b925c18fe` added to
     `sysdeps/unix/sysv/linux/microblaze/Makefile` (the rebase over
     60b925c1 the task asked for).
   - **Bug fix:** setcontext and swapcontext used r19 (callee-saved) to
     hold ucp across rt_sigprocmask, and on failure branched to
     `SYSCALL_ERROR_LABEL` with the caller's r19 clobbered.  They now
     store the caller's r19 in the r5 save slot at r1+4 (which the
     caller reserves: `REG_PARM_STACK_SPACE` and
     `OUTGOING_REG_PARM_STACK_SPACE` in gcc/config/microblaze/microblaze.h,
     the same area 3/8 relies on) and reload it in the delay slot of the
     branch to the error handler.  No frame and no CFA change, so no CFI
     is needed for it.
   - The comment on the two `nop`s before `__startcontext` now cites the
     sparc precedent: sparc32 (BZ #22919) and sparc64 `34eefd0d14b`
     (BZ #34978, merged 2026-11-08) pad `__start_context` for the same
     reason.
   - The patch no longer contains any `cfi_*` macro.  Without 7 those
     macros expand to real `.cfi_*` directives, which released binutils
     rejects, so 6 must not use them.
   - makecontext.c comment: box alignment and a full stop.
7. CFI.  Changed:
   - The `setcontext.S` hunk (`cfi_undefined (r15)` in `__startcontext`)
     stays here, which is why 7 needs 6.  This is the ordering fix the
     task asked for; see "Ordering" below.
   - The configure gate was already in the outbox patch (probe
     `libc_cv_microblaze_asm_cfi`, `HAVE_MICROBLAZE_ASM_CFI` in
     config.h.in, the `cfi_*` macros defined away in
     `sysdeps/microblaze/sysdep.h` when it is not set).  Fixed in it:
     the comments said "binutils before 2.46", but binutils 2.46 and 2.47
     are released without MicroBlaze CFI (upstream binutils master
     `tc-microblaze.h` has no `TARGET_USE_CFIPOP` as of 2026-11-13), so
     they now say "released binutils".
   - `sysdeps/microblaze/configure` is regenerated with autoconf 2.72
     (output identical to the outbox version apart from the comment) and
     keeps mode 100755; the outbox patch changed it to 100644 for no
     reason.
   - Message: dropped the tst-cancelx4 claim (that is 4's fix, not this
     one's), described the `syscall_cancel.S` situation without "the
     preceding patch", and replaced "which is in GCC master but not in
     GCC 14" with a plain statement that the signal-frame unwinder is a
     separate GCC change.  GCC master does have
     `libgcc/config/microblaze/linux-unwind.h`, but it computes the
     ucontext address with `sizeof (ucontext_t)` for uClibc's layout
     (line 72), which is wrong for glibc; the issues repo's gcc 0001 is
     the fix.
8. Deletes `sysdeps/microblaze/backtrace.c` and `backtrace_linux.c` and
   their two Makefile lines so `debug/backtrace.c` is used.  Changed:
   rebased over 60b925c1 (the Linux Makefile hunk now only removes the
   `resource` block above the THP block), subject shortened, message
   reworded to not depend on series position.

## Ordering

The outbox cover letter already ordered ucontext (7) before CFI (8), but
issue #29 says ucontext goes "deliberately last" while #25 needs the
`setcontext.S` file it creates.  The choice was between:

- moving `cfi_undefined (r15)` into the ucontext patch: then ucontext
  needs the CFI patch's configure gate, and so is blocked on binutils
  accepting MicroBlaze CFI upstream, which may take a long time; or
- keeping it in the CFI patch and sending ucontext first.

I took the second.  The CFI patch is blocked on binutils anyway (#25's
own precondition), so sending ucontext before it costs nothing, and
ucontext stays independent of binutils.  **The send order in the issues
must change: #29 before #25.**  If #25 ever has to go before #29, drop
its `setcontext.S` hunk and add the line to #29 instead (it then works,
because the gate exists).

## How to send

glibc reviews small, independent patches more easily, and the issues
already plan one submission per issue, so the per-issue directories are
the ones to mail.  Each is bare `[PATCH]` except #19, which is a
`[PATCH n/2]` pair with a cover letter:

| directory | issue | depends on |
|---|---|---|
| `glibc-microblaze-longjmp-chk` | #12 | nothing |
| `glibc-microblaze-dl-fini` | #18 | nothing |
| `glibc-microblaze-syscall-cancel` | #19 | nothing |
| `glibc-microblaze-libm-tests` | #28 | nothing |
| `glibc-microblaze-ucontext` | #29 | nothing |
| `glibc-microblaze-asm-cfi` | #25 | #18 and #29 (text), binutils MicroBlaze CFI (function) |
| `glibc-microblaze-backtrace` | #27 | #25 (function only) |

The per-issue patch files are byte-identical to this directory's apart
from the `[PATCH n/8]` numbering.  This directory's
`0000-cover-letter.txt` is for sending all eight as one series, if that
is ever preferred.

## Testing

All builds were in Docker (`mbbuild:latest`, Debian 12, aarch64 host
in Docker Desktop), because the macOS host lacks GNU make and sed.
Toolchain from `scripts/build-many-glibcs.py` in `work/build/glibc-new`
(build tree in the docker volume `glibc-new-bmg`; logs in
`work/build/glibc-new/logs/`): binutils 2.47, GCC 15.3.0, Linux 7.1
headers, `host-libraries` + `compilers microblaze-linux-gnu` and
`compilers microblazeel-linux-gnu`, all PASS.

| configuration | what | result |
|---|---|---|
| microblaze-linux-gnu (BE) | clean `configure && make -j8 && make check-abi` of master `30f5c72a42` and of each of the 8 commits | 9/9 BUILD-OK, 9/9 check-abi OK |
| microblaze-linux-gnu (BE) | build-many-glibcs.py `glibcs` stage on the series tip (build, install, `make check` with run-built-tests=no) | PASS |
| microblaze-linux-gnu (BE) | master glibc built inside the `compilers` stage | PASS |
| microblazeel-linux-gnu (LE) | clean build + check-abi of master and of the series tip; the tip also built inside the LE `compilers` stage | BUILD-OK, check-abi OK |
| BE, CFI-capable assembler | series tip and the CFI commit, with binutils from `work/src/binutils` (microblaze-testsuite `patches/binutils/0001-0012` applied) via `-B` | probe says yes; libc.so and ld.so build; the build stops later, see below |

Evidence that each patch does what it says, from the BE builds (in
`logs/clean-microblaze-linux-gnu.txt`): `libc_cv_microblaze_asm_cfi=no`
with binutils 2.47 (`microblaze-glibc-linux-gnu-as` 2.47 rejects
`.cfi_startproc` with "CFI is not supported for this target"), so the
CFI patch changes no object there; `_identify_sighandler` disappears
from libc.so with the backtrace patch; `getcontext` in libc.so becomes
the weak alias of the new `__getcontext` with the ucontext patch, with
the ABI lists unchanged.

With the CFI-capable assembler (`logs/clean-microblaze-linux-gnu-cfigas*.txt`):
the probe says yes and `csu/start.o`, `stdlib/getcontext.os`,
`swapcontext.os`, `setcontext.os` (2 FDEs: `__setcontext` and
`__startcontext`, which starts with `DW_CFA_undefined: r15`),
`elf/dl-trampoline.os`, `misc/clone.os` and `gmon/_mcount.o` all carry
FDEs.  The full build does not finish with that binutils, for reasons
in binutils, not in these patches; the commit before the CFI patch
fails the same way:
- with the default `-g`, gas fails on `posix/regex.c` with 701 "value of
  00010000 too large for field of 2 bytes" errors in debug info;
- with `CFLAGS=-O2`, everything up to libc.so and ld.so builds and the
  link of `support/links-dso-program` fails ("libm.so.6, needed by
  libstdc++.so, not found"; mixed new ld with the 2.47-built libstdc++).

Before the Docker builds, every MicroBlaze `.S` file was also assembled
at each commit with the macOS-hosted `work/install` microblaze-elf-gcc
against a hand-made config (PIC and static; CFI on with its CFI gas,
CFI off, and CFI off with a 2.46.50 assembler without CFI): no
failures.  This is how the binutils 0012 problem below was found.

## Not tested

- **No `make check` that runs tests.**  Our QEMU build has no user mode,
  and a system-mode test wrapper is issue #16, which this task excluded.
  The runtime results quoted in the commit messages of 1-5 (qemu-user and
  qemu-system runs of tst-longjmp_chk*, tst-array*, tst-cancel17,
  tst-cancelx4, the libm tests) come from the issues repo's earlier runs
  of the outbox versions on a 2026-08/09 master, not from this rebase.
- The changed setcontext/swapcontext error path (6) has never run.  The
  success path is unchanged apart from one store to r1+4 before the
  system call.
- Little-endian: only master and the series tip were built, not each commit.
- The CFI-enabled configuration of 7 was only partly built (libc.so and
  ld.so, not the whole tree; see Testing), with the local, unreleased
  binutils CFI patches.  Nothing has unwound through it in this rebase.

## Open questions for the human

- glibc's position on LLM-assisted patches.  I did not find a policy in
  the glibc tree; `review-commit-msg.py` has no glibc mode and its
  binutils LLM-policy flags do not apply.  Check before sending; every
  commit carries `Assisted-by: Claude <noreply@anthropic.com>`.
- Signed-off-by (DCO) is not in the commits; add it.
- glibc likes a Bugzilla entry for user-visible bugs (and needs one for
  backports).  1, 2 and 3 are candidates for `[BZ #nnnnn]` subjects;
  none are filed.
- binutils: see "Found on the way" (two problems in the local series).

## Found on the way

**binutils 0012 ("gas: microblaze: emit CFA advances as relocations")
fails on an advance of 256 bytes or more across a relaxable branch.**
With the gas in `work/install` (built from `work/src/binutils`, which has
microblaze-testsuite `patches/binutils/0001-0012` applied):

```
	.text
f:
	.cfi_startproc
	.rept 62
	nop
	.endr
	brid 0f
	nop
0:
	.cfi_rel_offset r20, 8
	brlid r15,g@PLT
	nop
	.cfi_adjust_cfa_offset -16
	.cfi_endproc
```

`microblaze-elf-as` reports "value of 256 too large for field of 1 byte
at 0000002b"; with 61 nops it assembles (DW_CFA_advance_loc1 252).  The
1-byte form is chosen for a delta that needs advance_loc2.  An earlier
draft of patch 6 (which saved r19 in a stack frame and described it with
CFI) hit this in swapcontext.S; the final version does not, but any
function with CFI notes 256+ bytes apart across a relaxable branch will.
This is for whoever owns the binutils relax-CFI series; nothing in glibc
should work around it.

**The same binutils tree cannot assemble glibc's posix/regex.c at -g**:
701 errors "value of 00010000 too large for field of 2 bytes" in the
debug sections (`logs/clean-microblaze-linux-gnu-cfigas.txt`).  It looks
like the same family: a 2-byte label difference that became an ADD/SUB
pair is still checked against its field size.  Not reduced further.
