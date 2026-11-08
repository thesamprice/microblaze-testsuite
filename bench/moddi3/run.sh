#!/bin/sh
# Build the 64-bit divide and remainder variants for both byte orders, run
# each under QEMU with -icount, and collect the instruction counts, the
# instruction classes, mbcount.c's cycle estimates, the static sizes and
# the disassembly.  summary.py turns results.txt into per-call figures.
# "make bench-moddi3" runs this with:
#
#   TOOLBIN    the directory holding microblaze-elf-gcc
#   GCC_SRC    the gcc tree.  Its HEAD gives the upstream libgcc2.c and
#              moddi3.S; its working tree, with patches/gcc applied, gives
#              the patched ones.
#   GCC_BUILD  the gcc build tree, for the headers libgcc2.c needs
#   QEMU       qemu-system-microblaze, with patches/qemu/0001's test device
#   OUT        where to write everything
#
# The variants of __moddi3:
#
#   stock         moddi3.S before gcc 3a721dc02, from moddi3-stock.S here.
#                 Wrong for most inputs and hangs on some; correctness only,
#                 and only with "def".
#   asm           moddi3.S as upstream has it: the assembly fix
#   asm-new       moddi3-new.S here: moddi3.S with what the C does better
#   generic       upstream libgcc2.c's __moddi3: what deleting moddi3.S
#                 would give
#   generic-nohw  upstream libgcc2.c with TARGET_HAS_NO_HW_DIVIDE forced:
#                 its shift-and-subtract __udivmoddi4
#   patched       libgcc2.c and microblaze-lib.h with patches/gcc applied
#
# and, with "def" and "full" only, the experiments behind REPORT.md:
#
#   rem           moddi3-rem.c, portable C keeping only the remainder
#   rem-fused     the same with moddi3.S's subtract-and-test-sign
#   rem-left      the same again, but shifting the remainder left past a
#                 fixed divisor, as moddi3.S does
#
# __umoddi3, __divdi3 and __udivdi3 have generic, generic-nohw and patched.
#
# The sets of CPU options:
#
#   def    none: what libgcc is built with, -mcpu=v4.00.a, soft multiply
#          and divide, no barrel shifter
#   mlib   -mxl-barrel-shift -mno-xl-soft-mul -mxl-multiply-high, the most
#          capable multilib gcc/config/microblaze/t-microblaze ships
#   nodiv  every option QEMU's CPU implements except the divider
#   full   every option QEMU's CPU implements
set -e
: "${TOOLBIN:?}" "${GCC_SRC:?}" "${GCC_BUILD:?}" "${QEMU:?}" "${OUT:?}"
HERE=$(cd "$(dirname "$0")" && pwd)
CC=$TOOLBIN/microblaze-elf-gcc
AR=$TOOLBIN/microblaze-elf-ar
NM=$TOOLBIN/microblaze-elf-nm
OBJDUMP=$TOOLBIN/microblaze-elf-objdump

MLIB="-mxl-barrel-shift -mno-xl-soft-mul -mxl-multiply-high"
NODIV="-mcpu=v11.00.a $MLIB -mxl-pattern-compare -mxl-reorder"
FULL="$NODIV -mno-xl-soft-div"
OPT="-O2 -ffreestanding -fno-stack-protector"
LIBGCC_SRC=$GCC_SRC/libgcc
MBLIB=$LIBGCC_SRC/config/microblaze
# What libgcc's Makefile passes to libgcc2.c, less -g and the warnings.
# The build tree's libgcc_tm.h is shadowed: each variant gets its own.
L2="-DIN_GCC -DIN_LIBGCC2 -DCROSS_DIRECTORY_STRUCTURE -fbuilding-libgcc
    -Dinhibit_libc -fvisibility=hidden -DHIDE_EXPORTS
    -I$GCC_BUILD/microblaze-elf/libgcc -I$GCC_BUILD/gcc
    -I$LIBGCC_SRC -I$GCC_SRC/gcc -I$GCC_SRC/include"
L2=$(echo $L2)

mkdir -p "$OUT/obj" "$OUT/dis" "$OUT/log" "$OUT/src" \
  "$OUT/tm/upstream" "$OUT/tm/patched"

# Upstream sources from HEAD, whatever the working tree has done to them.
git -C "$GCC_SRC" show HEAD:libgcc/libgcc2.c > "$OUT/src/libgcc2.c"
git -C "$GCC_SRC" show HEAD:libgcc/config/microblaze/moddi3.S \
  > "$OUT/src/moddi3.S"
printf '#ifndef LIBGCC_TM_H\n#define LIBGCC_TM_H\n#endif\n' \
  > "$OUT/tm/upstream/libgcc_tm.h"
PATCHED=
if [ -f "$MBLIB/microblaze-lib.h" ]; then
  PATCHED=patched
  printf '#ifndef LIBGCC_TM_H\n#define LIBGCC_TM_H\n#include "%s"\n#endif\n' \
    "$MBLIB/microblaze-lib.h" > "$OUT/tm/patched/libgcc_tm.h"
fi
UP="-I$OUT/tm/upstream $L2"
PA="-I$OUT/tm/patched $L2"

# The instruction-class counter.  QEMU's own headers are installed beside
# the binary; glib comes from pkg-config.
PLUGIN=$OUT/libmbcount.so
QINC=$(dirname "$QEMU")/../include
case $(uname) in Darwin) SHARED="-bundle -undefined dynamic_lookup" ;;
		 *) SHARED="-shared -fPIC" ;; esac
