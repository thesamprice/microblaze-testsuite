/* __moddi3 for MicroBlaze: libgcc's moddi3.S with what the generic C does
   better, for comparison in bench/moddi3.  Not part of any gcc patch.

   moddi3.S runs one restoring step per bit of the dividend X, whatever
   the divisor D.  This runs one per bit of the quotient, as libgcc2.c's
   shift-and-subtract division does: shift D up under X first, then shift
   it back down one bit per step, keeping 0 <= R < 2Y throughout.

   Kept from moddi3.S: magnitudes first, the remainder taking the sign of
   X, and the keep-or-skip decision read from the sign of one subtraction.
   That is sound for every comparison here because all the quantities
   compared are at most 2^63, so their differences are in signed range.

   Also changed:
     - |X| < |D| returns X at once.  That covers a zero dividend.
     - No stack frame: only caller-saved registers.
     - Y moves right through the carry, SRL then SRC, two instructions.

   Division by zero returns 0, as moddi3.S does.  */

#ifdef __MICROBLAZEEL__
# define OPX_L	r5
# define OPX_H	r6
# define OPD_L	r7
# define OPD_H	r8
# define RES_L	r3
# define RES_H	r4
#else
# define OPX_H	r5
# define OPX_L	r6
# define OPD_H	r7
# define OPD_L	r8
# define RES_H	r3
# define RES_L	r4
#endif

/* OPX holds X, then X >> 1 while D is aligned.  OPD holds D, then Y,
   the shifted divisor.  RES holds R.  */
#define TRIAL_H	r9	/* Trial subtraction.  */
#define TRIAL_L	r10
#define SIGN	r11	/* High word of the dividend, for its sign.  */
#define COUNT	r12	/* Steps remaining, less one.  */

	.text
	.globl	__moddi3
	.ent	__moddi3
	.type	__moddi3, @function
__moddi3:
	.frame	r1,0,r15

	OR	r18,OPD_H,OPD_L
	BEQID	r18,$Lzero		# X % 0: return 0.
	OR	SIGN,r0,OPX_H
	BGEI	OPX_H,$LX_abs
	RSUBI	OPX_L,OPX_L,0
	RSUBIC	OPX_H,OPX_H,0
$LX_abs:
	BGEID	OPD_H,$LD_abs
	OR	RES_L,r0,OPX_L		# R = |X|.
	RSUBI	OPD_L,OPD_L,0
	RSUBIC	OPD_H,OPD_H,0
$LD_abs:
	# |X| < |D|: the remainder is X.  This also catches X == 0.
	OR	RES_H,r0,OPX_H
	RSUB	TRIAL_L,OPD_L,RES_L
	RSUBC	TRIAL_H,OPD_H,RES_H
	BLTI	TRIAL_H,$Lsign

	# Align: the largest K with D << K <= X, i.e. shift D up while it is
	# no more than X >> 1.  Then 2Y > X, so the loop starts with R < 2Y.
	SRL	OPX_H,OPX_H
	SRC	OPX_L,OPX_L
	# A whole word at a time first: D << 32 <= X >> 1 when D's high word
	# is zero and its low word is no more than the high word of X >> 1.
	BNEID	OPD_H,$Lalign
	ADDK	COUNT,r0,r0
	CMPU	r18,OPD_L,OPX_H
	BLTI	r18,$Lalign
	OR	OPD_H,r0,OPD_L
	OR	OPD_L,r0,r0
	ADDIK	COUNT,r0,32
$Lalign:
	RSUB	TRIAL_L,OPD_L,OPX_L
	RSUBC	TRIAL_H,OPD_H,OPX_H
	BLTI	TRIAL_H,$Lstep		# Y > X >> 1: aligned.
	ADD	OPD_L,OPD_L,OPD_L
	ADDC	OPD_H,OPD_H,OPD_H
	BRID	$Lalign
	ADDIK	COUNT,COUNT,1

	# K + 1 steps.  R < 2Y and Y <= 2^63, so R - Y lies in [-Y, Y) and its
	# sign is the comparison.  The SRL in the delay slot sets the carry
	# for the SRC at the bottom; nothing in between touches it.
$Lstep:
	RSUB	TRIAL_L,OPD_L,RES_L
	RSUBC	TRIAL_H,OPD_H,RES_H
	BLTID	TRIAL_H,$Lskip		# R < Y: keep R.
	SRL	OPD_H,OPD_H
	OR	RES_H,r0,TRIAL_H	# R -= Y.
	OR	RES_L,r0,TRIAL_L
$Lskip:
	ADDIK	COUNT,COUNT,-1
	BGEID	COUNT,$Lstep
	SRC	OPD_L,OPD_L

$Lsign:
	# The remainder takes the sign of the dividend.
	BGEI	SIGN,$Lreturn
	RSUBI	RES_L,RES_L,0
	RTSD	r15,8
	RSUBIC	RES_H,RES_H,0
$Lreturn:
	RTSD	r15,8
	NOP
$Lzero:
	OR	RES_H,r0,r0
	RTSD	r15,8
	OR	RES_L,r0,r0
	.end	__moddi3
	.size	__moddi3, . - __moddi3
