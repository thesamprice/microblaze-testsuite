/*
 * The same relations from C, compiled with -mhard-float
 * -mxl-float-convert, so GCC emits fcmp.le, fcmp.ge and fint with its
 * own operand order.  Exit status: first failing check, or 0.
 */
#define EXIT (*(volatile unsigned *) 0xff000000)

static volatile float one = 1.0f, two = 2.0f, nan_ = __builtin_nanf ("");
static volatile float f25 = 2.5f, f275 = 2.75f, m275 = -2.75f;

static int le (float a, float b) { return a <= b; }
static int ge (float a, float b) { return a >= b; }

int main_ (void) __attribute__ ((noinline));
int
main_ (void)
{
  int n = 0;
#define T(c) do { n++; if (!(c)) { EXIT = n; for (;;); } } while (0)
  T (le (one, two) == 1);
  T (le (two, one) == 0);
  T (ge (one, two) == 0);
  T (ge (two, one) == 1);
  T (ge (nan_, one) == 0);
  T (le (nan_, one) == 0);
  T ((int) f25 == 2);
  T ((int) f275 == 2);
  T ((int) m275 == -2);
  EXIT = 0;
  for (;;);
}
