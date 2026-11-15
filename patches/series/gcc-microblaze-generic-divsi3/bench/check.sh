#!/usr/bin/env bash
# check.sh be|le: correctness of libgcc's generic C __divsi3, __modsi3,
# __udivsi3 and __umodsi3 (divmod.c, udivmod.c, udivmodsi4.c), built in
# five configurations and linked ahead of libgcc, against audit/'s
# boundary and random tables (results computed on the host by
# audit/gen.py).  Prints one summary line per configuration; the full
# output is in $OUT/check-<e>/result-<cfg>.txt.
#
# Environment, all optional:
#   WORK        the runner's work directory (default: <repo>/work)
#   INSTALL     big-endian toolchain and QEMU prefix (default: $WORK/install)
#   INSTALL_LE  little-endian toolchain prefix (default: $WORK/install-le)
#   LIBGCC_SRC  a libgcc source tree; only its generic C is used
#               (default: $WORK/src/gcc/libgcc)
#   OUT         scratch directory (default: $WORK/bench/divsi3)
# Runs through the DejaGnu board's contrib/microblaze-qemu-run, which the
# runner's patched DejaGnu provides in $WORK/src/dejagnu.
set -e
D=$(cd "$(dirname "$0")" && pwd)
REPO=${REPO:-$(cd "$D/../../../.." && pwd)}
WORK=${WORK:-$REPO/work}
INSTALL=${INSTALL:-$WORK/install}
INSTALL_LE=${INSTALL_LE:-$WORK/install-le}
L=${LIBGCC_SRC:-$WORK/src/gcc/libgcc}
A=$D/audit; e=${1:?usage: check.sh be|le}
RUN=$WORK/src/dejagnu/contrib/microblaze-qemu-run
if [ $e = be ]; then CC="$INSTALL/bin/microblaze-elf-gcc"; Q=$INSTALL/bin/qemu-system-microblaze
else CC="$INSTALL_LE/bin/microblazeel-elf-gcc"; Q=$INSTALL/bin/qemu-system-microblazeel; fi
for f in "${CC%% *}" "$Q" "$RUN" "$L/udivmodsi4.c"; do
  [ -e "$f" ] || { echo "check.sh: missing $f" >&2; exit 1; }
done
declare -A CF=( [def]="" [bs]="-mxl-barrel-shift" [mul]="-mno-xl-soft-mul" [pcmp]="-mxl-pattern-compare"
  [all]="-mcpu=v11.0 -mxl-barrel-shift -mno-xl-soft-mul -mxl-multiply-high -mxl-pattern-compare" )
O=${OUT:-$WORK/bench/divsi3}/check-$e; mkdir -p $O
python3 $A/gen.py $O > /dev/null
$CC -O2 -DV=small -mxl-barrel-shift -msmall-divides -c $A/ops.c -o $O/small.o
$CC -O2 -I$O -c $A/test.c -o $O/test.o
for cfg in def bs mul pcmp all; do
  F=${CF[$cfg]}
  for g in divmod udivmod udivmodsi4; do $CC -O2 $F -c $L/$g.c -o $O/$g-$cfg.o; done
  $CC $O/test.o $O/small.o $O/divmod-$cfg.o $O/udivmod-$cfg.o $O/udivmodsi4-$cfg.o -Wl,--no-relax \
    -Wl,--defsym,_TEXT_START_ADDR=0x90000000 -Wl,--defsym,_STACK_SIZE=0x400000 -Wl,--defsym,_HEAP_SIZE=0x400000 -o $O/test-$cfg.elf
  MB_QEMU=$Q MB_TIMEOUT=600 sh $RUN $O/test-$cfg.elf > $O/result-$cfg.txt || true
  echo "$e $cfg: $(grep -E '^libgcc: ' $O/result-$cfg.txt) | $(grep -c MISMATCH $O/result-$cfg.txt) mismatch lines | $(grep 'libgcc div by zero' $O/result-$cfg.txt)"
done
