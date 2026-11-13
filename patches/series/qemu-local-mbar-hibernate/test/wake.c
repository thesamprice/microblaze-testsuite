/*
 * hibernate (mbar 8) must halt the CPU until an interrupt, as sleep
 * (mbar 16) does.  A one-shot timer interrupt about 1 ms after the
 * instruction wakes it.  Exit status: 0 if the CPU waited for the
 * interrupt, 1 if it ran past the instruction first, 2 if it never
 * saw the interrupt at all.
 */
#include "board.h"

static volatile int irqs;

void
irq_handler (void)
{
  TCSR0 = TCSR0;		/* T0INT is write-one-to-clear */
  INTC_IAR = 1 << TIMER_IRQ;
  irqs++;
}

int
main (void)
{
  int seen;

  INTC_IER = 1 << TIMER_IRQ;
  INTC_MER = MER_ME | MER_HIE;

  TLR0 = TIMER_HZ / 1000;
  TCSR0 = TCSR_LOAD | TCSR_UDT;
  TCSR0 = TCSR_ENT | TCSR_ENIT | TCSR_UDT;
  irq_enable ();
#ifndef INSN
# define INSN "hibernate"
#endif
  __asm__ volatile (INSN ::: "memory");
  seen = irqs;
  for (volatile int i = 0; i < 10000000 && irqs == 0; i++)
    ;
  if (irqs == 0)
    return 2;
  return seen == 0 ? 1 : 0;
}
