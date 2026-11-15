# rtems-microblaze-tls-get-addr

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#82 (RTEMS
half). For: GitLab MR against rtems/rtos/rtems. One patch, so no cover
letter. Not yet sent. No Signed-off-by; it has `Assisted-by: Claude`.

## Base

RTEMS `origin/main` `53d56d9494` (the base of the other RTEMS series
here). Branch `microblaze-tls-get-addr` (worktree `work/src/rtems-fix-tls`),
commit `79686b95d0`. One patch:
`0001-cpukit-microblaze-Return-the-TLS-variable-in-__tls_g.patch`.

## What it does

GCC lowers every MicroBlaze TLS access to a `__tls_get_addr` call. For
the general dynamic model (an `extern _Thread_local` object) the argument
points to a GOT pair that the static link fills with module 1 and the
object's offset in the TLS segment. RTEMS's `__tls_get_addr` ignored the
argument and returned the thread pointer, which is right only for local
dynamic (offset 0, GCC adds the DTPREL offset afterwards). An extern
`_Thread_local` therefore always read the first object of the TLS
segment (sptls04's case). It now returns the thread pointer plus
`ti->offset`, as the ARM port does, with `_Assert (ti->module == 1)`.

## Dependency: the gcc half

With current GCC on microblaze-rtems the argument itself is garbage: r20,
the GOT pointer, was set up only for Linux. The GCC fix is
`../gcc-microblaze-audit-fixes/` 0002 ("set up the GOT pointer for TLS
accesses on every target"). This RTEMS patch is needed with it; on its
own it would read `ti` through an uninitialised r20. Merge after, or
together with, the GCC fix reaching the RTEMS toolchain.

## Testing

RTEMS was **not** built with this patch. The same logic (return the TLS
block start plus `ti->offset`) is the `__tls_get_addr` in GCC's new test
`gcc.target/microblaze/others/tls-run.c` (from the GCC 0002 patch), which
passes on microblaze-elf and microblazeel-elf under QEMU with the GCC fix
(part of the microblaze.exp runs in `../gcc-microblaze-audit-fixes/`
NOTES.md). The issue's reproducer, with RTEMS's old behaviour, read
`k=5 (expect 2)`.

## Open questions

- Not run on an RTEMS BSP: build `microblaze/kcu105_qemu` or
  `petalogix_s3adsp1800` with a GCC carrying the 0002 fix and run
  `sptls04` before sending.
