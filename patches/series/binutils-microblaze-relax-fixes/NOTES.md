# binutils-microblaze-relax-fixes

Issues (thesamprice/rtems-microblaze-linker-relaxation-bug): #101, #88,
#89, #90, #104, #105, #85, #98, #84, in patch order. For:
binutils@sourceware.org. Not yet sent.

## Base and dependencies

Branch `fix/binutils-all` (worktree `work/src/binutils-fix-all`), cut on
`audit/all-patches` = binutils master `7b7c85d7f65` (2026-11-15) plus 26
of our patches, none upstream yet:

- the in-review relax-safe CFI series, patches 0001-0015
  (`binutils-relax-safe-cfi-ef` holds 0013-0015),
- `binutils-microblaze-64-none`,
- `binutils-microblaze-no-keep-memory`,
- `binutils-microblaze-srec-64/on-relax-cfi`,
- `binutils-microblaze-eh-relax` (0016, the LSDA test),
- `binutils-microblaze-opcodes` (seven patches).

Top of the base: `e43593417fc` ("ld: microblaze: test LSDA call sites
under relaxation"). The patches here do not apply to bare master.

Apply order of the three folders cut from `fix/binutils-all`:
`binutils-microblaze-relax-fixes` (this, 9) ->
`binutils-microblaze-local-labels` (1) -> `binutils-microblaze-gas-fixes`
(9). They are the 19 commits of `audit/all-patches..fix/binutils-all`.

| patch | commit | issue |
|---|---|---|
| 0001 relaxation cleanups | `5277c6d8bfe` | #101 |
| 0002 compressed debug sections | `fbef83554b6` | #88 |
| 0003 `__start_SEC`/`__stop_SEC` | `66ae338d619` | #89 |
| 0004 SEC_MERGE addends mapped twice | `3800cbc5af3` | #90 |
| 0005 TEXTREL_32_LO howto | `4d984c6f564` | #104 |
| 0006 `.rela.got` sizing | `a6a2db4b189` | #105 |
| 0007 words in the relaxed section | `56bc7332275` | #85 |
| 0008 ADD/SUB for global differences | `90a55ca30e3` | #98 |
| 0009 code alignment, `R_MICROBLAZE_ALIGN` | `f738f888bc8` | #84 |

## Compatibility: R_MICROBLAZE_ALIGN

0009 adds relocation `R_MICROBLAZE_ALIGN` = 46, the next free number
after SET_ULEB128/SUB_ULEB128 (44, 45; 36-45 are as provisional as the
rest of the relax-safe CFI series). gas emits it for code alignment above
4 bytes. An older ld rejects such objects ("unsupported relocation
type"), as happened when R_RISCV_ALIGN was introduced. Without
relaxation nothing changes: gas still emits only the padding needed.

RTEMS libdl loads relocatable objects at run time and also rejects
unknown types; the companion change is `../rtems-microblaze-libdl-relocs/`
(#115), which accepts ADD/SUB/SET/ULEB128 (36-45) and ALIGN (46).

## Testing

macOS host. Built with `work/build-fix-all/build.sh`, run with
`check.sh` there (`make -k check-gas check-ld check-binutils`); the base
is `work/build-audit` (same scripts on `audit/all-patches`). The figures
are for all 19 commits of `fix/binutils-all` together; the three folders
were not tested separately.

| target | gas PASS | ld PASS | binutils PASS | FAIL |
|---|---|---|---|---|
| microblaze-elf, base | 329 | 498 | 245 | 0 |
| microblaze-elf, fixed | 344 | 507 | 245 | 0 |
| microblaze-linux, base | 326 | 829 | 249 | 12 ld + 1 XPASS |
| microblaze-linux, fixed | 341 | 839 | 249 | the same 12 ld + 1 XPASS |

The microblaze-linux FAILs, identical lists before and after:
ld-elf/commonpage1, local1, maxpage1, maxpage2, pr19162, pr25207,
textaddr1, textaddr4, textaddr9, textaddr10, pr22374, --sort-common
(ascending); XPASS ld-elf/pr24511.

New XFAIL on both: gas "difference between forward references"
(0007; riscv xfails it the same way).

microblazeel-elf: gas built and run (`work/build-fix-all/microblazeel-elf`);
all new tests pass.

End to end: a C program built with `-O2 -falign-functions=32`, linked
with `--relax`, run under QEMU: every function 32-byte aligned and the
same result as with `--no-relax` (sum `001c22c1`, exit 0; `prog.c` and
`run.sh` are in a session scratchpad, `e2e-all/`, not in this repo).
Before 0009, three of four functions in such a program came out
misaligned (from the commit message).

## How to reproduce

```
cd work/src/binutils-fix-all   # or a worktree of audit/all-patches + git am these
B=work/build-fix-all; sh $B/build.sh && sh $B/check.sh
```

## Open questions

- Relocation numbers 36-46 are provisional until the relax-safe CFI
  series is accepted; 0009 must follow whatever numbering it gets.
- 0009 never grows a section: when padding would have to grow, it keeps
  IMMs instead. Reviewers may prefer RISC-V's worst-case padding; that
  would change output for links without relaxation.
