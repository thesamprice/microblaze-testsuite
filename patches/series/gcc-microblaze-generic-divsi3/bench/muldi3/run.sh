#!/usr/bin/env bash
# muldi3/run.sh: instructions and estimated cycles per __muldi3 call,
# big-endian, under the mbcount3.c plugin.  Four variants:
#   libgcc-asm    libgcc2.c's __muldi3 as a default libgcc builds it,
#                 calling mulsi3.S
#   libgcc-cmul   the same, calling ../mulc/c-smaller.c's C __mulsi3
#   hwmul-libgcc  __muldi3 built with -mno-xl-soft-mul (a multilib
#                 toolchain's mno-xl-soft-mul libgcc)
#   inline-mulhu  a * b compiled inline with -mno-xl-soft-mul
#                 -mxl-multiply-high
# The two libgcc __muldi3 objects are built with the exact command libgcc's
# own Makefile uses for _muldi3.o, taken from LIBGCC_BUILD with make -n.
#
# Environment, all optional:
#   WORK          the runner's work directory (default: <repo>/work)
#   INSTALL       toolchain and QEMU prefix (default: $WORK/install)
#   LIBGCC_BUILD  a configured microblaze-elf libgcc build directory
#                 (default: $WORK/build/gcc/microblaze-elf/libgcc)
#   LIBGCC_SRC    libgcc source with config/microblaze/mulsi3.S
#                 (default: $WORK/src/gcc/libgcc)
#   OUT           scratch directory (default: $WORK/bench/divsi3/muldi3)
#   PLUGIN        an mbcount3 plugin; built from ../mbcount3.c if unset
set -e
D=$(cd "$(dirname "$0")" && pwd)
REPO=${REPO:-$(cd "$D/../../../../.." && pwd)}
WORK=${WORK:-$REPO/work}
INSTALL=${INSTALL:-$WORK/install}
LB=${LIBGCC_BUILD:-$WORK/build/gcc/microblaze-elf/libgcc}
L=${LIBGCC_SRC:-$WORK/src/gcc/libgcc}
O=${OUT:-$WORK/bench/divsi3/muldi3}; mkdir -p $O
B=$REPO/bench/moddi3
CC=$INSTALL/bin/microblaze-elf-gcc; NM=$INSTALL/bin/microblaze-elf-nm
Q=$INSTALL/bin/qemu-system-microblaze
for f in "$CC" "$Q" "$LB/Makefile" "$L/config/microblaze/mulsi3.S"; do
  [ -e "$f" ] || { echo "run.sh: missing $f" >&2; exit 1; }
done
P=${PLUGIN:-$O/libmbcount3.so}
if [ -z "$PLUGIN" ]; then
  case $(uname) in Darwin) PL="-bundle -undefined dynamic_lookup" ;; *) PL="-shared -fPIC" ;; esac
  cc -O2 -I$INSTALL/include $(pkg-config --cflags glib-2.0) $PL -o $P $D/../mbcount3.c
fi
python3 $D/genb64.py $O/b64.h
# libgcc's own compile command for _muldi3.o, redirected to $O.
src=$(sed -n 's/^srcdir = //p' $LB/Makefile)
cmd=$(make -s -C $LB -n -W $src/libgcc2.c _muldi3.o | grep -- '-DL_muldi3')
[ -n "$cmd" ] || { echo "run.sh: no _muldi3.o command from $LB" >&2; exit 1; }
cmd=$(printf '%s\n' "$cmd" | sed 's/ -MT _muldi3.o -MD -MP -MF _muldi3.dep//')
(cd $LB && eval "$(printf '%s\n' "$cmd" | sed "s| -o [^ ]*| -o $O/muldi3-def.o|")")
(cd $LB && eval "$(printf '%s\n' "$cmd" | sed "s| -o [^ ]*| -o $O/muldi3-hwmul.o|; s| -DL_muldi3 | -DL_muldi3 -mno-xl-soft-mul |")")
OPT="-O2 -ffreestanding -fno-stack-protector"
$CC -c $B/start.S -o $O/start.o
$CC -c $L/config/microblaze/mulsi3.S -o $O/mulsi3-asm.o
$CC $OPT -c $D/../mulc/c-smaller.c -o $O/mulsi3-c.o
$CC $OPT -mno-xl-soft-mul -mxl-multiply-high -mcpu=v11.0 -c $D/inl.c -o $O/inl.o
for set in 0 1 2; do
  for v in libgcc-asm libgcc-cmul hwmul-libgcc inline-mulhu; do
    sym=__muldi3; fn=__muldi3
    case $v in
      libgcc-asm) objs="$O/muldi3-def.o $O/mulsi3-asm.o" ;;
      libgcc-cmul) objs="$O/muldi3-def.o $O/mulsi3-c.o" ;;
      hwmul-libgcc) objs="$O/muldi3-hwmul.o" ;;
      inline-mulhu) objs="$O/inl.o"; sym=inl_muldi3; fn=inl_muldi3 ;;
    esac
    $CC $OPT -I$O -DFN=$fn -DSET=$set -c $D/cb64.c -o $O/b-$fn-$set.o
    elf=$O/$v-$set.elf
    $CC -nostdlib -T $B/link.ld $O/start.o $O/b-$fn-$set.o $objs -o $elf
    lo=$($NM $elf | awk -v s=$sym '$3==s{print "0x"$1}'); hi=$($NM $elf | awk '$3=="_etext"{print "0x"$1}')
    r=$(timeout 300 $Q -M petalogix-s3adsp1800 -nographic -icount shift=0 -plugin "$P,lo=$lo,hi=$hi" -d plugin -kernel $elf 2>&1 | tr -d '\r' | grep '^MBCOUNT' || true)
    echo "__muldi3 $v x $set $r"
  done
done
