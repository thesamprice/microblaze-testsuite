# glibc-microblaze-syscall-cancel

- **Issue:** #19 in thesamprice/rtems-microblaze-linker-relaxation-bug
- **Upstream base:** glibc master `30f5c72a42` ("AArch64: Fix libmvec archive member collisions [BZ #34946]"), fetched 2026-11-12
- **From:** outbox/glibc/0003 and 0004 in the issues repo
- **Branch:** `glibc-microblaze-runtime` in `work/src/glibc-new`; this directory is that branch's patch for this issue, byte-identical apart from numbering to `../glibc-microblaze-runtime/`, whose NOTES.md has the full history and the reasoning on ordering.
- **Patches:** `0001-microblaze-Fix-__syscall_cancel_arch-stack-arguments.patch`, `0002-microblaze-Tail-call-__syscall_do_cancel.patch`

## What it does

1/2: `__syscall_cancel_arch` loads syscall arguments 5 and 6 from r1+28/32 (where the ABI puts its 7th and 8th arguments) instead of r1+56/60.

2/2: the cancel branch reaches the `_Noreturn` `__syscall_do_cancel` with `brid` instead of `brlid`, so the assembly leaves no frame of its own for the forced unwind to step through.  This is why the CFI patch (#25) has no syscall_cancel.S hunk.

## Changes from the outbox version

Subjects rewritten (the outbox ones were 56 and 70 characters and lower case), messages reworded and the ChangeLog blocks dropped (glibc commit messages no longer carry them), author unified to Samuel Price.  Code unchanged.  Both apply to master on their own and in either order.  `0000-cover-letter.txt` is for the `[PATCH 0/2]` mail.

## Dependencies

None.  Note that master already has Luc Michel's epilogue fix for this function (BZ 33547); these touch different lines.

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
- If a reviewer asks why the function gets no CFI: the tail call leaves no frame to describe, and released binutils cannot assemble MicroBlaze CFI anyway.
