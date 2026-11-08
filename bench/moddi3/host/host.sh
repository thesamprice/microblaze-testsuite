#!/bin/sh
# What patches/gcc does to libgcc2.c on a host machine, before and after.
# Run on Linux with gcc and git; "make bench-moddi3-host" runs it in
# Docker, natively and for linux/amd64.
#
#   GCC_SRC  the gcc tree: HEAD gives the upstream libgcc2.c, the working
#            tree, with patches/gcc applied, the patched one
#   OUT      where to write everything
#
# 1. Identity.  Every change in the series is under TARGET_HAS_NO_HW_DIVIDE,
#    which no x86 or AArch64 configuration defines, so a host libgcc should
#    not change.  Each double-word routine is compiled from both versions
#    of libgcc2.c, as libgcc would, and the disassembly compared: with
#    32-bit words (the __moddi3 family, as on a 32-bit target) and with the
#    host's 64-bit words (the __modti3 family, what a host libgcc has).
#
# 2. The new code on a host CPU.  With 32-bit words and
#    TARGET_HAS_NO_HW_DIVIDE forced on, both versions are checked against
#    the 4701 vectors and timed, next to the upstream default path (long
#    division) and the compiler's own 64-bit divide instruction.
#
# libgcc2.c is compiled outside a gcc build tree, so the headers that tree
# would generate are stubbed, and the word size is given explicitly.
set -e
: "${GCC_SRC:?}" "${OUT:?}"
HERE=$(cd "$(dirname "$0")/.." && pwd)
ARCH=$(uname -m)
mkdir -p "$OUT/up" "$OUT/pa" "$OUT/stub" "$OUT/obj"

git -c safe.directory='*' -C "$GCC_SRC" show HEAD:libgcc/libgcc2.c \
  > "$OUT/up/libgcc2.c"
cp "$GCC_SRC/libgcc/libgcc2.c" "$OUT/pa/libgcc2.c"
if cmp -s "$OUT/up/libgcc2.c" "$OUT/pa/libgcc2.c"; then
  echo "host.sh: GCC_SRC has no change to libgcc2.c; apply patches/gcc" >&2
  exit 1
fi
for h in tconfig.h coretypes.h tm.h libgcc_tm.h; do
  echo '/* Stub: libgcc2.c built outside a gcc build tree.  */' \
    > "$OUT/stub/$h"
done
printf '#include <stddef.h>\n#include <limits.h>\n' > "$OUT/stub/tsystem.h"

cc -O2 -o "$OUT/gen" "$HERE/gen.c"
"$OUT/gen" > "$OUT/vectors.h"

L2="-O2 -fbuilding-libgcc -DIN_LIBGCC2 -Dinhibit_libc -fno-stack-protector
    -I$OUT/stub -I$GCC_SRC/libgcc -I$GCC_SRC/include"
L2=$(echo $L2)
RESULTS=$OUT/results.txt
: > "$RESULTS"
o=$OUT/obj

# 1. Identity.
for w in 4 8; do
  W="-DLIBGCC2_UNITS_PER_WORD=$w -DMIN_UNITS_PER_WORD=$w"
  for L in moddi3 umoddi3 divdi3 udivdi3 divmoddi4 udivmoddi4; do
    for s in up pa; do
      gcc $L2 $W -DL_$L -c "$OUT/$s/libgcc2.c" -o $o/id-$w-$L-$s.o
      objdump -d $o/id-$w-$L-$s.o | sed '1,/file format/d' > $o/id-$w-$L-$s.s
    done
    sym=$(nm $o/id-$w-$L-up.o | awk '$2=="T"{print $3}' | tr '\n' ' ')
    if cmp -s $o/id-$w-$L-up.s $o/id-$w-$L-pa.s; then r=identical
    else r=DIFFERENT; fi
    echo "$ARCH identity word=$((w * 8))bit L_$L [$sym] $r" | tee -a "$RESULTS"
  done
done

# 2. TARGET_HAS_NO_HW_DIVIDE forced on, 32-bit words.
W="-DLIBGCC2_UNITS_PER_WORD=4 -DMIN_UNITS_PER_WORD=4"
gcc $L2 $W -DL_clz -c "$OUT/up/libgcc2.c" -o $o/clz.o
for op in moddi3 umoddi3 divdi3 udivdi3; do
  case $op in moddi3) n=0 ;; umoddi3) n=1 ;; divdi3) n=2 ;; udivdi3) n=3 ;; esac
  for v in native default nohw-up nohw-pa; do
    case $v in
      native)  objs= ; d=-DNATIVE ;;
      default) gcc $L2 $W -DL_$op -c "$OUT/up/libgcc2.c" -o $o/$op-$v.o
	       objs="$o/$op-$v.o $o/clz.o"; d= ;;
      nohw-up) gcc $L2 $W -DTARGET_HAS_NO_HW_DIVIDE -DL_$op \
		 -c "$OUT/up/libgcc2.c" -o $o/$op-$v.o
	       objs=$o/$op-$v.o; d= ;;
      nohw-pa) gcc $L2 $W -DTARGET_HAS_NO_HW_DIVIDE -DL_$op \
		 -c "$OUT/pa/libgcc2.c" -o $o/$op-$v.o
	       objs=$o/$op-$v.o; d= ;;
    esac
    gcc -O2 -I"$OUT" -DOP=$n $d "$HERE/host/hostbench.c" $objs -o $o/$op-$v
    printf '%s %s %-8s ' "$ARCH" "$op" "$v" | tee -a "$RESULTS"
    $o/$op-$v | tee -a "$RESULTS"
  done
done
