/* Bare-metal entry for strlen-test.c: set the stack, clear .bss, call main_.  */
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
2:	brlid	r15, main_
	nop
3:	bri	3b
