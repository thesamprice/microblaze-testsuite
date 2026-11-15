/* Cortex-M0 counterpart of ../bench.c: call one 64-bit divide routine,
   chosen by OP, once per vector in cvec.h (from mkvec.c), check every
   result, and report the number of wrong ones.  armcount.c counts each
   call's instructions; this program does no timing of its own.

     OP  0 __moddi3  1 __umoddi3  2 __divdi3  3 __udivdi3
         4 __aeabi_ldivmod  5 __aeabi_uldivmod (quotient and remainder)

   Runs on QEMU's micro:bit (a Cortex-M0) with semihosting, through rt.c.  */

#include "cvec.h"

typedef unsigned long long u64;

#if OP == 0
# define FN __moddi3
#elif OP == 1
# define FN __umoddi3
#elif OP == 2
# define FN __divdi3
#elif OP == 3
# define FN __udivdi3
#elif OP == 4
# define FN __aeabi_ldivmod
#elif OP == 5
# define FN __aeabi_uldivmod
#else
# error "OP must be 0 to 5"
#endif
extern u64 FN (u64, u64);

/* rt.c: call FN (A, B) and store r2:r3, the AEABI remainder, in *REM.  */
extern u64 call_divmod (u64 a, u64 b, u64 (*fn) (u64, u64), u64 *rem);
extern void sh_write0 (const char *);
extern void sh_exit (int);

static void
putu (char *p, unsigned v)
{
  char t[12];
  int n = 0;
  do
    t[n++] = '0' + v % 10;	/* 32-bit: __aeabi_uidivmod, not counted */
  while (v /= 10);
  while (n)
    *p++ = t[--n];
  *p = 0;
}

int
main (void)
{
  u64 (*fn) (u64, u64) = FN;
  unsigned bad = 0;
  char line[64] = "BENCH bad=";

  __asm__ volatile ("" : "+r" (fn));
  for (int i = 0; i < NTV; i++)
    {
#if OP >= 4
      u64 rem;
      u64 q = call_divmod (va[i], vb[i], fn, &rem);
      bad += q != vw[i] || rem != vr[i];
#else
      bad += fn (va[i], vb[i]) != vw[i];
#endif
    }
  putu (line + 10, bad);
  sh_write0 (line);
  sh_write0 ("\n");
  return bad != 0;
}