cc -O2 $SHARED -I"$QINC" $(pkg-config --cflags glib-2.0) \
  -o "$PLUGIN" "$HERE/mbcount.c"

cc -O2 -o "$OUT/gen" "$HERE/gen.c"
"$OUT/gen" > "$OUT/vectors.h"
RESULTS=$OUT/results.txt
: > "$RESULTS"

for e in be le; do
  E=; Q=$QEMU
  [ $e = le ] && { E=-mlittle-endian; Q=${QEMU}el; }
  o=$OUT/obj/$e
  mkdir -p $o
  $CC $E $OPT -c "$HERE/start.S" -o $o/start.o
  for op in moddi3 umoddi3 divdi3 udivdi3; do
    case $op in moddi3) n=0 ;; umoddi3) n=1 ;; divdi3) n=2 ;; udivdi3) n=3 ;; esac
    $CC $E $OPT $FULL -I"$OUT" -DOP=$n -c "$HERE/bench.c" -o $o/bench-$op.o
  done

  for f in def mlib nodiv full; do
    case $f in def) F= ;; mlib) F=$MLIB ;; nodiv) F=$NODIV ;; full) F=$FULL ;; esac
    # The libgcc routines the C variants can call: 32-bit divide and
    # multiply, and the leading-zero count with its table.
    for s in udivsi3 umodsi3 mulsi3; do
      $CC $E $OPT $F -c $MBLIB/$s.S -o $o/h-$f-$s.o
    done
    for s in clz clzdi2; do
      $CC $E $OPT $F $UP -DL_$s -c "$OUT/src/libgcc2.c" -o $o/h-$f-$s.o
    done
    rm -f $o/help-$f.a
    $AR rc $o/help-$f.a $o/h-$f-*.o

    for op in moddi3 umoddi3 divdi3 udivdi3; do
      case $op in
	moddi3)
	  V="asm asm-new generic generic-nohw $PATCHED"
	  [ $f = def ] && V="stock $V"
	  case $f in def|full) V="$V rem rem-fused rem-left" ;; esac ;;
	*) V="generic generic-nohw $PATCHED" ;;
      esac
      for v in $V; do
	case $v in
	  stock)        src=$HERE/moddi3-stock.S; d= ;;
	  asm)          src=$OUT/src/moddi3.S; d= ;;
	  asm-new)      src=$HERE/moddi3-new.S; d= ;;
	  generic)      src=$OUT/src/libgcc2.c; d="$UP -DL_$op" ;;
	  patched)      src=$LIBGCC_SRC/libgcc2.c; d="$PA -DL_$op" ;;
	  generic-nohw) src=$OUT/src/libgcc2.c
			d="$UP -DL_$op -DTARGET_HAS_NO_HW_DIVIDE" ;;
	  rem)          src=$HERE/moddi3-rem.c; d= ;;
	  rem-fused)    src=$HERE/moddi3-rem.c; d=-DFUSED ;;
	  rem-left)     src=$HERE/moddi3-rem.c; d=-DLEFT ;;
	esac
	n=$op-$v-$f-$e
	tag="$op $v $f $e"
	$CC $E $OPT $F $d -c $src -o $o/$op-$v-$f.o
	$CC $E -nostdlib -T "$HERE/link.ld" $o/start.o $o/bench-$op.o \
	  $o/$op-$v-$f.o $o/help-$f.a -o $o/$n.elf
	$OBJDUMP -d --no-show-raw-insn $o/$n.elf > "$OUT/dis/$n.s"
	# Static size of the routine, and the libgcc routines it calls.
	size=$($OBJDUMP -d $o/$op-$v-$f.o | grep -c '^ *[0-9a-f]*:	')
	helpers=$($NM -u $o/$op-$v-$f.o | awk '{print $2}' |
		  tr '\n' ' ' | sed 's/ $//')
	set +e
	timeout 60 "$Q" -M petalogix-s3adsp1800 -nographic -icount shift=0 \
	  -kernel $o/$n.elf > "$OUT/log/$n.log" 2>&1
	status=$?
	set -e
	lines=$(tr -d '\r' < "$OUT/log/$n.log" | grep '^BENCH [a-z/]* n=' || :)
	if [ -n "$lines" ]; then
	  echo "$lines" |
	    sed "s|^BENCH |$tag status=$status size=$size helpers=[$helpers] |"
	  # Again under the plugin, for the instruction classes: from the
	  # routine to the end of .text, which is it and its helpers.
	  lo=$($NM $o/$n.elf | awk -v s=__$op '$3==s{print "0x"$1}')
	  hi=$($NM $o/$n.elf | awk '$3=="_etext"{print "0x"$1}')
	  timeout 120 "$Q" -M petalogix-s3adsp1800 -nographic -icount shift=0 \
	    -plugin "$PLUGIN,lo=$lo,hi=$hi" -d plugin -kernel $o/$n.elf 2>&1 |
	    tr -d '\r' | grep '^MBCOUNT' | sed "s|^MBCOUNT|$tag classes|"
	else
	  echo "$tag status=$status size=$size helpers=[$helpers] no result"
	fi >> "$RESULTS"
	printf '%-8s %-13s %-5s %s  exit %s\n' $op $v $f $e $status
      done
    done
  done
done
