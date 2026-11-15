/* lm32/_mulsi3.c: shift and add, looping over the bits of B.  */
unsigned int
__mulsi3 (unsigned int a, unsigned int b)
{
  unsigned int result = 0;
  if (a == 0)
    return 0;
  while (b != 0)
    {
      if (b & 1)
	result += a;
      a <<= 1;
      b >>= 1;
    }
  return result;
}
