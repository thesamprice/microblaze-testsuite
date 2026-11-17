# Submission order: core bugs

Priority list for sending the patches behind the open issues in the
"Core bugs & test framework" milestone of
thesamprice/rtems-microblaze-linker-relaxation-bug. Written 2026-11-16.
Nothing in this list has been sent yet. Series details are in
[`README.md`](README.md) and each series' `NOTES.md`.

## How the order was chosen

1. **Silent wrong code first.** A miscompile that produces a working-looking
   program outranks an ICE or an assembler error, which at least fail
   loudly.
2. **Dependencies.** A patch goes after anything its context needs.
3. **Independent and small first.** A series that applies to plain
   upstream master, alone, can go out now and gets reviewed on its own
   merits.
4. **Test framework last.** The DejaGnu board and a posted `check-gcc`
   baseline (#36) mean most when they show the fixes above.

## Apply check against current master

Each series was applied alone to upstream master with `git apply --index`
(gcc `9571dd0b7` and binutils-gdb `bd92f21ae14`, both 2026-11-17). Not
rebuilt or retested on those masters.

| series | result on current master |
|---|---|
| `dejagnu-spawn-split` | not checked (DejaGnu master `6ea0ff7` was current on 2026-11-06) |
| `gcc-microblaze-fixes` | all 4 apply |
| `gcc-microblaze-zero-fails` | all 4 apply |
| `gcc-microblaze-audit-fixes` | 0001-0003, 0005-0008 apply; 0004 needs `gcc-microblaze-fixes` 0002 (known) |
| `gcc-microblaze-compile-fixes` | 0001, 0003, 0004 apply; 0002 needs `gcc-microblaze-fixes` 0003, 0005 needs audit-fixes 0004 (known) |
| `gcc-generic-clmul-promoted`, `gcc-generic-overaligned-parm`, `gcc-microblaze-locviews` | apply |
| `gcc-testsuite-fixes` | 0001, 0003, 0004 apply. **0002 is already upstream**: Torbjörn Svensson's "testsuite: Require a C99 runtime for fold-round-1.c [PR124262]" (`20774e7ed`) adds the same line. Drop it |
| `gcc-generic-compare-tests` | 0001, 0002, 0004, 0005 apply. **0003 collides**: upstream added an unrelated `gcc.dg/gimplefe-62.c` (Kyrylo Tkachov, 2026-11-09). Rename ours to the next free number |
| `binutils-microblaze-opcodes` | all 7 apply |
| `gdb-sim-microblaze-rslr` | applies |
| `binutils-microblaze-gotpc-static` | applies only with `git apply -C1` (known; context from the series underneath) |
| `binutils-microblaze-gas-fixes` | 0002 applies alone; the other eight, including #92's 0003, need the relax-safe CFI series and `binutils-microblaze-relax-fixes` underneath |

## The order

### Wave 1: unblock testing (send now, independent)

| # | series | list | issues | why here |
|---|---|---|---|---|
| 1 | `dejagnu-spawn-split` (1) | dejagnu@gnu.org | #72 | DejaGnu master runs no local command with arguments, so nobody on current DejaGnu can run the gcc or binutils testsuites. One patch, no dependencies |

### Wave 2: GCC silent wrong code (send now, all apply to master)

| # | series / patches | issues | severity |
|---|---|---|---|
| 2 | `gcc-microblaze-audit-fixes` 0001 | #81 | compare-and-swap succeeds when the values differ only in bit 31: broken atomics and locks, silently |
| 3 | `gcc-microblaze-audit-fixes` 0003 | #83 | the epilogue frees the alloca/VLA area before its last accesses; an interrupt in the gap corrupts them |
| 4 | `gcc-microblaze-audit-fixes` 0002, then `rtems-microblaze-tls-get-addr` | #82 | bare-metal TLS builds `__tls_get_addr`'s argument from an uninitialised r20; extern `__thread` reads the wrong variable. The RTEMS half goes after the GCC half is accepted |
| 5 | `gcc-microblaze-fixes` 0001-0003 | #54, #56, #55 | 0001: fint+branch peephole2, wrong code without checking (`(int) -0.5f < 0` true) and an ICE with it. 0002: a `break_handler` unit puts the interrupt vector on the break handler. 0003: `-freg-struct-return` ICE. **Send 0004 (bsefi/bsifi, #67/#68) separately**: it is a feature, and it no longer belongs in a bug-fix series now that stage 1 is over |
| 6 | `gcc-microblaze-zero-fails` 0001-0004 | #73, #75 | 0001: `va_arg` garbage in C23 `void f (...)`. 0002: `-fPIE -mpic-data-is-text-relative` ICE. 0003/0004: testsuite, `gcc.target/microblaze` and `fileio`. With these, `execute.exp` and `microblaze.exp` have zero failures, which is what later reviewers will check against |

2-4 can be one mail: the eight audit fixes are one series, and 0001-0003
lead it. Send all eight together once `gcc-microblaze-fixes` 0002 is in
(0004 needs it); if that is slow, send 0001-0003 and 0005-0008 first and
0004 after.

### Wave 3: GCC ICEs and assembler errors

| # | series / patches | issues | notes |
|---|---|---|---|
| 7 | `gcc-microblaze-compile-fixes` 0001, 0003, 0004 | #116 (0001) | 0001: LRA ICE for a shift by a symbol address. 0003: calls through constant non-function addresses. 0004: TImode argument counted as two words, **wrong code** after a 16-byte vector argument (could move up to wave 2) |
| 8 | `gcc-microblaze-compile-fixes` 0002, 0005 | | after `gcc-microblaze-fixes` 0003 and audit-fixes 0004 are in |

### Wave 4: binutils and sim (independent of GCC; can run in parallel with waves 2-3)

| # | series | list | issues | notes |
|---|---|---|---|---|
| 9 | `binutils-microblaze-opcodes` (7) | binutils@sourceware.org | #40-#44 | objdump decodes `bslli`/`bsrai` as `bsrli`, `wdc.ext.clear` as `wdc.clear`, `mbar 9/17/31` as sleep modes, and stops at a zero word; `pcmpbc` removed. Applies to master; send first of the binutils series |
| 10 | `gdb-sim-microblaze-rslr` (1) | gdb-patches@sourceware.org | #52 | `mts rslr` writes the PC, so every newlib program hangs in the simulator. Independent |
| 11 | `binutils-microblaze-gotpc-static` (1) | binutils@sourceware.org | #117 | ld segfault on a static `-fpic` link. Rebase onto bare master (it applies with `-C1`), rebuild, run `ld.exp`, and send independently rather than waiting at the end of the relax stack |
| 12 | `binutils-microblaze-gas-fixes` 0003 | binutils@sourceware.org | #92 | gas silently truncates immediates over 32 bits on 64-bit hosts. Blocked: it sits on the in-review relax-safe CFI series (#47, itself waiting on #20) and `binutils-microblaze-relax-fixes`. Either wait, or rebase 0003 (and 0002, which already applies alone) onto master and send them ahead of the rest of gas-fixes |

### Wave 5: middle-end and testsuite (needs more than a MicroBlaze run)

| # | series | issues | notes |
|---|---|---|---|
| 13 | `gcc-generic-clmul-promoted` (1) | #121 | wrong code (stale upper bits) on any target that promotes the CLMUL result's mode. Generic code: bootstrap and regtest on x86_64 (or aarch64) first |
| 14 | `gcc-testsuite-fixes` 0001, 0003, 0004 | #120, #121 | drop 0002 (upstream as PR124262) and renumber to 3 patches |
| 15 | `gcc-generic-compare-tests` (5) | #54, #56, #60, #76 | rename 0003's `gimplefe-62.c`. Tests only; no rush |

### Wave 6: our own repository and research

| # | item | issues | notes |
|---|---|---|---|
| 16 | `testsuite-check-newlib` | #66 | microblaze-testsuite only, no upstream mail: merge it here |
| 17 | newlib/libgloss Xilinx patches | #58 | not packaged; needs testing first (crtinit frame size, exception handler, `__stack_chk_fail`). Not ready to order |
| 18 | MicroBlaze DejaGnu board and a posted `check-gcc` baseline | #36 | last: the board (`patches/dejagnu/0001`) wants its UART driver moved to libgloss first, and the baseline is worth posting once waves 2-3 are in, so it shows few failures |

## Not core bugs, but time-critical

GCC 17 stage 1 ends 2026-11-16 (the date the series README and #48
use). Bug fixes can still go in during stage 3; new optimisations
generally cannot unless posted before stage 1 closes. Ready or nearly
ready, and not bug fixes:

- `gcc-microblaze-carry` (#48) and `gcc-microblaze-generic-moddi3` (#49):
  "ready to send" in the README. Post today, or hold for GCC 18.
- `gcc-microblaze-fixes` 0004 (bsefi/bsifi), `gcc-microblaze-pcmpbf`,
  `gcc-microblaze-opt`, `gcc-microblaze-elfos` and
  `gcc-microblaze-elf-defaults`: features and cleanups; GCC 18 stage 1
  unless the MicroBlaze maintainer takes them earlier.

## Before sending anything

- Add `Signed-off-by:` (README).
- Rebuild and rerun the series on current master, not only the
  `git apply` check above.
- For the generic GCC patches (13 here, and `gcc-generic-overaligned-parm`,
  #118, low priority): bootstrap and regtest on a primary target.
