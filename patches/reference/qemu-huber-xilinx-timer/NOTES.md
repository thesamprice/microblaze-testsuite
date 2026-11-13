# Sebastian Huber, "[PATCH 0/2] Fix two Xilinx Timer issues": test record

Issue: #59 (thesamprice/rtems-microblaze-linker-relaxation-bug).
Nothing has been sent.  These are not our patches; they carry Sebastian
Huber's Signed-off-by and no AI trailer.

## Fetched

`thread.mbox`: lore.kernel.org
`/qemu-devel/20260824003405.616297-1-sebastian.huber@embedded-brains.de/t.mbox.gz`
(fetched 2026-11-12, gunzipped).  Three messages: 0/2, 1/2 "Start on
the enable edge", 2/2 "Reload at the expiry", all 2026-08-24.  **No
replies** in the thread.

## Applied

- `work/src/qemu-new` branch `huber-timer`: base-local (QEMU 10.2.4
  tarball `ce70e4a95` + patches/qemu/0001 exit device `954e754f6`) +
  `git am` of the thread: `756ab740d` (1/2), `fb2eccb21` (2/2).  Both
  apply cleanly; the cover letter is an empty patch and was skipped.
- They also `git am` cleanly onto hw/timer/xilinx_timer.c of upstream
  master `9d7d057a55` (2026-11-12), which does not contain them.
- Build: work/build/qemu-new, binaries kept in `huber/`.  No new
  compiler warnings (build-59.log).  checkpatch not run on his patches.

## Test program

`test/timer.c` (+ crt.S, board.h, link.ld; `test/run.sh QEMU_BE QEMU_LE`).
Bare metal on petalogix-s3adsp1800 (timer at 62 MHz, IRQ 0, level
input on the INTC).  Timer 1 runs free as the time reference; timer 0
is under test, and its handler acknowledges with
`TCSR0 = TCSR0 | TINT`, i.e. with ENT still set (what the Linux and
RTEMS drivers do).

- **periodic**: P = 6200 ticks (100 us), ARHT, 64 periods; prints the
  mean interval between handler entries.
- **oneshot**: P ticks, no ARHT; counts interrupts within 20 P.
  Hardware: 1.
- **tlr**: periodic P; the 8th handler writes TLR0 = 2P; mean of the
  32 intervals after the first full period at the new value.

Run with `-icount shift=0` (deterministic: identical numbers BE/LE and
run to run) and without icount.

## Results, -icount shift=0 (BE and LE identical)

