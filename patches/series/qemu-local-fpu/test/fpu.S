/*
 * fcmp.le, fcmp.ge and fint against UG984.  fcmp compares rB with rA
 * (Table 104); fint truncates.  Runs on petalogix-s3adsp1800 (whose
 * CPU has use-fpu=2) with the exit device from microblaze-testsuite
 * patches/qemu/0001 at 0xff000000: the exit status is the number of
 * the first check that failed, or 0 for a pass.
 */
#define ONE	0x3f800000	/* 1.0 */
#define TWO	0x40000000	/* 2.0 */
#define QNAN	0x7fc00000

	.text
	.globl	_start
_start:
	addk	r20, r0, r0		/* first failed check */
	/* MSR[EE] is clear from reset, so the NaN compares below set
	   FSR[IO] without trapping.  */
	addik	r10, r0, ONE
	addik	r11, r0, TWO
	addik	r12, r0, QNAN

#define CHECK(reg, val, n)		\
	addik	r18, r0, val;		\
	cmp	r18, r18, reg;		\
	beqi	r18, 1f;		\
	bnei	r20, 1f;		\
	addik	r20, r0, n;		\
1:

/* fcmp.OP rD, rA, rB gives (rB OP rA).  */
	fcmp.lt	r3, r11, r10		/* 1 < 2 */
	CHECK(r3, 1, 1)
	fcmp.gt	r3, r11, r10		/* 1 > 2 */
	CHECK(r3, 0, 2)
	fcmp.le	r3, r11, r10		/* 1 <= 2 */
	CHECK(r3, 1, 3)
	fcmp.le	r3, r10, r11		/* 2 <= 1 */
	CHECK(r3, 0, 4)
	fcmp.le	r3, r10, r10		/* 1 <= 1 */
	CHECK(r3, 1, 5)
	fcmp.ge	r3, r11, r10		/* 1 >= 2 */
	CHECK(r3, 0, 6)
	fcmp.ge	r3, r10, r11		/* 2 >= 1 */
	CHECK(r3, 1, 7)
	fcmp.ge	r3, r10, r10		/* 1 >= 1 */
	CHECK(r3, 1, 8)
	fcmp.ge	r3, r12, r10		/* 1 >= NaN: unordered */
	CHECK(r3, 0, 9)
	fcmp.ge	r3, r10, r12		/* NaN >= 1: unordered */
	CHECK(r3, 0, 10)
	fcmp.le	r3, r12, r10		/* 1 <= NaN: unordered */
	CHECK(r3, 0, 11)

/* fint truncates toward zero.  */
#define FINT(bits, want, n)		\
	addik	r5, r0, bits;		\
	fint	r3, r5;			\
	CHECK(r3, want, n)

	FINT(0x40200000, 2, 12)		/* 2.5 */
	FINT(0x40300000, 2, 13)		/* 2.75 */
	FINT(0xc0300000, -2, 14)	/* -2.75 */
	FINT(0x40600000, 3, 15)		/* 3.5 */
	FINT(0xbf400000, 0, 16)		/* -0.75 */
	FINT(0x4b000001, 8388609, 17)	/* 8388609.0, exact */

	addik	r3, r0, 0xff000000
	swi	r20, r3, 0
2:	bri	2b
