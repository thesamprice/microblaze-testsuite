# gcc-microblaze-pcmpbf

Issue: #69 (thesamprice/rtems-microblaze-linker-relaxation-bug), "gcc: use
pcmpbf for zero-byte search with -mxl-pattern-compare".
Upstream: gcc-patches@gcc.gnu.org.  One patch, so no cover letter.

## Base

Committed as `9777be92c` on branch `scratch/gcc-new-pcmpbf` in the worktree
`work/src/gcc-new` (from the clone `work/src/gcc`, which was not changed).
The branch sits on `xilinx-rework` (`d01983184`): upstream gcc `df809a029`
plus four microblaze commits (fint-and-branch peephole2, _break_handler,
small structs in their own mode, bsefi/bsifi).  The patch does not depend
on them: `git apply --cached --check` onto `df809a029` succeeds, and onto
the gcc-microblaze-elfos commit (`423f5843b`) too.

## The patch

`0001-microblaze-expand-strlen-inline-with-pcmpbf.patch`

- `microblaze.md`: a `pcmpbf` insn (unspec, `UNSPEC_PCMPBF`; operand 2 may
  be zero and prints as `r0`), and a `strlensi` expander, enabled by
  `TARGET_PATTERN_COMPARE`, that FAILs for a search character other than
  0, when optimizing for size, or when `microblaze_expand_strlen` declines.
- `microblaze.cc`: `microblaze_expand_strlen`.  Needs a known alignment of
  at least 4.  Loop: `lwi; pcmpbf rX,rW,r0; beqid rX,loop; addik p,p,4`
  (four instructions, the add in the delay slot).  Big-endian: result =
  p + pos - (start + 5).  Little-endian, pcmpbf counts from the most
  significant byte, which is the last byte in memory: with -mxl-reorder,
  `swapb` the found word and run `pcmpbf` again; without it, step back one
  word and find the zero with `lbui` (at most four).

### Which hook, and the precedent

The standard `strlen<mode>` optab, expanded from `expand_builtin_strlen`
(builtins.cc), which passes the alignment from `get_pointer_alignment`.
Precedents read: rs6000 `strlensi` (rs6000.md:1821, `dlmzb`, needs
alignment >= 8 because it loads two words, big-endian only, not at -Os) is
the closest, since `dlmzb` is the same operation as `pcmpbf` against zero;
riscv `strlen<mode>` / `riscv_expand_strlen_scalar` (riscv-string.cc:548,
`orc.b`, needs word alignment, handles both byte orders) is the model for
the C helper living in the .cc file and for the little-endian handling.
sh (`sh_expand_strlen`, sh.md:9491) was also looked at.  Combine-based
recognition of the `(x - 0x01010101) & ~x & 0x80808080` idiom was not done:
nothing in tree does it, it would only match source written that way, and
the issue's second candidate (memchr/strchr word loops) has no optab GCC
expands inline except `rawmemchr`, which loop distribution uses only on
targets with vector rawmemchr (s390, riscv) and which needs an unaligned
head; not attempted.

No Xilinx code was read or used for this patch.

## Tests (all in the patch)

- `isa/strlen-pcmpbf.c`: -O2 BE, aligned: pcmpbf against r0, no call.
- `isa/strlen-pcmpbf-unaligned.c`: unknown alignment: no pcmpbf, call.
- `isa/strlen-pcmpbf-os.c`: -Os: call.
- `isa/strlen-pcmpbf-nopcmp.c`: -mno-xl-pattern-compare: call.
- `isa/strlen-pcmpbf-le.c`: -mlittle-endian -mno-xl-reorder: one pcmpbf,
  `lbui`, no swapb.
- `isa/strlen-pcmpbf-le-reorder.c`: -mlittle-endian -mxl-reorder: two
  pcmpbf and swapb.
- `others/strlen-pcmpbf-run.c`: run test; lengths 0..11 from both word
  offsets, nonzero (0x01, 0x7f, 0x80, 0xff) and zero bytes after the
  terminator.  Runs at -O0..-Os and LTO under the microblaze.exp torture
  list with -mcpu=v10.0.

The scans use `brlid\tr15,strlen` rather than `strlen`, so they keep
working once a `.file "strlen-pcmpbf.c"` line appears (it does with the
gcc-microblaze-elfos series).

## Testing done (all microblaze-elf, big-endian, QEMU 10.2.4 + patches/qemu/0001, board microblaze-qemu, `MB_NO_RELAX=-Wl,--no-relax`)

Build: `work/build/gcc-new` (configure flags copied from
`gcc-xfix-full`; c,lto; newlib from `work/src/newlib`).  Baseline is the
same tree at `d01983184` before the patch.

