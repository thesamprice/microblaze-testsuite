/* petalogix-s3adsp1800 devices, as QEMU's
   hw/microblaze/petalogix_s3adsp1800_mmu.c maps them.  */
#ifndef BOARD_H
#define BOARD_H
#include <stdint.h>

#define REG(a) (*(volatile uint32_t *) (a))

#define INTC		0x81800000
#define INTC_ISR	REG (INTC + 0x00)
#define INTC_IPR	REG (INTC + 0x04)
#define INTC_IER	REG (INTC + 0x08)
#define INTC_IAR	REG (INTC + 0x0c)
#define INTC_MER	REG (INTC + 0x1c)
#define MER_ME		1
#define MER_HIE		2

#define TIMER_IRQ	0
#define UART_IRQ	3

#define TMR		0x83c00000
#define TCSR0		REG (TMR + 0x00)
#define TLR0		REG (TMR + 0x04)
#define TCR0		REG (TMR + 0x08)
#define TCSR_UDT	(1 << 1)
#define TCSR_ARHT	(1 << 4)
#define TCSR_LOAD	(1 << 5)
#define TCSR_ENIT	(1 << 6)
#define TCSR_ENT	(1 << 7)
#define TCSR_TINT	(1 << 8)
#define TIMER_HZ	62000000	/* the board's clock-frequency */

#define UART		0x84000000
#define UART_RX		REG (UART + 0x0)
#define UART_TX		REG (UART + 0x4)
#define UART_STAT	REG (UART + 0x8)
#define UART_CTRL	REG (UART + 0xc)
#define STAT_RXVALID	0x01
#define STAT_TXEMPTY	0x04
#define STAT_INTR_EN	0x10
#define CTRL_RST_TX	0x01
#define CTRL_RST_RX	0x02
#define CTRL_INTR_EN	0x10

#define TESTDEV_EXIT	REG (0xff000000)
#define TESTDEV_ICOUNT	REG (0xff000004)	/* only under -icount */

static inline void irq_enable (void)
{
  __asm__ volatile ("msrset r0, 2" ::: "memory");
}

static inline void irq_disable (void)
{
  __asm__ volatile ("msrclr r0, 2" ::: "memory");
}

void irq_handler (void);
#endif
