/* Call FN (a 64-bit multiply) on operand set SET of b64.h.  */
#include "b64.h"
#define TESTDEV ((volatile unsigned int *) 0xff000000)
extern unsigned long long FN (unsigned long long, unsigned long long);
volatile unsigned long long sink;
void
main_ (void)
{
  unsigned i;
  for (i = 0; i < NS; i++)
    sink += FN (bset[SET][i][0], bset[SET][i][1]);
  TESTDEV[0] = 0;
  for (;;)
    ;
}
