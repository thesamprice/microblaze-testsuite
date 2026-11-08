/* __moddi3 in portable C, for comparison with libgcc's moddi3.S and with
   the generic __moddi3 in libgcc2.c.

   Restoring shift-and-subtract division that keeps only the remainder, as
   moddi3.S does, but with the divisor shifted up under the dividend first,
   as libgcc2.c's TARGET_HAS_NO_HW_DIVIDE __udivmoddi4 does, so the loop
   runs once per quotient bit rather than once per dividend bit.

   With -DFUSED, the keep-or-skip test is moddi3.S's: one subtraction, and
   the sign of the result decides.  With the divisor aligned that is sound
   for any operands, not only magnitudes of signed values.  The shifted
   divisor Y has its top bit where X has its, so the first R - Y is smaller
   in magnitude than that bit; after that R < Y before each halving of Y,
   so R <= 2Y after it, and R - Y lies between -Y and Y with Y at most half
   the range.  patches/gcc/0002 uses it for __umoddi3 as well.  Without
   -DFUSED it is the plain unsigned comparison.

   With -DLEFT, the divisor stays put and the dividend's bits are shifted
   into the remainder from the right, as moddi3.S does, still only as many
   of them as the quotient can have.  The sign test is the fused one.

   Division by zero returns the dividend, as a core with a hardware divide
   would (a - (a / 0) * 0 with a zero quotient).  moddi3.S returns zero.
   Either is allowed: the behaviour is undefined.  */

typedef long long DItype;
typedef unsigned long long UDItype;

DItype
__moddi3 (DItype u, DItype v)
{
  UDItype x = u < 0 ? -(UDItype) u : (UDItype) u;
  UDItype d = v < 0 ? -(UDItype) v : (UDItype) v;
  UDItype r = x;

  /* 1 <= D <= X, else the remainder is X.  */
  if (d - 1 < x)
    {
      int k = __builtin_clzll (d) - __builtin_clzll (x);
#ifdef LEFT
      /* The quotient has at most K + 1 bits.  Everything of X above them
	 is a partial remainder smaller than D to start from; the K + 1 bits
	 left are moved to the top of X and shifted into R one at a time,
	 with D fixed, as moddi3.S does.  R < D <= 2^63 throughout, so
	 2R + 1 cannot overflow and 2R + 1 - D lies in [-D, D).  */
      r = (x >> k) >> 1;
      x <<= 63 - k;
      do
	{
	  r = (r << 1) | (x >> 63);
	  x <<= 1;
	  UDItype t = r - d;
	  if ((DItype) t >= 0)
	    r = t;
	}
      while (--k >= 0);
#else
      UDItype y = d << k;
      do
	{
# ifdef FUSED
	  UDItype t = r - y;
	  if ((DItype) t >= 0)
	    r = t;
# else
	  if (r >= y)
	    r -= y;
# endif
	  y >>= 1;
	}
      while (--k >= 0);
#endif
    }

  return u < 0 ? -(DItype) r : (DItype) r;
}
