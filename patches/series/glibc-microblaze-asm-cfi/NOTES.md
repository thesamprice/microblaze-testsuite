# glibc-microblaze-asm-cfi

- **Issue:** #25 in thesamprice/rtems-microblaze-linker-relaxation-bug
- **Upstream base:** glibc master `30f5c72a42` ("AArch64: Fix libmvec archive member collisions [BZ #34946]"), fetched 2026-11-12
- **From:** outbox/glibc/0008 in the issues repo
- **Branch:** `glibc-microblaze-runtime` in `work/src/glibc-new`; this directory is that branch's patch for this issue, byte-identical apart from numbering to `../glibc-microblaze-runtime/`, whose NOTES.md has the full history and the reasoning on ordering.
- **Patches:** `0001-microblaze-Add-CFI-to-the-assembly-sources.patch`

## What it does

Configure probe `libc_cv_microblaze_asm_cfi` -> `HAVE_MICROBLAZE_ASM_CFI`; without it `sysdeps/microblaze/sysdep.h` defines every `cfi_*` macro to nothing.  With it, ENTRY/END emit `cfi_startproc`/`cfi_endproc` (as or1k, csky, arc), the frames of `_dl_runtime_resolve`, `_dl_runtime_profile`, `_mcount` and the reentrant PIC `SYSCALL_ERROR_HANDLER` are described, and r15 is marked undefined in `_start`, the clone child and `__startcontext`.

## Changes from the outbox version

- Comments said "binutils before 2.46"; 2.46 and 2.47 are released without MicroBlaze CFI, so they now say "released binutils".
- `sysdeps/microblaze/configure` regenerated with autoconf 2.72 and kept at mode 100755 (the outbox patch changed it to 100644).
- Message: dropped the tst-cancelx4 claim (that is #19's fix), no "preceding patch" wording, and the GCC note no longer claims GCC master's signal-frame unwinder is sufficient (it assumes uClibc's ucontext_t size).

## Dependencies

Text: #18 (start.S context) and #29 (setcontext.S).  Function: binutils MicroBlaze CFI support (`patches/binutils/0003` in microblaze-testsuite, not upstream); until that lands the probe says no and the patch changes no generated code, which is the objection #25 warns about.

## Testing

Build-tested only, in Docker with build-many-glibcs.py's toolchain
(binutils 2.47, GCC 15.3.0, Linux 7.1 headers): a clean
`configure && make && make check-abi` for microblaze-linux-gnu of
master `30f5c72a42` and of every commit of the
`glibc-microblaze-runtime` stack, which contains this patch, all
BUILD-OK and check-abi OK.  The series tip also passes the
build-many-glibcs.py `glibcs` stage (`make check` with
run-built-tests=no) for microblaze-linux-gnu and builds and passes
check-abi for microblazeel-linux-gnu.  Details and logs:
`../glibc-microblaze-runtime/NOTES.md` and `work/build/glibc-new/logs/`.

With binutils 2.47 the probe says no (verified).  With the local binutils
CFI series (`work/src/binutils`) the probe says yes and libc.so, ld.so
and every MicroBlaze assembly object build with FDEs (`__startcontext`'s
starts with `DW_CFA_undefined: r15`); the rest of the tree does not
build with that binutils, for binutils reasons that also break the
commit before this one (see the runtime NOTES.md).

## Not tested

- No test was run.  QEMU user mode is not in our QEMU build and the system-mode test wrapper is issue #16, which was out of scope.  Run-time results quoted in the commit message come from the issues repo's earlier qemu runs of the outbox version on an older master, not from this rebase.
- Little-endian (microblazeel) was built only at the series tip, not per commit; the sources have no endian-specific code.

## Open questions

- Add `Signed-off-by:`.  The commit carries `Assisted-by: Claude <noreply@anthropic.com>`; check glibc's current policy on LLM-assisted contributions before sending (I found none in the tree).
- binutils 0012 (relax-safe CFA advances) mis-sizes advances of 256 bytes or more across a relaxable branch; see `../glibc-microblaze-runtime/NOTES.md`, "Found on the way".  This patch does not trigger it.
