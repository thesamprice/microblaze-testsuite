LOCAL ONLY: not for submission to qemu-devel (QEMU AI policy). Reference for a hand-written fix.

# qemu-local-mbar-hibernate: mbar 8 (hibernate) does not halt

Issue: #45 (thesamprice/rtems-microblaze-linker-relaxation-bug).

## Base

- `work/src/qemu-new` branch `base-local` (QEMU 10.2.4 tarball
  `ce70e4a95` + patches/qemu/0001 exit device `954e754f6`); branch
  `local-mbar`.
- Upstream master `9d7d057a55` (2026-11-12): **still has the bug**
  (`if (mbar_imm & 16)` in `trans_mbar`).  The patch applies to master.

## The patch

`0001-target-microblaze-enter-sleep-mode-on-hibernate.patch`: test
`mbar_imm & 24` instead of `& 16`, per UG984 v2026.1 p. 285 pseudocode
"if (IMM & 24) != 0 then enter sleep mode" and Table 69 (sleep = mbar
16, hibernate = mbar 8, suspend = mbar 24).

### Privilege: a choice the manual leaves open

UG984 contradicts itself:

- "Privileged Instructions" list (Chapter 2, around line 8738 of
  claude-mb/docs/ug984.txt): "SLEEP, HIBERNATE, SUSPEND".
- mbar page (p. 285): "this instruction is privileged when the most
  significant bit in IMM is set to 1", which is bit 16 and so not set
  by hibernate.

The patch keeps all three privileged (the existing `trap_userspace`
check now covers `& 24`), so a user-mode process cannot halt the CPU.
The earlier test-only change described in issue #45's comment did the
opposite (privileged on `& 16` only).  A hand-written upstream fix
should pick one deliberately; it is the main thing a reviewer will ask
about.  Real hardware would settle it.

## Tests

`test/run.sh QEMU_BE QEMU_LE`:

1. One-instruction programs: execute INSN, then exit with 7.  "halts" =
   still running at the 3 s timeout.
2. `wake.c` (+ `crt.S`, `board.h`, `link.ld`: vectors in LMB BRAM at 0,
   interrupt handler in C): arm a one-shot xps-timer interrupt about
   1 ms ahead, enable interrupts, execute INSN, then check whether the
   handler had run before the next instruction.  Exit 0 = waited for the
   interrupt, 1 = ran past INSN, 2 = no interrupt at all.

Results (BE and LE identical):

| INSN | base-local | local-mbar / local-all |
|---|---|---|
| nop | runs on | runs on |
| mbar 1 | runs on | runs on |
| mbar 2 | runs on | runs on |
| sleep (mbar 16) | halts | halts |
| **hibernate (mbar 8)** | **runs on** | **halts** |
| suspend (mbar 24) | halts | halts |
| **mbar 9** | **runs on** | **halts** |
| mbar 17 | halts | halts |
| wake: hibernate | **exit 1** | **exit 0** |
| wake: sleep | exit 0 | exit 0 |
| wake: suspend | exit 0 | exit 0 |
| wake: nop (control) | exit 1 | exit 1 |

QEMU's own tests: no tests/tcg/microblaze exists.  tests/functional
microblaze and microblazeel (5 Linux-boot tests) pass on base-local
and on local-all, which contains this series; table in
`../qemu-local-uartlite-irq/NOTES.md`.  This series alone was not run
through them.

## Untested

- User mode.  On this board user mode needs MSR[VM] and a TLB set up
  (`mb_cpu_mmu_index` returns the user index only with VM set), which
  the test does not do, so neither the privileged-instruction exception
  for hibernate nor the EE-clear path is exercised.
- Whether the sleep/hibernate/suspend output signals matter to any
  QEMU board model (none models them).

## Open questions

- Privilege of hibernate (above).
