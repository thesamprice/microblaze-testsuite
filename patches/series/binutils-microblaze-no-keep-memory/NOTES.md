# binutils-microblaze-no-keep-memory

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#50

Upstream base: binutils-gdb master `b6272d0e90717f2b96a748feaba7c5d41fe4ac15`
(2026-11-13).

## Already fixed on master?

No.  Alan Modra's October refactors named in the issue (`1d00124bd73`
"Format elf_link_read_relocs calls", `f2fa1a5ec2e` "Duplicate
bfd_sym_from_r_symndx lookup") are in the base and only reformat the
call.  On the base, `microblaze_elf_relax_section` still sets
`free_relocs = internal_relocs` whenever `!keep_memory`, and still
stores freshly read contents in `this_hdr.contents` before possibly
freeing them.  The reproducer below aborts on the unpatched base.

## Patch

`0001-microblaze-don-t-free-cached-relocs-and-contents.patch`

- `bfd/elf32-microblaze.c` (`microblaze_elf_relax_section`): drop
  `free_relocs`/`free_contents`; at the end and in `error_return`, free
  `internal_relocs`, `contents` and `isymbuf` only when they differ from
  `elf_section_data (sec)->relocs`, `elf_section_data (sec)->this_hdr.contents`
  and `symtab_hdr->contents`; with `keep_memory`, cache contents and
  symbols instead.  Contents are no longer put in `this_hdr.contents` at
  read time.
- New test `ld/testsuite/ld-microblaze/relax-no-keep-memory.{s,d,ld}`.

Idiom followed: `sh_elf_relax_section`, bfd/elf32-sh.c:786-822 on the
base (same comparisons in 22 other bfd backends; listed by
`grep -l "elf_section_data (sec)->relocs != internal_relocs" bfd/*.c`).
The Xilinx patch (meta-xilinx mb32/0006, CR-1115233) was not used.

Side effect, stated in the commit: `isymbuf` read by
`bfd_elf_get_elf_syms` when nothing was relaxed used to be neither freed
nor cached (a leak); it is now freed (`--no-keep-memory`) or cached
(default), as in sh.

Reporter credit: the commit says it was reported to AMD by
dednev@rambler.ru (from the issue).  Whether to turn that into a
`Reported-by:` trailer is the sender's call.

## How the bug shows (unpatched base, macOS arm64)

Two scratch inputs, linked with
`ld-new -EL -relax --no-keep-memory -T relax-no-keep-memory.ld`:

- call from `.text.aaa_relaxed` to another section (IMM deleted in pass
  1, relocs cached, pass 2 frees them): `Abort trap: 6`, exit 134.
- `lwi` of an out-of-range symbol (IMM kept, contents freed while still
  in `this_hdr.contents`): exit 0 on a plain run; with `MallocScribble=1`
  exit 139 (SIGSEGV) and the disassembly of the output starts
  `5d039000 / 00001000 / aaaaaaaa` (freed-memory fill).

The committed test combines both; on the unpatched base it FAILs with
`Abort trap: 6`.  Patched: both inputs and the test link with exit 0
under `MallocScribble=1 MallocGuardEdges=1`, and the outputs are
byte-identical to the same links without `--no-keep-memory`.

## Test results (microblaze-elf, build work/build/binutils-new/elf)

CC_FOR_TARGET = installed microblaze-elf-gcc with `-B` pointing at
debug-stripped copies of its crt files and libraries (the installed
newlib was assembled by a gas carrying the relax-cfi series, whose
R_MICROBLAZE_ADD32/SUB32 relocs master ld rejects).  Same setup for
before and after.

| suite | base | patched |
|---|---|---|
| gas | 331 PASS, 0 FAIL | 331 PASS, 0 FAIL |
| ld | 546 PASS, 2 FAIL, 15 XFAIL, 9 UNTESTED | 547 PASS, 2 FAIL, 15 XFAIL, 9 UNTESTED |
| binutils | 268 PASS, 1 FAIL, 2 XFAIL | 268 PASS, 1 FAIL, 2 XFAIL |

Only difference: `+PASS: MicroBlaze relaxation with --no-keep-memory`.
The two ld FAILs (`merge4`, `S-records`) and the binutils FAIL
(`--only-keep-debug for ELF relocatables`) are on the base too.
(`S-records` is issue #39.)

## Untested / open

- Not run under ASan or valgrind; not run on a Linux/glibc host, so I do
  not know whether the new test fails there without the fix (glibc's
  double-free check usually aborts, but this was not observed).
- microblazeel-elf and microblaze-linux were not tested for this patch
  (the test forces -EL so it exercises little-endian on microblaze-elf).
- The other-sections loop still reads `_bfd_elf_link_read_relocs (abfd,
  o, NULL, NULL, true)` and caches `ocontents` unconditionally; that is
  memory use under --no-keep-memory, not a correctness issue, and is
  left alone (the existing comment already says so).