| run | before | after |
|---|---|---|
| gcc.target/microblaze (microblaze.exp) | 620 PASS / 142 FAIL / 31 UNRESOLVED / 1 UNSUPPORTED | 655 / 142 / 31 / 1 |
| gcc.c-torture/execute (execute.exp) | 24536 PASS / 14 FAIL / 176 UNSUPPORTED | 24536 / 14 / 176 |

microblaze.exp delta: +35 PASS, all from the 7 new tests; every other
result line identical (sorted .sum diff).  execute.exp: .sum result lines
identical, as expected, since nothing changes without
-mxl-pattern-compare.  The 142 microblaze.exp failures (picdtr.c 105,
the string_cst/sdata/data_var scans, fcmp*/vanilla/nofcmp calling an
undeclared `print`) and the 14 execute failures (fprintf-2.c,
pr117432.c, 7 each) are pre-existing and unchanged.

With the patch only: execute.exp + builtins.exp with board
`microblaze-qemu/-mcpu=v10.0/-mxl-pattern-compare`: 25510 PASS, 14 FAIL
(the same fprintf-2 and pr117432), 176 UNSUPPORTED.  No run of that
variant without the patch was made.  Only 4 torture files actually get
the inline expansion at -O2 (pr87053.c, strlen-4.c, strlen-5.c,
widechar-3.c); everything else has unknown alignment or folds.

pcmpbf in QEMU, and the little-endian code: a freestanding harness
(`bench/` below) checks pcmpbf directly (positions 1-4, no match, two
zeros, nonzero rB) and checks len() on lengths 0..12 from both word
offsets with 0x80/0xff garbage after the NUL, on qemu-system-microblaze
and qemu-system-microblazeel, for BE, LE without reorder and LE with
reorder.  All pass.  This is the only little-endian execution testing;
the DejaGnu runs are big-endian only (the build is --disable-multilib).

The final commit differs from the tested cc1 only in the wording of the
comment above `microblaze_expand_strlen`.

## Benchmark (instruction counts, QEMU -icount, test device from patches/qemu/0001)

`len(p) = __builtin_strlen(__builtin_assume_aligned(p, 4))`, counted from
the call to its return, -O2 -mcpu=v10.0.  "call-c" calls newlib's
`libc/machine/microblaze/strlen.c` built without -mxl-pattern-compare
(its word loop with the 0x01010101/0x80808080 test, what a default newlib
gives); "call-pcmp" calls the same file built with -mxl-pattern-compare
(its inline-asm pcmpbf loop).

| length | BE inline | LE inline, no reorder | LE inline, reorder | call-c | call-pcmp |
|---:|---:|---:|---:|---:|---:|
| 0 | 11 | 12 | 13 | 25 | 19 |
| 3 | 11 | 24 | 13 | 34 | 31 |
| 4 | 15 | 16 | 17 | 34 | 24 |
| 15 | 23 | 36 | 25 | 61 | 46 |
| 63 | 71 | 84 | 73 | 169 | 106 |
| 255 | 263 | 276 | 265 | 601 | 346 |
| sum of 11 lengths | 605 | 712 | 627 | 1436 | 910 |

(The call columns are the same for every byte order.)  Code size: len()
is 9 instructions inline on BE (12 LE without reorder, 11 with) against 8
for the call version, which also needs the 32-instruction (C) or
23-instruction (pcmp) strlen linked in.  These are instruction counts,
not cycles; the mbcount.c cycle estimator from bench/moddi3 was not run.
Harness and raw output: the session scratchpad
`.../scratchpad/gcc-new/bench/` (run.sh, bench.c, len.c, results.txt);
not copied into this repo.

## Checks

- `contrib/gcc-changelog/git_check_commit.py` (GitPython in a scratch
  venv): OK.
- `contrib/check_GNU_style.py`: no output.  `git diff --check`: clean.
- `tools/review-commit-msg.py --project gcc`: no Signed-off-by (added by
  the sender), the LLM-policy flag (104 non-test lines), 240 words vs a
  p90 of 235 for this size.  `tools/check-patch-style.py` says "ChangeLog
  block has no directory header"; the block uses `gcc/ChangeLog:`, the
  GCC form, so I take that to be the tool's binutils bias.

## Not tested / open

- No little-endian DejaGnu run; no run with -mxl-reorder under DejaGnu.
- No bootstrap (cross target).  microblaze-linux and microblaze-rtems not
  built with this patch.
- GCC's AI policy: the expander and helper are LLM-written code; the
  user decides whether this can be sent (see STYLE.md).
- Strings without known 4-byte alignment still call strlen.  Peeling up
  to three bytes to reach alignment would cover `char *` arguments; not
  done.
- The newlib side is separate: patches/series/newlib-microblaze-strlen
  (#70) rewrites newlib's pcmpbf strlen.
