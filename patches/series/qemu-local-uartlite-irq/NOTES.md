LOCAL ONLY: not for submission to qemu-devel (QEMU AI policy). Reference for a hand-written fix.

# qemu-local-uartlite-irq: xilinx_uartlite interrupt from the enable alone

Issue: #62 (thesamprice/rtems-microblaze-linker-relaxation-bug).

## Is it a bug?  Yes.

PG142, "AXI UART Lite v2.0 LogiCORE IP Product Guide", April 5, 2017
(docs.amd.com/v/u/en-US/pg142-axi-uartlite, PDF fetched 2026-11-12):

- p. 5, Overview: "Interrupt Control - The AXI UART Lite core provides
  interrupt enable/disable control. If interrupts are enabled, a
  rising-edge sensitive interrupt is generated when the receive FIFO
  becomes non-empty or when the transmit FIFO becomes empty."
- Feature Summary: "Generates a rising-edge sensitive interrupt when the
  receive FIFO becomes non-empty or when the transmit FIFO becomes
  empty. This interrupt can be masked by using an interrupt
  enable/disable signal."
- Port Descriptions: `interrupt`, O, "Edge rising UART interrupt."
- Table 2-7, CTRL_REG bit 4 "Enable Intr": "0 = Disable interrupt
  signal, 1 = Enable interrupt signal".  CTRL_REG is write-only.
- Table 2-8, STAT_REG bit 4 "Intr Enabled": "Indicates that interrupts
  is enabled. 0 = Interrupt is disabled, 1 = Interrupt is enabled".

So the events are FIFO transitions, enabling is only a mask, and
STAT_REG bit 4 mirrors the enable.

QEMU 10.2.4 `hw/char/xilinx_uartlite.c` (identical in upstream master
`9d7d057a55` apart from include paths):

- `STATUS_IE` (STAT_REG bit 4) is used as a sticky "pending" latch:
  set by every TX write (`/* hax.  */`) and by `uart_update_irq`
  whenever the RX FIFO is non-empty; nothing ever clears it.
- `uart_update_irq` drives the line at level
  `(STATUS & STATUS_IE) && (CTRL & CONTROL_IE)` after every register
  read of RX and every register write.

Consequences, all confirmed by the test below on base-local:
after one transmitted character, writing CTRL with the enable set
raises the interrupt by itself (Sebastian Huber's observation in RTEMS
1a88250af3); so does rewriting CTRL or reading RX; STAT_REG bit 4 reads
1 with interrupts disabled.  petalogix-s3adsp1800 configures the INTC
input for the UART as edge (`kind-of-intr` includes UARTLITE_IRQ) and
`xilinx_intc`'s `irq_handler` latches ISR on every call with level 1,
not only on a 0-to-1 change, so each such access latches a new request.

## Base

- `work/src/qemu-new` branch `base-local` (QEMU 10.2.4 tarball
  `ce70e4a95` + patches/qemu/0001 exit device `954e754f6`); branch
  `local-uartlite`.
- Upstream master `9d7d057a55`: not fixed; the patch applies
  (`git apply --check`).

## The patch

`0001-hw-char-xilinx_uartlite-pulse-the-IRQ-on-FIFO-events.patch`

- Removes the latch and the level computation.
- `uart_event_irq()`: `qemu_irq_pulse()` if CTRL's enable is set.
  Called after a TX write (the model transmits at once, so the TX FIFO
  goes non-empty and back to empty: one "becomes empty" event) and when
  a character arrives in an empty RX FIFO.
- STAT_REG bit 4 = CTRL_REG bit 4.

Precedent for modelling an edge interrupt as a pulse: `qemu_irq_pulse`
in include/hw/irq.h, used by 29 files under hw/.  Both INTC configurations
in xilinx_intc latch a pulse into ISR (edge: in `irq_handler`; level:
`update_irq` ORs the pin state into ISR while it is high, and ISR is
cleared only by IAR), so the pulse works whichever way a board
configures the input.

