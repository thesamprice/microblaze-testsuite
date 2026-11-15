/* Shift and add over the operand of smaller magnitude, as mulsi3.S does
   with B: a * b is -(a * -b) modulo 2^32, so a negative operand costs as
   many iterations as its absolute value has bits.  */
unsigned int
__mulsi3 (unsigned int a, unsigned int b)
{
  unsigned int r = 0, neg = 0, t;
  if ((int) a < 0)
    {
      a = -a;
      neg = 1;
    }
  if ((int) b < 0)
    {
      b = -b;
      neg ^= 1;
    }
  if (b > a)
    {
      t = a;
      a = b;
      b = t;
    }
  while (b)
    {
      if (b & 1)
	r += a;
      a <<= 1;
      b >>= 1;
    }
  return neg ? -r : r;
}
