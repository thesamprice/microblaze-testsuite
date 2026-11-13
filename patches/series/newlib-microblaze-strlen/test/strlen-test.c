/* Check a MicroBlaze strlen at every start alignment 0-7 and every length
   0-LMAX, and count the instructions each call executes, on QEMU's
   petalogix-s3adsp1800 with the test device from microblaze-testsuite's
   patches/qemu/0001, under -icount.

   The bytes before the string are zero, so a strlen that looks before
   its start returns a wrong length; the bytes after the NUL are zero too
   in one pass and non-zero in another, so a pcmpbf that picks the wrong
   zero byte, or a scan that misses the first NUL, shows.  The string's
   own bytes cycle through values chosen to defeat the usual word tricks:
   0x01, 0x80, 0xff, 0x7f and 0x81.

   Prints COUNT lines for selected lengths and a total, then exits QEMU
   with the number of wrong results as the status.  */

#define UART ((volatile unsigned int *) 0x84000000)
#define TESTDEV ((volatile unsigned int *) 0xff000000)

#ifndef LMAX
#define LMAX 160
#endif

typedef unsigned long size_t;
extern size_t strlen (const char *);

/* Through a volatile pointer, so the call is a call.  */
static size_t (*volatile fn) (const char *) = strlen;

static void
putc_ (char c)
{
  while (UART[2] & 0x8)
    ;
  UART[1] = (unsigned char) c;
}

static void
puts_ (const char *s)
{
  while (*s)
    putc_ (*s++);
}

static void
putu (unsigned v)
{
  char b[12];
  int i = 0;
  do
    {
      /* v % 10 and v / 10 without libgcc's divide.  */
      unsigned q = 0, r = v;
      while (r >= 10)
	r -= 10, q++;
      b[i++] = '0' + r;
      v = q;
    }
  while (v);
  while (i)
    putc_ (b[--i]);
}

static inline unsigned
count (void)
{
  return TESTDEV[1];
}

static unsigned char buf[LMAX + 64] __attribute__ ((aligned (16)));
static const unsigned char pat[] = { 0x01, 0x80, 0xff, 0x7f, 0x81, 'a' };

/* Instructions for each alignment and length, from the pass with zero
   bytes after the NUL.  */
static unsigned insns[8][LMAX + 1];

void
main_ (void)
{
  unsigned base = ~0U, bad = 0, n = 0;
  unsigned long long total4 = 0;

  for (int i = 0; i < 8; i++)
    {
      unsigned t0 = count ();
      __asm__ volatile ("" ::: "memory");
      unsigned t1 = count ();
      if (t1 - t0 < base)
	base = t1 - t0;
    }

  for (int tail = 0; tail < 2; tail++)
    for (int al = 0; al < 8; al++)
      for (int len = 0; len <= LMAX; len++)
	{
	  for (unsigned i = 0; i < sizeof buf; i++)
	    buf[i] = 0;
	  const char *s = (const char *) buf + 8 + al;
	  /* pat[k], with k counting modulo the size of pat by hand, since
	     % would need libgcc.  */
	  unsigned k = 0;
	  for (int i = 0; i < len; i++)
	    {
	      buf[8 + al + i] = pat[k];
	      if (++k == sizeof pat)
		k = 0;
	    }
	  if (tail)
	    for (unsigned i = 8 + al + len + 1; i < sizeof buf; i++)
	      {
		buf[i] = pat[k];
		if (++k == sizeof pat)
		  k = 0;
	      }

	  unsigned t0 = count ();
	  size_t r = fn (s);
	  unsigned t1 = count ();
	  n++;
	  if (r != (size_t) len)
	    {
	      bad++;
	      if (bad <= 20)
		{
		  puts_ ("BAD al=");
		  putu (al);
		  puts_ (" len=");
		  putu (len);
		  puts_ (" tail=");
		  putu (tail);
		  puts_ (" got=");
		  putu (r);
		  puts_ ("\r\n");
		}
	    }
	  if (!tail)
	    {
	      insns[al][len] = t1 - t0 - base;
	      if (al < 4)
		total4 += t1 - t0 - base;
	    }
	}

  static const int show[] = { 0, 1, 2, 3, 4, 5, 7, 8, 15, 16, 31, 32, 63, 64,
			      100, 160 };
  for (unsigned k = 0; k < sizeof show / sizeof show[0]; k++)
    {
      int len = show[k];
      if (len > LMAX)
	continue;
      puts_ ("COUNT len=");
      putu (len);
      for (int al = 0; al < 4; al++)
	{
	  puts_ (" a");
	  putu (al);
	  puts_ ("=");
	  putu (insns[al][len]);
	}
      puts_ ("\r\n");
    }
  puts_ ("TOTAL calls=");
  putu (n);
  puts_ (" bad=");
  putu (bad);
  puts_ (" insns_a0-3_len0-");
  putu (LMAX);
  puts_ ("=");
  putu ((unsigned) total4);
  puts_ (" overhead=");
  putu (base);
  puts_ ("\r\n");

  TESTDEV[0] = bad ? 1 : 0;
  for (;;)
    ;
}
