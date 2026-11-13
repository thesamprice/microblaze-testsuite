/* Bare-metal start-up with an interrupt vector that calls the C
   function irq_handler ().  A hardware exception exits with 99.  */
	.section .vectors, "ax"
	brai	_start			/* 0x00 reset */
	.org	0x10
	brai	_irq			/* 0x10 interrupt */
	.org	0x20
	brai	_hwex			/* 0x20 hardware exception */

	.text
	.globl	_start
_start:
	addik	r1, r0, _stack_top
	addik	r5, r0, __bss_start
	addik	r6, r0, __bss_end
1:	cmpu	r18, r6, r5
	bgei	r18, 2f
	swi	r0, r5, 0
	brid	1b
	addik	r5, r5, 4
2:	brlid	r15, main
	nop
	addik	r4, r0, 0xff000000	/* exit with main's return value */
	swi	r3, r4, 0
3:	bri	3b

_irq:
	addik	r1, r1, -64
	swi	r3, r1, 4
	swi	r4, r1, 8
	swi	r5, r1, 12
	swi	r6, r1, 16
	swi	r7, r1, 20
	swi	r8, r1, 24
	swi	r9, r1, 28
	swi	r10, r1, 32
	swi	r11, r1, 36
	swi	r12, r1, 40
	swi	r15, r1, 44
	swi	r18, r1, 48
	mfs	r3, rmsr
	swi	r3, r1, 52
	brlid	r15, irq_handler
	nop
	lwi	r3, r1, 52
	mts	rmsr, r3
	lwi	r3, r1, 4
	lwi	r4, r1, 8
	lwi	r5, r1, 12
	lwi	r6, r1, 16
	lwi	r7, r1, 20
	lwi	r8, r1, 24
	lwi	r9, r1, 28
	lwi	r10, r1, 32
	lwi	r11, r1, 36
	lwi	r12, r1, 40
	lwi	r15, r1, 44
	lwi	r18, r1, 48
	rtid	r14, 0
	addik	r1, r1, 64

_hwex:
	addik	r3, r0, 99
	addik	r4, r0, 0xff000000
	swi	r3, r4, 0
4:	bri	4b
