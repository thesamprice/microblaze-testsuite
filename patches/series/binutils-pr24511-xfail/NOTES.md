# binutils-pr24511-xfail

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#26 (the
remaining binutils 0003/0005 item).  Replaces
`patches/binutils/0005-ld-testsuite-widen-the-pr24511-xfail-to-all-MicroBla.patch`.

Upstream base: binutils-gdb master `b6272d0e90717f2b96a748feaba7c5d41fe4ac15`
(2026-11-13).

## Patch

`0001-ld-xfail-pr24511-on-MicroBlaze-except-Linux.patch`

- `ld/testsuite/ld-elf/pr24511.d`: `microblaze*-*-elf*` becomes
  `microblaze*-*-*` in the xfail list, and a `#noxfail: microblaze*-linux*`
  line follows the xfail lines, as in `ld/testsuite/ld-elf/pr23658-1e.d`
  (mechanism from Alan Modra's bc85bc665a).

Changes from the old 0005:
- added the `#noxfail` line (the blocker in #26);
- new subject (old one was 63 characters, over the 55 limit);
- message rewritten: dropped `--` punctuation, and dropped the old
  microblaze-xilinx-rtems7 pass counts, which came from an earlier run I
  did not repeat.  The numbers below are from my runs.

## Testing (all ld-elf/elf.exp, macOS arm64 host)

| target (build dir) | pr24511.d | pr24511 result | elf.exp summary |
|---|---|---|---|
| microblaze-rtems7 (work/build/binutils-new/rtems) | base | FAIL | 171 PASS, 1 FAIL, 12 XFAIL |
| microblaze-rtems7 | patched | XFAIL | 171 PASS, 0 FAIL, 13 XFAIL |
| microblaze-linux (work/build/binutils-new/linux) | base | PASS | 328 PASS, 10 FAIL |
| microblaze-linux | patched | PASS | 328 PASS, 10 FAIL (identical per test) |
| microblaze-linux | patched without the `#noxfail` line | XPASS | (only pr24511 run) |
| microblaze-elf (work/build/binutils-new/elf) | patched | XFAIL | (only pr24511 run) |

The 10 microblaze-linux FAILs (commonpage1, local1, maxpage1, maxpage2,
pr19162, pr25207, textaddr1, textaddr10, textaddr4, textaddr9) are the
same with and without the patch; not investigated.

Caveats: the linux build's bfd was compiled from the
binutils-microblaze-no-keep-memory branch and then rebuilt from the base
before the runs above; the microblaze-elf binary used for its one
pr24511 run carried the no-keep-memory bfd change (relaxation only,
irrelevant to this test).  Only elf.exp was run on rtems and linux, not
all of ld.

## Open

- The old 0005 was paired with a gas patch in #26; that one already
  landed (ad8ac4b8993), so this can go alone.
- binutils's LLM policy covers testsuites; this is a 3-line testsuite
  edit, which the sender may judge not legally significant.
