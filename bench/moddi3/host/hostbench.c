/* Host-side check and timing of one of __moddi3, __umoddi3, __divdi3 or
   __udivdi3, chosen by OP, against the vectors bench/moddi3/gen.c writes.

   The routine under test is linked from an object built from libgcc2.c,
   which takes precedence over the host's own libgcc.  NATIVE instead
   times the compiler's own 64-bit / or %, which on a 64-bit host is one
   divide instruction, for reference.

   There is no instruction counter here, so this times: each trial runs
   every vector REPS times, and the best of TRIALS trials is reported, per
   vector class and in all, in nanoseconds per call.  */

#include <stdio.h>
#include <time.h>
#include "vectors.h"

typedef unsigned long long u64;
#if OP == 0
# define FN __moddi3
# define WANT(t) ((u64) (t).r)
# define NATIVE_EXPR(a, b) ((u64) ((long long) (a) % (long long) (b)))
#elif OP == 1
# define FN __umoddi3
# define WANT(t) ((t).ur)
# define NATIVE_EXPR(a, b) ((a) % (b))
#elif OP == 2
# define FN __divdi3
# define WANT(t) ((u64) (t).q)
# define NATIVE_EXPR(a, b) ((u64) ((long long) (a) / (long long) (b)))
#elif OP == 3
# define FN __udivdi3
# define WANT(t) ((t).uq)
# define NATIVE_EXPR(a, b) ((a) / (b))
#else
# error "OP must be 0 to 3"
#endif

#ifdef NATIVE
static u64 __attribute__ ((noinline))
native (u64 a, u64 b)
{
  return NATIVE_EXPR (a, b);
}
# define TARGET native
#else
extern u64 FN (u64, u64);
# define TARGET FN
#endif

static u64 (*volatile fn) (u64, u64) = TARGET;

#define REPS 200
#define TRIALS 9

static double
now (void)
{
  struct timespec ts;
  clock_gettime (CLOCK_MONOTONIC, &ts);
  return ts.tv_sec * 1e9 + ts.tv_nsec;
}

int
main (void)
{
  u64 (*f) (u64, u64) = fn;
  unsigned bad = 0;
  for (unsigned i = 0; i < NTV; i++)
    if (f ((u64) tv[i].a, (u64) tv[i].b) != WANT (tv[i]))
      bad++;

  /* Each class's vectors, and all of them, as index lists, so a trial
     touches only the vectors it times.  */
  static unsigned idx[NCLASS + 1][NTV];
  unsigned n[NCLASS + 1] = { 0 };
  double best[NCLASS + 1];
  for (unsigned i = 0; i < NTV; i++)
    {
      idx[tv[i].cls][n[tv[i].cls]++] = i;
      idx[NCLASS][n[NCLASS]++] = i;
    }
  for (int c = 0; c <= NCLASS; c++)
    best[c] = 1e300;

  volatile u64 sink = 0;
  for (int t = 0; t < TRIALS; t++)
    for (int c = 0; c <= NCLASS; c++)
      {
	double t0 = now ();
	for (int r = 0; r < REPS; r++)
	  for (unsigned j = 0; j < n[c]; j++)
	    {
	      unsigned i = idx[c][j];
	      sink += f ((u64) tv[i].a, (u64) tv[i].b);
	    }
	double ns = (now () - t0) / ((double) REPS * n[c]);
	if (ns < best[c])
	  best[c] = ns;
      }

  printf ("HOST bad=%u all=%.2f", bad, best[NCLASS]);
  for (int c = 0; c < NCLASS; c++)
    printf (" %s=%.2f", class_name[c], best[c]);
  printf ("\n");
  return bad != 0;
}
