# gcc-microblaze-cbranch

From the audit of MicroBlaze peepholes and compare/branch patterns that
followed #54. The fint peephole2 was the backend's only peephole; this
covers what else fuses compares and branches.

Base: gcc master `df809a029` plus `gcc-microblaze-zero-fails`. 0002's
`pcmpeq`/`pcmpne` scans need that series' `-ffat-lto-objects` fix in
microblaze.exp.

- 0001 removes `cbranchsi4_reg` and `microblaze_expand_conditional_branch_reg`
  (2015). Not a standard pattern name, never generated, and its EQ case
  branches the wrong way (`pcmpeq` gives 1 on equal, then it branches on
  0). New test `others/cbranch-eq-reg.c`, a run test of register `==`/`!=`
  branches and values with `-mxl-pattern-compare`. It passes before and
  after, because the removed code was unreachable.
- 0002 adds run tests for the live integer compare/branch patterns:
  `cmp-branch-run.c` (int), `cmp-branch-di-run.c` (long long) and
  `cmp-branch-pcmp-run.c` (`-mxl-pattern-compare`). Expected results come
  from a table computed on the host.

Left out: a float test (`fcmp-branch-run.c`, in the scratchpad) fails 7
execution tests on stock QEMU because of the `fcmp.le`/`fcmp.ge` operand swap
(#60), and passes with the QEMU fix.

- 0003 (#76) stops `microblaze_expand_conditional_branch` from testing an
  unsigned inequality against 0 as signed: it branched on the register
  with `signed_condition (code)`, so `x >u 0` became `x > 0`. Latent: the
  middle end rewrites `(gtu x 0)` as `(ne x 0)` and `(leu x 0)` as
  `(eq x 0)`, and folds GEU/LTU, so neither C nor GIMPLE input reaches it.
  New test `others/cbranch-unsigned-zero.c` writes the comparisons in
  GIMPLE. It passes with and without the patch for that reason.

  To show the bug and the fix, a scratch build guarded those two rules in
  `simplify-rtx.cc` with an environment variable. With them off,
  unpatched gcc branches with `bgti` and the test aborts at `-O0` (1
  FAIL, 13 PASS); patched, it emits `cmpu` + `blti` and passes (14 PASS).
  At `-O1` and above GIMPLE folding rewrites the comparison first.

  A first version tested `!unsigned_condition_p (code)`. That is also
  true for EQ and NE, so it sent every `== 0` / `!= 0` branch through
  the xor path. The code stayed correct after combine but 12 execute
  tests' assembly changed. The patch tests `signed_condition (code) ==
  code` instead, which keeps EQ, NE and the signed inequalities on the
  shortcut. With it, `-O2` assembly is identical for all 1577 tests, with
  and without `-mxl-pattern-compare`. A trace in an instrumented cc1
  showed no unsigned inequality against 0 reaching the expander in any of
  them.

## Testing

On top of `gcc-microblaze-fixes` and `gcc-microblaze-zero-fails`
(build/gcc-xfix and build-le/gcc), stock QEMU 10.2.4:

- microblaze.exp: 805 PASS, 1 UNSUPPORTED, 0 FAIL, big- and little-endian
  (721 before, plus 84 from the four tests: cbranch-eq-reg 28,
  cmp-branch-pcmp-run 28, cmp-branch-run 14, cmp-branch-di-run 14).
- All 1577 gcc.c-torture/execute tests give identical `-O2` assembly
  before and after 0001, with and without `-mxl-pattern-compare`.
- With 0003 (its first version), microblaze.exp gave 819 PASS, 0 FAIL on
  both endians. The final version differs only in leaving EQ/NE on the
  shortcut; see the runner results in the top-level README for it.
- All three commits pass `git_check_commit.py` and `check_GNU_style.py`.