## Tests

`test/uart.c` (+ crt.S, board.h, link.ld; `test/run.sh QEMU_BE QEMU_LE`).
The CPU's interrupt stays off; the test reads the INTC's ISR.  "xy" is
fed to the serial input about 1 s after start.  All 16 checks run; the
failed ones are printed as "FAIL n"; exit status is the first.

1 STAT bit 4 clear at start; 2-3 TX with interrupts disabled: no
request, STAT bit 4 still clear; 4-5 enable: STAT bit 4 set, **no
request**; 6-7 TX: one request, cleared by IAR; 8 rewriting CTRL and
reading STAT: no request; 9-10 first RX character: one request; 11-12
reading RX: no request; 13-14 second character, read: no request; 15-16
disable: STAT bit 4 clear, TX gives no request.

| build | BE | LE |
|---|---|---|
| base-local | exit 3; FAIL 3, 5, 8, 12, 14, 15, 16 | identical |
| local-uartlite | exit 0 | exit 0 |
| local-all | exit 0 | exit 0 |

(16 on base-local is the request latched by check 14 still pending.)

## QEMU's own tests

There is no tests/tcg/microblaze and no qtest for xilinx_uartlite.
tests/functional, run with each build through a wrapper adding
`-L <build>/qemu-bundle/.../share/qemu` (the copied binaries cannot
find petalogix-s3adsp1800.dtb otherwise; the first attempt without it
hung with no console output on every build).  The LE test logs in on
the serial console and runs tftp + md5sum, so it exercises the
interrupt-driven Linux uartlite driver in both directions.

| test (tests/functional/...) | base-local | local-all (4 local series) | huber-timer |
|---|---|---|---|
| microblaze/test_s3adsp1800 legacy_be (Linux boot to "kernel memory protection") | ok | ok | ok |
| microblaze/test_s3adsp1800 legacy_le (endianness=little, login, tftp, md5sum) | ok | ok | ok |
| microblaze/test_replay (record/replay boot) | ok | ok | ok |
| microblazeel/test_s3adsp1800 legacy_le | ok | ok | ok |
| microblazeel/test_s3adsp1800 legacy_be (endianness=big) | ok | ok | ok |

No skips.  Logs: work/build/qemu-new/func-<build>-*.log.  local-uartlite
alone was not run through them; local-all contains it.

## Impact on RTEMS: read before carrying this in our test runner

RTEMS commit 1a88250af3 ("bsps/microblaze: Add an alternative test
interrupt", Sebastian Huber) defines `TM27_INTERRUPT_VECTOR_ALTERNATIVE`
on this UART and raises it with `XUartLite_EnableIntr();
XUartLite_DisableIntr();`, relying on exactly this QEMU behaviour (its
commit message says so, and that a real board needs a separate test of
that path).  With this patch that pulse does nothing, so RTEMS tests
that use the alternative test interrupt (ts-validation-intr and the
tm27-based tests) will fail on a QEMU that carries it.  Do not add it to
patches/qemu while those RTEMS tests run on our QEMU, and coordinate
with Sebastian before anyone fixes this upstream.

## Untested

- RTEMS on the patched QEMU (expected to break as above; not run).
- microblaze-v-generic (riscv), the other board using this device: not
  built.  It also configures the UART input as edge.
- Characters arriving while the guest is not reading (FIFO full, 8
  entries in QEMU against 16 in PG142) and overrun/error bits: not
  changed, not tested.
- CTRL_REG reads: PG142 says they return 0; QEMU returns the last
  value.  Not changed.
- Migration: the device has no vmstate before or after.

## Open questions

- Whether real hardware raises an interrupt when interrupts are
  enabled while the TX FIFO is already empty.  PG142 says "becomes
  empty", which I read as no; only hardware can settle it.
- What RTEMS should use as a raisable test interrupt instead.
