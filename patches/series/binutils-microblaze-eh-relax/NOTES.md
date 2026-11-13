# binutils-microblaze-eh-relax

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#71 (C++
exceptions hang under linker relaxation: RTEMS samples/cdtest).

Base: `work/src/binutils-new` tip `8d80a35dde7` ("microblaze: add
SET_ULEB128 and SUB_ULEB128 relocations") = binutils-gdb master
`b6272d0e907` + `patches/binutils/0001`-`0012` +
`patches/series/binutils-relax-safe-cfi-ef/0013`-`0015`.  Branch
`binutils-microblaze-eh-relax`, worktree
`work/src/binutils-issue71-0012`, one commit `009ccaf5abc`.

## Root cause (verified)

GCC writes the LSDA call-site table (`.gcc_except_table`) as

	.uleb128 $LEHB0-$LFB0     # call-site start
	.uleb128 $LEHE0-$LEHB0    # length
	.uleb128 $L9-$LFB0        # landing pad

gas (2.36 Xilinx, 2.47, master, master + 0001-0012) resolves these to
constants with no relocation.  When `ld -relax` deletes IMMs inside the
function, the unwinder looks up call sites and enters landing pads at
the unrelaxed offsets.

In the RSB-built cdtest (`work/build/rtems-new/rsb-base`, GCC 15.2,
binutils 2.47) `main_task` shrinks 0x3a8 -> 0x398.  The call-site entry
for the call to `foo_function` (return address main_task+0x44) still
covers it, but its landing pad says main_task+0x144 (0x90000cd0); the
real landing pad is main_task+0x138 (0x90000cc4).  The unwinder skips
`addk r4,r5,r0; addk r3,r6,r0; xori r3,r3,1` (exception pointer and
selector), takes the wrong branch and calls `_Unwind_Resume`, which
finds no handler and spins at `_Unwind_Resume+332` (`bri 0`).  gdb
backtrace: `_Unwind_Resume` <- `main_task` main.cc:207.

The FDE `pc_range` is stale too with 2.47 (cdtest main_task FDE
0x90000b8c..0x90000f34, function ends 0x90000f24; reproducer
0x90000284..0x90000464 for a 0x154-byte function), because GCC writes
`.eh_frame` by hand with `.4byte $LFE-$LFB`.  0001-0012 already fix
that (reproducer FDE 0x90000284..0x900003d8 with them).  It is not the
cause of the hang: 0001-0012 fix the FDE and the reproducer still
calls terminate.

Why the old pin passes cdtest: with GCC 12.4.1 + Xilinx 2.36 no IMM in
`main_task` or `foo_function` is deleted (both keep their object sizes,
0x3a8 and 0x104, in `bsp-base/.../cdtest.exe`), so the table happens to
be right.  The old pin fails the reproducer the same way (below), so
this is not a 2.47 regression.

## Which binutils fixes it

`0015` (SET_ULEB128/SUB_ULEB128, #47 F) is the fix: gas emits a pair
for each of these `.uleb128` fields (20 pairs in the reproducer
object, 6 of them in `.rela.gcc_except_table`), and ld rewrites them.  It
depends on 0008-0011 (ADD/SUB infrastructure).  #51 is not involved
(no far R_MICROBLAZE_64_NONE branch on the failing path) and was not
tried.

The patch here adds only a regression test (`relax-lsda`,
`relax-lsda-norelax`) in the shape of that LSDA.  No code change is
needed beyond 0015.

## Reproducer

`repro/` (copies; the working files are in `work/build/issue71/`):

- `eh.cc`: 32 calls to `sink` (in another section, so each is
  `imm; brlid`) then `try { thrower(v); } catch (int)`.
- `build.sh <bsp-build-dir> <out.exe> [ld flags]`: builds it against an
  RTEMS waf build dir (headers, librtems*, linkcmds).  `TOOLBIN` picks
  the toolchain, `BEXTRA=-B<dir>` puts another `as`/`ld` first.
- `build-cdtest.sh`: same for samples/cdtest (main.cc, init.c).
- `runq.sh <exe> [timeout]`: QEMU command line from rtems-tools
  `petalogix_s3adsp1800.ini` (needs `endianness=little` and the two
  `-global` options, else every program dies with fatal 0xabcd0003).
- `lsda.py`: decodes an LSDA call-site table.

Example:

	cd work/build/issue71
	./build.sh ../rtems-new/rsb-base relax.exe
	./build.sh ../rtems-new/rsb-base norelax.exe -Wl,--no-relax
	BEXTRA=-B$PWD/bin-ef/ ./build.sh ../rtems-new/rsb-base ef-relax.exe
	$RUNQ relax.exe 10

`bin-ef/` and `bin-0012/` hold `as`/`ld` symlinks to
`work/build/binutils-new/rtems` (0001-0015, rebuilt 2026-11-13) and
`work/build/issue71/binutils-0012` (0001-0012, built for this).

## Results (all run 2026-11-13, QEMU petalogix-s3adsp1800 LE)

Reproducer (`eh.cc`):

| toolchain | relax | --no-relax |
|---|---|---|
| GCC 12.4.1 + Xilinx 2.36 (old pin, `bsp-base`) | terminate | pass |
| GCC 15.2 + 2.47 (RSB) | terminate | pass |
| GCC 15.2 + master+0001-0012 as/ld | terminate | not run |
| GCC 15.2 + master+0001-0015 as/ld | **pass** | pass |

cdtest:

| build | result |
|---|---|
| RSB waf build `rsb-base` (2.47, relaxed) | hang after first catch |
| RSB waf build `rsb-norelax` | exceptions pass |
| manual build, 2.47 | terminate at the first throw (different layout) |
| manual build, 0001-0012 as/ld | terminate at the first throw |
| manual build, 0001-0015 as/ld | **all exceptions pass**, global dtors run |

The manual builds assemble main.cc and init.c with the given gas; the
BSP, libstdc++, libgcc and newlib are the 2.47-assembled ones.

New ld test by hand: with 0001-0015 the relaxed table is `14 08 24`,
unrelaxed `1c 0c 30`; with 0001-0012 relaxed it stays `1c 0c 30`
(stale; 0x30 is then the delay slot of the last rtsd).

Testsuites (microblaze-elf, `work/build/issue71/binutils-elf`, run with
`work/build/binutils-new/runchecks.sh`, results in
`work/build/binutils-new/results/issue71-lsda`), compared with
`cfiEF2` (0001-0015):

| suite | 0001-0015 | + 0016 |
|---|---|---|
| gas | 327 PASS, 11 XFAIL | 327 PASS, 11 XFAIL |
| ld | 559 PASS, 1 FAIL | 561 PASS, 1 FAIL |

Only per-test difference: +PASS "MicroBlaze relaxation keeps LSDA call
sites with the code" and "MicroBlaze LSDA call sites without
relaxation".  The FAIL is S-records, as before.  check-binutils not run
(test-only patch).

## Open questions / not done

- Libraries: any LSDA in libstdc++, libgcc or newlib assembled by a gas
  without 0015 stays stale when relaxation shrinks that function.  The
  RSB builds GCC after binutils, so a binutils with 0015 fixes them too,
  but I did not run an RSB build with it.  Not checked whether any
  library LSDA is actually broken in today's images.
- The RTEMS testsuite was not re-run with 0015.
- binutils does not accept LLM-written content, testsuites included
  (STYLE.md).  The test in 0016 was written by Claude; a human must
  rewrite it before it goes upstream, or fold an equivalent check into
  0015's tests.
- Relocation numbers 44/45 remain provisional (see the E/F NOTES).
- Big-endian not tested.
