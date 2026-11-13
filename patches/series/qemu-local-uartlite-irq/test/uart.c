/*
 * xilinx_uartlite interrupt against PG142: a rising edge "when the
 * receive FIFO becomes non-empty or when the transmit FIFO becomes
 * empty", if enabled; STAT_REG bit 4 says whether interrupts are
 * enabled.  The CPU's interrupt stays off; the test reads the INTC's
 * ISR, where the UART input is edge-triggered on this board.
 *
 * Run with "xy" on the serial input for the receive checks.  Every
 * check runs; the failed ones are listed on the serial output as
 * "FAIL n", after the characters the test transmits.  Exit status:
 * the number of the first check that failed, or 0.
 */
#include "board.h"

#define UART_BIT (1u << UART_IRQ)

static int n, first;
static unsigned failed;
#define CHECK(c) do { n++; if (!(c)) { failed |= 1u << n; \
                                        if (!first) first = n; } } while (0)

void irq_handler (void) { }

static void
ack (void)
{
  INTC_IAR = UART_BIT;
}

static int
wait_rx (void)
{
  for (volatile int i = 0; i < 1000000000; i++)
    if (UART_STAT & STAT_RXVALID)
      return 1;
  return 0;
}

int
main (void)
{
  INTC_IER = UART_BIT;
  INTC_MER = MER_ME | MER_HIE;
  UART_CTRL = 0;
  ack ();

  CHECK ((UART_STAT & STAT_INTR_EN) == 0);	/* 1 */

  /* Transmit with interrupts disabled: no interrupt.  */
  UART_TX = 'a';
  CHECK ((INTC_ISR & UART_BIT) == 0);		/* 2 */
  CHECK ((UART_STAT & STAT_INTR_EN) == 0);	/* 3 */

  /* Enabling interrupts is not an event.  */
  UART_CTRL = CTRL_INTR_EN;
  CHECK ((UART_STAT & STAT_INTR_EN) != 0);	/* 4 */
  CHECK ((INTC_ISR & UART_BIT) == 0);		/* 5 */

  /* The Tx FIFO empties after a character: one interrupt.  */
  UART_TX = 'b';
  CHECK ((INTC_ISR & UART_BIT) != 0);		/* 6 */
  ack ();
  CHECK ((INTC_ISR & UART_BIT) == 0);		/* 7 */

  /* Rewriting the enable, or reading status, is not an event.  */
  UART_CTRL = CTRL_INTR_EN;
  (void) UART_STAT;
  CHECK ((INTC_ISR & UART_BIT) == 0);		/* 8 */

  /* Receive: the first character makes the FIFO non-empty.  */
  CHECK (wait_rx ());				/* 9 */
  for (volatile int i = 0; i < 1000000; i++)	/* let 'y' arrive too */
    ;
  CHECK ((INTC_ISR & UART_BIT) != 0);		/* 10 */
  ack ();
  CHECK (UART_RX == 'x');			/* 11 */
  /* Reading the FIFO is not an event.  */
  CHECK ((INTC_ISR & UART_BIT) == 0);		/* 12 */
  CHECK (wait_rx () && UART_RX == 'y');		/* 13 */
  CHECK ((INTC_ISR & UART_BIT) == 0);		/* 14 */

  /* Disabled again.  */
  UART_CTRL = 0;
  CHECK ((UART_STAT & STAT_INTR_EN) == 0);	/* 15 */
  UART_TX = '\n';
  CHECK ((INTC_ISR & UART_BIT) == 0);		/* 16 */

  for (int i = 1; i <= n; i++)
    if (failed & (1u << i))
      {
        for (const char *p = "FAIL "; *p; p++)
          UART_TX = *p;
        if (i >= 10)
          UART_TX = '1';	/* n < 20, and no divide instruction */
        UART_TX = '0' + (i >= 10 ? i - 10 : i);
        UART_TX = '\n';
      }
  return first;
}
