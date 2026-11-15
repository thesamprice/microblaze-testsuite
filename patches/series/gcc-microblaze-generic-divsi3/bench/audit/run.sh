#!/usr/bin/env bash
# audit/run.sh be|le: the original libgcc audit.  Checks libgcc's own
# routines (the assembly __divsi3, __modsi3, __udivsi3, __umodsi3,
# __mulsi3, and muldi3_hardproc if present), the -msmall-divides table
# and the hardware idiv/mul against gen.py's host-computed tables.
# Environment as for ../check.sh; output in $OUT/audit-<e>/result.txt.
set -e
D=$(cd "$(dirname "$0")" && pwd)
REPO=${REPO:-$(cd "$D/../../../../.." && pwd)}
WORK=${WORK:-$REPO/work}
INSTALL=${INSTALL:-$WORK/install}
INSTALL_LE=${INSTALL_LE:-$WORK/install-le}
e=${1:?usage: run.sh be|le}
if [ "$e" = be ]; then CC=$INSTALL/bin/microblaze-elf-gcc; Q=$INSTALL/bin/qemu-system-microblaze
else CC=$INSTALL_LE/bin/microblazeel-elf-gcc; Q=$INSTALL/bin/qemu-system-microblazeel; fi
O=${OUT:-$WORK/bench/divsi3}/audit-$e; mkdir -p $O
python3 $D/gen.py $O > /dev/null
$CC -O2 -DV=small -mxl-barrel-shift -msmall-divides -c $D/ops.c -o $O/small.o
$CC -O2 -DV=hw -mno-xl-soft-div -mno-xl-soft-mul -c $D/ops.c -o $O/hw.o
$CC -O2 -DWITH_HW -I$O -c $D/test.c -o $O/test.o
$CC $O/test.o $O/small.o $O/hw.o -Wl,--no-relax -Wl,--defsym,_TEXT_START_ADDR=0x90000000 -Wl,--defsym,_STACK_SIZE=0x400000 -Wl,--defsym,_HEAP_SIZE=0x400000 -o $O/test.elf
MB_QEMU=$Q MB_TIMEOUT=600 sh $WORK/src/dejagnu/contrib/microblaze-qemu-run $O/test.elf > $O/result.txt
cat $O/result.txt
