/*
 * xps-timer behaviour that Sebastian Huber's "[PATCH 0/2] Fix two
 * Xilinx Timer issues" changes.  Timer 1 runs free as the time
 * reference; timer 0 is the one under test.  Results go to the serial
 * port, in timer ticks (62 MHz on petalogix-s3adsp1800):
 *
 *   periodic  N periods of a P-tick auto-reload timer whose handler
 *             acknowledges with ENT still set; prints the mean period.
 *             Patch 1: the acknowledge no longer restarts the count.
 *             Patch 2: the reload happens at the expiry, not when the
 *             callback runs.
 *   oneshot   a P-tick timer without ARHT, acknowledged with ENT still
 *             set; prints how many interrupts arrive in 20 P.  The
 *             hardware gives one.  Patch 1.
 *   tlr       TLR0 rewritten to 2 P from the handler of a running
 *             periodic timer; prints the mean period after the change.
 *             Patch 2.
 *
 * Exit status 0 if all three match the expected values, else the
 * number of the first that did not.
 */
#include "board.h"

#define TCSR1	REG (TMR + 0x10)
#define TLR1	REG (TMR + 0x14)
#define TCR1	REG (TMR + 0x18)

#ifndef P
# define P	6200		/* 100 us */
#endif
#define N	64

static volatile int irqs, change_at = -1;
static volatile uint32_t stamp[N + 1];

static void
putc_ (int c)
{
  while (!(UART_STAT & STAT_TXEMPTY))
    ;
  UART_TX = c;
}

static void
puts_ (const char *s)
{
  while (*s)
    putc_ (*s++);
}

static void
putdec (uint32_t v)
{
  char b[12];
  int i = 0;
  /* No divide: subtract powers of ten.  */
  static const uint32_t p10[] = { 1000000000, 100000000, 10000000, 1000000,
                                  100000, 10000, 1000, 100, 10, 1 };
  int started = 0;
  for (int k = 0; k < 10; k++)
    {
      int d = 0;
      while (v >= p10[k])
        v -= p10[k], d++;
      if (d || started || k == 9)
        b[i++] = '0' + d, started = 1;
    }
  b[i] = 0;
  puts_ (b);
}

void
irq_handler (void)
{
  if (irqs <= N)
    stamp[irqs] = TCR1;
  irqs++;
  if (irqs == change_at)
    TLR0 = 2 * P;
  TCSR0 = TCSR0 | TCSR_TINT;	/* acknowledge, ENT still set */
  INTC_IAR = 1 << TIMER_IRQ;
}

static void
start1 (void)
{
  TLR1 = 0;
  TCSR1 = TCSR_LOAD;
  TCSR1 = TCSR_ENT;		/* count up from 0, no interrupt */
}

static void
wait_ticks (uint32_t t)
{
  uint32_t t0 = TCR1;
  while (TCR1 - t0 < t)
    ;
}

static void
stop0 (void)
{
  TCSR0 = TCSR_TINT;		/* ENT and ENIT clear */
  INTC_IAR = 1 << TIMER_IRQ;
}

/* Mean of stamp[to] - stamp[from] over to - from periods, in ticks,
   rounded down; also prints the remainder in 1/64 tick units.  */
static uint32_t
report (const char *name, int from, int to)
{
  uint32_t d = stamp[to] - stamp[from], n = to - from, q = 0;
  /* n is a power of two here.  */
  int sh = 0;
  while ((1u << sh) < n)
    sh++;
  q = d >> sh;
  puts_ (name);
  puts_ (" total=");
  putdec (d);
  puts_ (" periods=");
  putdec (n);
  puts_ (" mean=");
  putdec (q);
  puts_ ("+");
  putdec (((d - (q << sh)) << 6) >> sh);
  puts_ ("/64\n");
  return q;
}

int
main (void)
{
  int fail = 0;
  uint32_t m;

  INTC_IER = 1 << TIMER_IRQ;
  INTC_MER = MER_ME | MER_HIE;
  start1 ();
  irq_enable ();

  /* periodic */
  irqs = 0;
  TLR0 = P;
  TCSR0 = TCSR_LOAD | TCSR_UDT | TCSR_ARHT;
  TCSR0 = TCSR_ENT | TCSR_ENIT | TCSR_UDT | TCSR_ARHT;
  while (irqs <= N)
    ;
  stop0 ();
  m = report ("periodic", 0, N);
#ifdef DUMP
  for (int i = 1; i <= N; i++)
    {
      putdec (stamp[i] - stamp[i - 1]);
      putc_ (i % 16 ? ' ' : '\n');
    }
#endif
  /* The model's period is TLR ticks; allow 2 more for a reload
     latency, which hardware may have (not checked against PG079).  */
  if (!fail && (m < P || m > P + 2))
    fail = 1;

  /* oneshot */
  irqs = 0;
  TLR0 = P;
  TCSR0 = TCSR_LOAD | TCSR_UDT;
  TCSR0 = TCSR_ENT | TCSR_ENIT | TCSR_UDT;
  wait_ticks (20 * P);
  stop0 ();
  puts_ ("oneshot irqs=");
  putdec (irqs);
  puts_ ("\n");
  if (!fail && irqs != 1)
    fail = 2;

  /* tlr: change the load value from the 8th handler; time 32 periods
     after the first full period at the new value.  */
  irqs = 0;
  change_at = 8;
  TLR0 = P;
  TCSR0 = TCSR_LOAD | TCSR_UDT | TCSR_ARHT;
  TCSR0 = TCSR_ENT | TCSR_ENIT | TCSR_UDT | TCSR_ARHT;
  while (irqs <= 8 + 1 + 32)
    ;
  stop0 ();
  m = report ("tlr", 9, 9 + 32);
  if (!fail && (m < 2 * P || m > 2 * P + 2))
    fail = 3;

  irq_disable ();
  return fail;
}
