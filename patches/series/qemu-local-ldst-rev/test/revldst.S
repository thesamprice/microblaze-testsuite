/*
 * Reversed sub-word loads and stores must not modify their base
 * register.  Runs on petalogix-s3adsp1800 with the exit device from
 * microblaze-testsuite patches/qemu/0001 at 0xff000000: the exit status
 * is the number of the first check that failed, or 0 for a pass.
 *
 * Each check uses one of the forms where compute_ldst_addr_typea
 * returns a guest register unchanged: rA = 0 or rB = 0.
 */
#ifdef __MICROBLAZEEL__
# define LBUR_EXP	0x11	/* byte at buf + 3 */
# define LHUR_EXP	0x2211	/* bytes 22 11 at buf + 2, swapped */
#else
# define LBUR_EXP	0x44
# define LHUR_EXP	0x4433
#endif

	.data
	.align	2
buf:	.word	0x11223344
buf2:	.word	0

	.text
	.globl	_start
_start:
	addk	r20, r0, r0		/* first failed check */

/* Record check N as failed, if none has yet, unless REG == VAL.  */
#define CHECK(reg, val, n)		\
	addik	r18, r0, val;		\
	cmp	r18, r18, reg;		\
	beqi	r18, 1f;		\
	bnei	r20, 1f;		\
	addik	r20, r0, n;		\
1:

	/* 1: lbur rD, rA, r0 */
	addik	r5, r0, buf
	lbur	r3, r5, r0
	CHECK(r5, buf, 1)
	CHECK(r3, LBUR_EXP, 2)

	/* 2: lbur rD, r0, rB */
	addik	r5, r0, buf
	lbur	r3, r0, r5
	CHECK(r5, buf, 3)
	CHECK(r3, LBUR_EXP, 4)

	/* 3: lhur rD, rA, r0 */
	addik	r5, r0, buf
	lhur	r3, r5, r0
	CHECK(r5, buf, 5)
	CHECK(r3, LHUR_EXP, 6)

	/* 4: lhur rD, r0, rB */
	addik	r5, r0, buf
	lhur	r3, r0, r5
	CHECK(r5, buf, 7)
	CHECK(r3, LHUR_EXP, 8)

	/* 5: sbr rD, rA, r0; must write the byte that lbur reads.  */
	addik	r5, r0, buf2
	addik	r4, r0, 0xab
	sbr	r4, r5, r0
	CHECK(r5, buf2, 9)
	addik	r6, r0, buf2
	lbur	r3, r6, r0
	CHECK(r3, 0xab, 10)

	/* 6: shr rD, r0, rB; must write the halfword that lhur reads.  */
	addik	r5, r0, buf2
	addik	r4, r0, 0x1234
	shr	r4, r0, r5
	CHECK(r5, buf2, 11)
	addik	r6, r0, buf2
	lhur	r3, r6, r0
	CHECK(r3, 0x1234, 12)

	/* 7: lwr does no address swizzle; its base was never at risk.  */
	addik	r5, r0, buf
	lwr	r3, r5, r0
	CHECK(r5, buf, 13)

	/* 8: the base must still be usable as a loop pointer.  */
	addik	r5, r0, buf
	addik	r7, r0, 4		/* iterations */
	addk	r8, r0, r0
2:	lbur	r3, r5, r0
	addk	r8, r8, r3
	addik	r7, r7, -1
	bneid	r7, 2b
	nop
	CHECK(r5, buf, 14)
	CHECK(r8, 4 * LBUR_EXP, 15)

	addik	r3, r0, 0xff000000
	swi	r20, r3, 0
3:	bri	3b
