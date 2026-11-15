#include <stdio.h>
#include "tables.h"

typedef unsigned (*op_t) (unsigned, unsigned);
extern int __divsi3 (int, int);
extern int __modsi3 (int, int);
extern unsigned __udivsi3 (unsigned, unsigned);
extern unsigned __umodsi3 (unsigned, unsigned);
extern int __mulsi3 (int, int);
extern unsigned long long muldi3_hardproc (unsigned long long, unsigned long long);

static unsigned l_div (unsigned a, unsigned b) { return __divsi3 (a, b); }
static unsigned l_mod (unsigned a, unsigned b) { return __modsi3 (a, b); }
static unsigned l_udiv (unsigned a, unsigned b) { return __udivsi3 (a, b); }
static unsigned l_umod (unsigned a, unsigned b) { return __umodsi3 (a, b); }
static unsigned l_mul (unsigned a, unsigned b) { return __mulsi3 (a, b); }

#define DECL(V) unsigned V##_div (unsigned, unsigned), V##_mod (unsigned, unsigned), \
  V##_udiv (unsigned, unsigned), V##_umod (unsigned, unsigned), V##_mul (unsigned, unsigned);
DECL (small) DECL (hw)

struct variant { const char *name; op_t f[5]; };
static const struct variant variants[] = {
  { "libgcc", { l_div, l_mod, l_udiv, l_umod, l_mul } },
  { "small-divides", { small_div, small_mod, small_udiv, small_umod, small_mul } },
#ifdef WITH_HW
  { "hw-div-mul", { hw_div, hw_mod, hw_udiv, hw_umod, hw_mul } },
#endif
};
static const char *opn[5] = { "div", "mod", "udiv", "umod", "mul" };
static const unsigned *bexp[5] = { bexp_div, bexp_mod, bexp_udiv, bexp_umod, bexp_mul };

static int bad;
static void
report (const char *v, int op, unsigned a, unsigned b, unsigned got, unsigned want)
{
  if (++bad <= 60)
    printf ("MISMATCH %s %s 0x%08x 0x%08x: got 0x%08x want 0x%08x\n",
	    v, opn[op], a, b, got, want);
}

int
main (void)
{
  unsigned v, op, i, j, n = 0;
  setvbuf (stdout, 0, _IONBF, 0);
  printf ("start\n");
  for (v = 0; v < sizeof variants / sizeof variants[0]; v++)
    {
      int before = bad;
      for (op = 0; op < 5; op++)
	{
	  printf ("%s %s\n", variants[v].name, opn[op]);
	  for (i = 0; i < NB; i++)
	    for (j = 0; j < NB; j++)
	      {
		unsigned a = bvals[i], b = bvals[j], got;
		if (b == 0 && op != 4)
		  continue;
		got = variants[v].f[op] (a, b);
		n++;
		if (got != bexp[op][i * NB + j])
		  report (variants[v].name, op, a, b, got, bexp[op][i * NB + j]);
	      }
	  for (i = 0; i < NR; i++)
	    {
	      unsigned a = rvals[i][0], b = rvals[i][1];
	      unsigned got = variants[v].f[op] (a, b);
	      n++;
	      if (got != rvals[i][2 + op])
		report (variants[v].name, op, a, b, got, rvals[i][2 + op]);
	    }
	}
      printf ("%s: %d mismatches\n", variants[v].name, bad - before);
      /* Division by zero: report, do not check.  */
      for (op = 0; op < 4; op++)
	printf ("%s %s by zero: 7/0=0x%08x  -7/0=0x%08x  0/0=0x%08x\n",
		variants[v].name, opn[op], variants[v].f[op] (7, 0),
		variants[v].f[op] (-7, 0), variants[v].f[op] (0, 0));
    }
#ifdef WITH_HW
  {
    int before = bad;
    for (i = 0; i < ND; i++)
      for (j = 0; j < ND; j++)
	{
	  unsigned long long got = muldi3_hardproc (dvals[i], dvals[j]);
	  n++;
	  if (got != dexp_mul[i * ND + j] && ++bad <= 80)
	    printf ("MISMATCH muldi3_hardproc 0x%016llx 0x%016llx: got 0x%016llx want 0x%016llx\n",
		    dvals[i], dvals[j], got, dexp_mul[i * ND + j]);
	}
    printf ("muldi3_hardproc: %d mismatches\n", bad - before);
  }
#endif
  printf ("%u checks, %d mismatches\n", n, bad);
  printf ("*** EXIT code %d\n", bad != 0);
  return 0;
}
