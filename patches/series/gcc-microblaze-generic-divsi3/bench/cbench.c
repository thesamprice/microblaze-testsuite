/* Call FN on operand set SET of bench.h, then exit QEMU through the
   patches/qemu/0001 test device.  The plugin counts only [FN, _etext),
   where the routine and its helpers are linked.  For the signed routines
   the operands are used as they are; for the unsigned ones the same bit
   patterns are taken as unsigned.  */
#include "bench.h"
#define TESTDEV ((volatile unsigned int *) 0xff000000)
extern unsigned FN (unsigned, unsigned);
volatile unsigned sink;
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