| test | base-local | with the series | expected |
|---|---|---|---|
| periodic mean (ticks) | 6203 + 6/64 | 6136 + 29/64 | 6200..6202 (test's tolerance) |
| oneshot interrupts | **16** | **1** | 1 |
| tlr mean after change | 12403 + 6/64 | 12399 + 62/64 | 12400..12402 |

Per-interval detail (built with `-DDUMP`, intervals between handler
entries, ticks):

| P | base-local | with the series |
|---|---|---|
| 1000 | 1003 or 1004 every time | 1000, 1000, 1000, **2000**, repeating: **one interrupt in four is lost** |
| 6000 | 6003/6004 | 1937, 6000, 6000, 6000, 10063, repeating |
| 6200 | 6203/6204 | 2137, 6200, 6200, 6200, 10263, repeating |
| 62000 | 62003/62004 | 62000 (61999 once in 8) |

Reading:

- Patch 1 does what it says: with base-local the acknowledge restarts
  the count, so a one-shot timer fires 16 times in 20 P, and every
  periodic interval is 3 ticks long (the handler's latency at
  shift=0).  With the series the one-shot fires once.
- Patch 2 does what it says: the expiries stay on a P grid (every
  repeating group above sums to an exact multiple of P, e.g. 2137 +
  3 x 6200 + 10263 = 5 x 6200), and the TLR change takes effect at the
  next reload, period exactly 2P.
- **But under -icount, with periods below about 1 ms, delivery of the
  interrupt is late by up to 4063 ticks, and at P = 1000 interrupts are
  lost.**  4063 ticks at 62 MHz is 65.5 us, i.e. about 2^16 ns, which
  at shift=0 is 2^16 instructions.  My unverified guess is the icount
  instruction budget (16-bit decrementer) not being cut short at the
  ptimer's re-armed deadline when the re-arm happens inside the ptimer
  callback, rather than from a guest MMIO write as before.  I did not
  investigate further.  It is still an improvement for the RTEMS clock
  driver at 1 ms or longer ticks; whether it blocks the series is for
  the reviewers.

## Results without icount

On this host (8 cores, load average 42-56 from other builds during the
runs) the virtual clock follows host time and host timer delivery was
late by many milliseconds, so the periodic numbers measure the host,
not the model:

| test | base-local BE / LE | series BE / LE |
|---|---|---|
| periodic mean (ticks, P = 6200) | 786903 / 703056 | 1098906 / 733449 |
| oneshot interrupts | 2 / 0 | 1 / 1 |
| tlr mean (2P = 12400) | 919855 / 1073948 | 953288 / 827783 |

A 10 ms period (P = 620000) gave means of 1.2M-1.56M ticks for
base-local and 1.0M ticks for the series, still dominated by host
latency.  The one-shot count is the only meaningful number here; the
"0" for base-local LE is the window closing before the late host timer
fired.  I would not quote the no-icount numbers in a reply.

## QEMU functional tests

See `patches/series/qemu-local-uartlite-irq/NOTES.md` for the table.
The huber build was run through tests/functional/microblaze and
microblazeel (Linux boots on petalogix-s3adsp1800, which use this
timer).

## Not tested

- RTEMS itself (clock driver, ts-validation-*, tm27): not run.
  Issue #59 asks for the RTEMS clock/timer tests; that needs an RTEMS
  build for this BSP, which this task did not cover.
- microblaze-v (riscv) machine, which also has the xps-timer: not built.
- Up-counting mode and the capture/PWM modes.
- Migration/vmstate (the series does not change vmstate).

## Observations outside the series (pre-existing, not caused by it)

- `timer_write`, R_TCSR: `xt->regs[addr] = value & 0x7ff` after
  clearing TINT from `value`, so *any* TCSR write clears a pending TINT,
  not only a write of 1 to TINT, which is how drivers acknowledge it.
  A guest that rewrites TCSR to change ENIT can lose an interrupt.
  (I did not check PG079 for the hardware's behaviour.)
- `TCSR_LOAD` is not modelled (the counter is loaded only when the
  timer starts).  With patch 1 a guest that reloads a running timer by
  setting LOAD while ENT stays set gets no reload.  The Linux microblaze
  timer driver and our tests clear ENT before setting LOAD, so they are
  unaffected.

## Draft reply (for a human to review and send; not sent)

    Subject: Re: [PATCH 0/2] Fix two Xilinx Timer issues

    Hi Sebastian,

    I applied both patches to v10.2.4 and to master (9d7d057a55); both
    apply cleanly.  On petalogix-s3adsp1800 with a bare-metal test
    whose handler acknowledges with ENT still set:

    - a one-shot timer (ARHT clear) now interrupts once in 20 periods;
      before the series it interrupted 16 times, because every
      acknowledge restarted it;
    - with -icount shift=0, a 6200-tick (100 us) auto-reload timer now
      expires on an exact 6200-tick grid; before, every period was 3
      ticks long, the handler latency;
    - a TLR write from the handler takes effect at the next reload.

    One thing I noticed under -icount shift=0 with short periods: the
    expiries are on time, but the interrupt is sometimes delivered up to
    4063 ticks (about 65.5 us, 2^16 instructions) late, and at a
    1000-tick period one interrupt in four is lost.  At 62000 ticks
    (1 ms) intervals are exact.  This did not happen before the series,
    where the restart came from the guest's MMIO write.  I have not
    looked into why; it may be the icount budget rather than this
    device.

    The tests/functional microblaze and microblazeel tests pass with
    the series applied.

    Tested-by: <name> <email>

    Thanks,
    <name>

Before sending: confirm the functional-test sentence against the table
in qemu-local-uartlite-irq/NOTES.md, and decide whether the icount
observation should hold back the Tested-by.
