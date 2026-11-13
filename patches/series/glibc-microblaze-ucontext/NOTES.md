# glibc-microblaze-ucontext

- **Issue:** #29 in thesamprice/rtems-microblaze-linker-relaxation-bug
- **Upstream base:** glibc master `30f5c72a42` ("AArch64: Fix libmvec archive member collisions [BZ #34946]"), fetched 2026-11-12
- **From:** outbox/glibc/0007 in the issues repo
- **Branch:** `glibc-microblaze-runtime` in `work/src/glibc-new`; this directory is that branch's patch for this issue, byte-identical apart from numbering to `../glibc-microblaze-runtime/`, whose NOTES.md has the full history and the reasoning on ordering.
- **Patches:** `0001-microblaze-Implement-the-ucontext-functions.patch`

## What it does

getcontext, setcontext and swapcontext in assembly, makecontext in C, and `ucontext_i.sym` for the offsets, replacing the generic ENOSYS stubs.  The symbols are already in the ABI lists (GLIBC_2.18).

## Changes from the outbox version

- Rebased over `60b925c18fe`: the `gen-as-const-headers` block now follows the `THP-PAGE-SIZE` block in `sysdeps/unix/sysv/linux/microblaze/Makefile`.
- Bug fix: setcontext and swapcontext held ucp in the callee-saved r19 across rt_sigprocmask and returned -1 with the caller's r19 clobbered when the call failed.  They now keep the caller's r19 in the r5 save slot at r1+4, which the caller always reserves (`REG_PARM_STACK_SPACE`, `OUTGOING_REG_PARM_STACK_SPACE` in gcc/config/microblaze/microblaze.h), and reload it in the delay slot of the branch to the error handler.  Untested at run time.
- No `cfi_*` macros: without the CFI patch they expand to `.cfi_*` directives that released binutils rejects.  The `cfi_undefined (r15)` for `__startcontext` is in the CFI patch (#25).
- The comment on the padding before `__startcontext` cites the sparc precedent (BZ #22919, and sparc64 `34eefd0d14b`, BZ #34978).
- Message reworded; makecontext.c comment fixed.  Applies to master on its own.

## Dependencies

None.  **Must be sent before #25**, whose setcontext.S hunk edits a file this patch creates.  #29 says "deliberately last"; that still holds among the fixes, but #25 is blocked on binutils and comes after it.

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

## Not tested

- No test was run.  QEMU user mode is not in our QEMU build and the system-mode test wrapper is issue #16, which was out of scope.  Run-time results quoted in the commit message come from the issues repo's earlier qemu runs of the outbox version on an older master, not from this rebase.
- Little-endian (microblazeel) was built only at the series tip, not per commit; the sources have no endian-specific code.

## Open questions

- Add `Signed-off-by:`.  The commit carries `Assisted-by: Claude <noreply@anthropic.com>`; check glibc's current policy on LLM-assisted contributions before sending (I found none in the tree).
- The new error path in setcontext/swapcontext has never run.  The success path differs from the tested outbox version only by a store to r1+4.
