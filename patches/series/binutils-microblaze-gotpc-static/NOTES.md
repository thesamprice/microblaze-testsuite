# binutils-microblaze-gotpc-static

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#117. For:
binutils@sourceware.org. One patch, so no cover letter. Not yet sent.

## Base and dependencies

Commit `9f88f3cbfda` on branch `fix/binutils-gotsegv`, one commit on top
of `fix/binutils-all` (`a16eefd1f6e`), i.e. after
`../binutils-microblaze-relax-fixes/`, `../binutils-microblaze-local-labels/`
and `../binutils-microblaze-gas-fixes/` and the base they sit on (see the
relax-fixes NOTES.md).

Apply order: relax-fixes -> local-labels -> gas-fixes -> gotpc-static
(this).

The change itself does not depend on those series, but the patch does
not apply to bare binutils master `7b7c85d7f65` with `git apply`: the
context of the `microblaze_elf_relocate_section` hunk differs there. With
`git apply -C1` it applies (checked, not built or tested).

## What it does

`gcc -fpic` loads the GOT pointer with `mfs r20, rpc` and
`addik r20, r20, _GLOBAL_OFFSET_TABLE_+8`, an `R_MICROBLAZE_GOTPC_64`. A
function that calls only through the PLT makes no other GOT reference,
and `microblaze_elf_check_relocs` did not handle GOTPC, so a static link
created no `.got`/`.got.plt`, `_GLOBAL_OFFSET_TABLE_` was undefined, and
`microblaze_elf_relocate_section` then dereferenced the NULL
`htab->elf.sgotplt` and ld died with SIGSEGV. GOTPC now creates the GOT
as GOTOFF already did (as arm and s390 do), and relocate_section reports
an error instead of crashing if it ever sees GOTPC without a GOT. New
test `ld-microblaze/gotpc-static`.

## Testing

macOS host, built and run as for `fix/binutils-all` (`make -k check-gas
check-ld check-binutils`):

| target | gas PASS | ld PASS | binutils PASS | FAIL |
|---|---|---|---|---|
| microblaze-elf, fix-all | 344 | 507 | 245 | 0 |
| microblaze-elf, with this | 344 | 508 | 245 | 0 |
| microblaze-linux, fix-all | 341 | 839 | 249 | 12 ld + 1 XPASS |
| microblaze-linux, with this | 341 | 840 | 249 | the same 12 ld + 1 XPASS |

The microblaze-linux FAILs are the ones listed in the relax-fixes
NOTES.md. The new ld PASS is `gotpc-static`.

End to end: gcc.dg/20001012-1.c and pic-macro-define.c, which the `fpic`
effective target expects to link and run, link and exit 0 under QEMU;
20050321-2.c links. Before, ld crashed on all three.

## How to reproduce

```
cd work/src/binutils && git worktree add /tmp/b fix/binutils-all
cd /tmp/b && git am patches/series/binutils-microblaze-gotpc-static/*.patch
# build and check as in work/build-fix-all (build.sh, check.sh)
```
