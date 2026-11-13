# glibc-microblaze-backtrace

- **Issue:** #27 in thesamprice/rtems-microblaze-linker-relaxation-bug
- **Upstream base:** glibc master `30f5c72a42` ("AArch64: Fix libmvec archive member collisions [BZ #34946]"), fetched 2026-11-12
- **From:** outbox/glibc/0009 in the issues repo
- **Branch:** `glibc-microblaze-runtime` in `work/src/glibc-new`; this directory is that branch's patch for this issue, byte-identical apart from numbering to `../glibc-microblaze-runtime/`, whose NOTES.md has the full history and the reasoning on ordering.
- **Patches:** `0001-microblaze-Use-the-generic-backtrace.patch`

## What it does

Deletes `sysdeps/microblaze/backtrace.c` (prologue-scanning walker) and `backtrace_linux.c` (its signal-trampoline matcher) and their Makefile lines, so `debug/backtrace.c` (`_Unwind_Backtrace`) is used, as on every other port.

## Changes from the outbox version

Rebased over `60b925c18fe`: the Linux Makefile hunk only removes the `resource` block above the new THP block.  Subject shortened, message reworded.  Applies to master on its own.

## Dependencies

Text: none.  Function: #25, so that frames in the assembly are walkable; signal frames also need the libgcc fix.  #27 says to send it after #25 is committed.

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
