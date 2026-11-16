# gcc-testsuite-fixes

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#120 (and the
strub-run3 half of #121). For: gcc-patches@gcc.gnu.org. Not yet sent.

## Base and dependencies

Branch `fix/gcc-testsuite-mb` (worktree in a session scratchpad), five
commits on gcc master `df809a029`. No dependencies. Testsuite only, so
not in `patches/gcc/`.

Checks: `git_check_commit.py` OK on each, `check_GNU_style.sh` clean.

## The failures and why

All from the first `compile.exp`/`dg.exp`/`dg-torture.exp` run on
microblaze-elf. In each the compiler's output is right.

| patch | tests | cause | fix |
|---|---|---|---|
| 1 | 7 `hierarchical-discriminator-*.c` | They scan `.loc ... discriminator N` on `gas` targets. MicroBlaze uses gas but `DWARF2_ASM_LINE_DEBUG_INFO` is 0 (kept, #119), so gcc writes the line table itself; the discriminators are in it (`-dA` shows `# discriminator 1`) but not as `.loc` | `-gas-loc-support` on gas targets: the option `DWARF2_ASM_LINE_DEBUG_INFO` only defaults. With it, 4-46 matches per test on MicroBlaze, 0 without |
| 2 | `fold-round-1.c` | The fold (match.pd:950) fires for float and long double too, but phiopt drops the result: GCC will not create new `floorf`/`floorl` calls when `targetm.libc_has_function` says no C99, which elfos.h's `no_c99_libc_has_function` does for every bare ELF target. mips-elf, riscv32-elf and sparc-elf cc1 (same base) keep the same 8 `link_error` calls | `dg-require-effective-target c99_runtime`, as `builtins-59.c` etc. False with newlib |
| 3 | `pr110729.c` (3) | Scans `,\.LPFE0`; MicroBlaze writes `,$LPFE0` (local label prefix `$`) | `[.$]LPFE` |
| 4 | `pic-1.c` | MicroBlaze forces `flag_pic = 2` ("we only support one kind of PIC"), as hppa | add to the target exclusion |
| 4 | `ifcvt-4.c` | No conditional-move patterns: "0 true changes made" | add to the skip list (riscv, arm are there) |
| 4 | `Wno-frame-address.c` | `__builtin_return_address (1)` unsupported | add to the skip list |
| 5 | `strub-run3.c` -O0 | The non-strub `callable` check fails (exit-code instrumented copy: the first loop). Its alloca block's last word overlaps the word at the old stack pointer, which the alloca copied down; the epilogue's stack restore writes it back over the end of the dead string (dumped: `55 de ad be ef c0 1d ca 00 00 00 00`). Not a strub problem: at-calls and internal pass. -O1 and up pass | `dg-skip-if` microblaze at -O0 |

## Testing

See `../gcc-microblaze-elf-defaults/NOTES.md` for the run (same stack,
same run). For these tests: 15 FAIL become 10 PASS and 5 UNSUPPORTED;
no other result changed.
