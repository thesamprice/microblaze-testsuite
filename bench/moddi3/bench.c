/* Check one of __moddi3, __umoddi3, __divdi3 or __udivdi3, chosen by OP,
   against the vectors in vectors.h and count the instructions it executes, on QEMU's petalogix-s3adsp1800 with the test
   device from patches/qemu/0001 and -icount.

   Each call is bracketed by two reads of the instruction counter.  Two
   back-to-back reads are measured first and subtracted, so a call's count
   is the instructions from the indirect branch into the routine to its return,
   delay slots included.  The operands are already in registers before the
   first read.

   Prints one line per vector class and a total, then exits QEMU through
   the test device with the number of wrong results as the status.  */

#include "vectors.h"

#define UART ((volatile unsigned int *) 0x84000000)
#define TESTDEV ((volatile unsigned int *) 0xff000000)

#define EXIT_REG (TESTDEV[0])
#define COUNT_LO (TESTDEV[1])
#define COUNT_HI (TESTDEV[2])

static void
putc_ (char c)
{
  while (UART[2] & 0x8)		/* TX FIFO full */
    ;
  UART[1] = (unsigned char) c;
}

static void
puts_ (const char *s)
{
  while (*s)
    putc_ (*s++);
}

/* Decimal by repeated subtraction: a 64-bit divide would call libgcc,
   which this program links none of.  */
static void
putu (unsigned long long v)
{
  unsigned long long p = 10000000000000000000ULL;
  int started = 0;
  for (int i = 0; i < 20; i++)
    {
      char c = '0';
      while (v >= p)
	v -= p, c++;
      if (c != '0' || started || i == 19)
	putc_ (c), started = 1;
      /* p /= 10 without a division: the next power down.  */
      unsigned long long q = 1;
      while (q * 10 < p)
	q *= 10;
      p = q;
    }
}

/* The 64-bit counter.  A read of the low half latches the high half.  */
static inline unsigned long long
count (void)
{
  unsigned lo = COUNT_LO;
  return ((unsigned long long) COUNT_HI << 32) | lo;
}

/* All four take and return a 64-bit value in the same registers, so
   they can share one pointer type whether signed or not.  */
typedef unsigned long long u64;
#if OP == 0
# define FN __moddi3
# define WANT(t) ((u64) (t).r)
#elif OP == 1
# define FN __umoddi3
# define WANT(t) ((t).ur)
#elif OP == 2
# define FN __divdi3
# define WANT(t) ((u64) (t).q)
#elif OP == 3
# define FN __udivdi3
# define WANT(t) ((t).uq)
#else
# error "OP must be 0 to 3"
#endif
extern u64 FN (u64, u64);

/* Called through a volatile pointer so that the compiler cannot move the
   call across the counter reads or inline anything into it.  */
static u64 (*volatile modfn) (u64, u64) = FN;

struct stat
{
  unsigned n, bad;
  unsigned long long sum;
  unsigned min, max;
};

static struct stat st[NCLASS + 1];

static void
report (const char *name, const struct stat *s)
{
  puts_ ("BENCH ");
  puts_ (name);
  puts_ (" n=");
  putu (s->n);
  puts_ (" bad=");
  putu (s->bad);
  puts_ (" insns=");
  putu (s->sum);
  puts_ (" min=");
  putu (s->min);
  puts_ (" max=");
  putu (s->max);
  puts_ ("\r\n");
}

void
main_ (void)
{
  u64 (*fn) (u64, u64) = modfn;
  unsigned long long t0, t1, base = ~0ULL;

  /* The cost of the two counter reads themselves.  */
  for (int i = 0; i < 8; i++)
    {
      t0 = count ();
      __asm__ volatile ("" ::: "memory");
      t1 = count ();
      if (t1 - t0 < base)
	base = t1 - t0;
    }

  for (int c = 0; c <= NCLASS; c++)
    st[c].min = ~0U;

  for (unsigned i = 0; i < NTV; i++)
    {
      u64 a = (u64) tv[i].a, b = (u64) tv[i].b, r;
      __asm__ volatile ("" : "+r" (a), "+r" (b));
      t0 = count ();
      r = fn (a, b);
      t1 = count ();
      unsigned d = (unsigned) (t1 - t0 - base);

      struct stat *s;
      for (int k = 0; k < 2; k++)
	{
	  s = k ? &st[NCLASS] : &st[tv[i].cls];
	  s->n++;
	  s->bad += r != WANT (tv[i]);
	  s->sum += d;
	  if (d < s->min)
	    s->min = d;
	  if (d > s->max)
	    s->max = d;
	}
    }

  puts_ ("BENCH overhead=");
  putu (base);
  puts_ ("\r\n");
  for (int c = 0; c < NCLASS; c++)
    report (class_name[c], &st[c]);
  report ("all", &st[NCLASS]);

  EXIT_REG = st[NCLASS].bad ? 1 : 0;
  for (;;)
    ;
}
