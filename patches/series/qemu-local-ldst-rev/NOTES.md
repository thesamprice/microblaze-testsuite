LOCAL ONLY: not for submission to qemu-devel (QEMU AI policy). Reference for a hand-written fix.

# qemu-local-ldst-rev: reversed sub-word loads/stores clobber their base

Issue: #61 (thesamprice/rtems-microblaze-linker-relaxation-bug).

QEMU's `docs/devel/code-provenance.rst` declines AI-derived
contributions.  This patch is for our own QEMU build and as a reference
for whoever writes the upstream fix by hand.  `BUGREPORT.md` is a
report a person can send instead; reporting with AI-assisted analysis
is allowed by the policy.

## Base

- QEMU 10.2.4 release tarball (`work/src/qemu-10.2.4.tar.xz`), committed
  pristine in `work/src/qemu-new` as `ce70e4a95`, plus
  `patches/qemu/0001-hw-microblaze-add-an-exit-and-instruction-count-devi.patch`
  (`954e754f6`, branch `base-local`).  The test needs that exit device.
- Branch `local-ldst-rev` in `work/src/qemu-new`.
- Upstream master checked: `9d7d057a55` (gitlab.com/qemu-project/qemu,
  2026-11-12).  **Still has the bug**: `do_load`/`do_store` there are
  identical to v10.2.4.  The patch applies to master (`git apply
  --check`).
- Regression from `36a9529e60` ("target/microblaze: Simplify
  compute_ldst_addr_type{a,b}", Richard Henderson, reviewed by Edgar),
  `git describe --contains`: `v10.1.0-rc0~73^2~15`, so first released
  in v10.1.0.

## The patch

`0001-target-microblaze-don-t-clobber-reversed-ld-st-base.patch`

`do_load` and `do_store` XOR the address with `3 - size` in place for
lbur/lhur/sbr/shr.  Since 36a9529e60, `compute_ldst_addr_typea` returns
`cpu_R[ra]` or `cpu_R[rb]` itself when the other operand is r0 (and a
`tcg_constant_i32(0)` when both are), so the guest's base register is
modified.  The fix XORs into a fresh temporary.

Precedent: that is what the code did before 36a9529e60, when
`compute_ldst_addr_typea` always returned a new temporary.  For
reference only (not copied): Luc Michel's fix in Xilinx's fork,
`6f493e0ede` (2026-05), takes the same approach and also factors the
reversed-access logic into a helper.  If AMD posts that, it supersedes
this.

## Tests

`test/revldst.S` + `test/run.sh QEMU_BE QEMU_LE`.  Bare metal on
petalogix-s3adsp1800, built with work/install/bin/microblaze-elf-gcc.
15 checks: base register preserved and value correct for lbur and lhur
in both `rA, r0` and `r0, rB` forms, sbr and shr base preserved and the
written byte/halfword read back with lbur/lhur, lwr base preserved
(control), and lbur used as a loop pointer.  Exit status is the number
of the first failed check, 0 = pass.

| build | big endian | little endian |
|---|---|---|
| base-local (10.2.4 + exit device) | exit 1 (check 1: `lbur r3, r5, r0` changed r5) | exit 1 |
| local-ldst-rev | exit 0 | exit 0 |
| local-all (all four local series) | exit 0 | exit 0 |

Low byte of r5 after one instruction, with r5 = 0x90001000 (BE,
one-instruction programs, scratchpad only):

| instruction | base-local | fixed |
|---|---|---|
| `lbur r3, r5, r0` | 0x03 | 0x00 |
| `lbur r3, r0, r5` | 0x03 | 0x00 |
| `lhur r3, r5, r0` | 0x02 | 0x00 |
| `sbr r3, r5, r0` | 0x03 | 0x00 |
| `shr r3, r0, r5` | 0x02 | 0x00 |
| `lwr r3, r5, r0` | 0x00 | 0x00 |
| `lbu r3, r5, r0` | 0x00 | 0x00 |

QEMU's own tests: there is no tests/tcg/microblaze.  tests/functional
microblaze and microblazeel (5 Linux-boot tests) pass on base-local and
on local-all, which contains this patch (table in
`../qemu-local-uartlite-irq/NOTES.md`); they do not exercise reversed
loads specifically, and this patch alone was not run through them.

## Untested

- The `r0, r0` form (address is a TCG constant).  It cannot have
  produced a wrong result before the fix, only a TCG misuse; I did not
  build QEMU with `--enable-debug-tcg` to see whether it asserts.
- qemu-microblaze linux-user (we build softmmu only).
- The typeb forms: there are no immediate reversed loads, so
  `compute_ldst_addr_typeb` is not involved.

## Open questions

- Whether to wait for AMD to post `6f493e0ede` (has Luc Michel's
  Signed-off-by) rather than write a fix by hand.  BUGREPORT.md asks
  for that.
