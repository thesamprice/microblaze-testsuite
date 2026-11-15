# rtems-microblaze-libdl-relocs

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#115. For:
GitLab MR against rtems/rtos/rtems. One patch, so no cover letter. Not
yet sent. No Signed-off-by; it has `Assisted-by: Claude`.

## Base

RTEMS `origin/main` `53d56d9494`. Branch `microblaze-libdl-add-sub`
(worktree `work/src/rtems-fix-libdl`), commit `4b3b80bcc7`. One patch:
`0001-cpukit-libdl-Add-MicroBlaze-ADD-SUB-SET-and-ALIGN-re.patch`.

## Why, and the binutils dependency

Our binutils patches make DWARF unwind information and exception tables
safe for linker relaxation as on RISC-V: gas emits ADD/SET + SUB pairs
(`R_MICROBLAZE_ADD8` .. `R_MICROBLAZE_SUB_ULEB128`, 36-45) for differences
of code labels, from the in-review relax-safe CFI series, and
`R_MICROBLAZE_ALIGN` (46) for code alignment above 4 bytes, from
`../binutils-microblaze-relax-fixes/` 0009. libdl's MicroBlaze loader
rejected them ("unsupported relocation type 44"), so an object with
unwind tables built with those binutils did not load.

The patch applies the ADD/SUB/SET relocations with S + A as on RISC-V,
accessing the (possibly unaligned) data fields with `memcpy()` in native
byte order, rewrites ULEB128 fields in place keeping their length, and
ignores `R_MICROBLAZE_ALIGN` (the loader does not relax).

The relocation numbers are provisional until the binutils series is
accepted upstream; this MR should follow it, not precede it.

## Testing

BSP `microblaze/petalogix_s3adsp1800` (little-endian, `BUILD_LIBTESTS =
True`), libdl tests dl01-dl14 under QEMU, each with and without
relaxation. Builds `work/build-rtems-newbu/c{1,2,3}-*`, scripts
`rtems-build.sh` and `rundl.sh` there (the runner is
`patches/series/rtems-microblaze-no-relax/scripts/runtest.sh`, 120 s),
results in `work/build-rtems-newbu/results/`.

| build | toolchain | dl05 no-relax | dl05 relax | others |
|---|---|---|---|---|
| c1 | RSB GCC 15.2 / binutils 2.47, unpatched RTEMS | PASS | TIMEOUT | as below |
| c2 | same GCC, binutils `fix/binutils-all`, unpatched RTEMS | FAIL ("unsupported relocation type 44") | FAIL | as below |
| c3 | same as c2, RTEMS with this patch | PASS | PASS | as below |

In all six runs dl01-dl04, dl07-dl12 and dl14 PASS and dl06 FAILs
(an expected failure, the same in the baseline). dl13 is not in the
runs (not built as a runnable test here). The c1 relax TIMEOUT of dl05 is
#71, the problem the relaxation-safe tables fix.

Only `R_MICROBLAZE_ADD32`, `SUB32`, `SET_ULEB128` and `SUB_ULEB128` occur
in the dl05 objects, so the ADD8/16, SUB6/8/16 and SET6 cases and the
ALIGN case are untested. Little-endian only; big-endian not run.

## How to reproduce

```
B=work/build-rtems-newbu
sh $B/bu/build.sh                      # binutils fix/binutils-all -> work/install-rtems-newbu
$B/rtems-build.sh work/src/rtems-fix-libdl $B/c3-new-fix-relax work/install-rtems-newbu relax
$B/rundl.sh $B/c3-new-fix-relax $B/results/c3-relax.txt
```

## Open questions

- Big-endian and the untested relocation widths, before sending.
- dl06's failure predates this change; not investigated here.
