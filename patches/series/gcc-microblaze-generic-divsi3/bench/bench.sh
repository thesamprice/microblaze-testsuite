#!/usr/bin/env bash
# bench.sh [FNS...]: instructions and estimated cycles per call, assembly
# vs libgcc's generic C vs the inline instruction, big-endian, under the
# QEMU plugins mbcount3.c and mbhaz.c.  Prints one line per run on stdout;
# table2.py turns that into tables.  Rebuilds both plugins every run, so
# it can be re-run after a plugin fix.
#
# FNS defaults to __divsi3 __modsi3 __udivsi3 __umodsi3; add __mulsi3 for
# the multiply comparison.  Environment, all optional:
#   WORK        the runner's work directory (default: <repo>/work)
#   INSTALL     toolchain and QEMU prefix (default: $WORK/install)
#   QEMU        qemu-system-microblaze with patches/qemu/0001
#               (default: $INSTALL/bin/qemu-system-microblaze)
#   LIBGCC_SRC  a libgcc source tree that still has the assembly
#               (config/microblaze/divsi3.S etc.), i.e. WITHOUT this
#               series; the generic C files come from the same tree
#               (default: $WORK/src/gcc/libgcc)
#   OUT         scratch directory for objects and ELFs
#               (default: $WORK/bench/divsi3)
#   CFGS        configurations to run (default: def bs all alldiv)
#   MULC        the C __mulsi3 to compare with mulsi3.S
#               (default: mulc/c-smaller.c)
set -e
D=$(cd "$(dirname "$0")" && pwd)
REPO=${REPO:-$(cd "$D/../../../.." && pwd)}
WORK=${WORK:-$REPO/work}
INSTALL=${INSTALL:-$WORK/install}
QEMU=${QEMU:-$INSTALL/bin/qemu-system-microblaze}
LIBGCC_SRC=${LIBGCC_SRC:-$WORK/src/gcc/libgcc}
O=${OUT:-$WORK/bench/divsi3}
CFGS=${CFGS:-def bs all alldiv}
MULC=${MULC:-$D/mulc/c-smaller.c}
FNS=${*:-__divsi3 __modsi3 __udivsi3 __umodsi3}
B=$REPO/bench/moddi3
L=$LIBGCC_SRC; M=$L/config/microblaze
CC=$INSTALL/bin/microblaze-elf-gcc; NM=$INSTALL/bin/microblaze-elf-nm
P=$O/libmbcount3.so; H=$O/libmbhaz.so
for f in "$CC" "$QEMU" "$M/divsi3.S" "$L/udivmodsi4.c" "$B/link.ld"; do
  [ -e "$f" ] || { echo "bench.sh: missing $f" >&2; exit 1; }
done
mkdir -p "$O"
PLUGIN_CFLAGS="-O2 -I$INSTALL/include $(pkg-config --cflags glib-2.0)"
case $(uname) in
  Darwin) PLUGIN_LDFLAGS="-bundle -undefined dynamic_lookup" ;;
  *) PLUGIN_LDFLAGS="-shared -fPIC" ;;
esac
# mbcount3.c: instruction classes and five-/three-stage cycle estimates,
# plus a perfect-branch-target-cache bound (cycb, maxb).
# mbhaz.c: five-stage data-hazard stalls.
cc $PLUGIN_CFLAGS $PLUGIN_LDFLAGS -o $P $D/mbcount3.c
cc $PLUGIN_CFLAGS $PLUGIN_LDFLAGS -o $H $D/mbhaz.c
python3 $D/genbench.py $O/bench.h
OPT="-O2 -ffreestanding -fno-stack-protector"
declare -A CF=( [def]="" [bs]="-mxl-barrel-shift -mno-xl-soft-mul"
  [all]="-mcpu=v11.0 -mxl-barrel-shift -mno-xl-soft-mul -mxl-multiply-high -mxl-pattern-compare"
  [alldiv]="-mcpu=v11.0 -mxl-barrel-shift -mno-xl-soft-mul -mxl-multiply-high -mxl-pattern-compare -mno-xl-soft-div"
  [bsonly]="-mxl-barrel-shift"
  [allnomul]="-mcpu=v11.0 -mxl-barrel-shift -mxl-pattern-compare -mno-xl-soft-div" )
$CC -c $B/start.S -o $O/start.o
for cfg in $CFGS; do
  F=${CF[$cfg]}
  $CC $OPT $F -c $L/divmod.c -o $O/divmod-$cfg.o
  $CC $OPT $F -c $L/udivmod.c -o $O/udivmod-$cfg.o
  $CC $OPT $F -c $L/udivmodsi4.c -o $O/udivmodsi4-$cfg.o
  case " $FNS " in *" __mulsi3 "*) $CC $OPT $F -c $MULC -o $O/mulc-$cfg.o ;; esac
  for fn in $FNS; do
    base=${fn#__}
    case $base in udivsi3|umodsi3) SETS="3 4 5" ;; *) SETS="0 1 2" ;; esac
    for set in $SETS; do
      $CC $OPT -I$O -DFN=$fn -DSET=$set -c $D/cbench.c -o $O/b-$fn-$set.o
      $CC $OPT -I$O -DFN=inl_$base -DSET=$set -c $D/cbench.c -o $O/bi-$fn-$set.o
      for v in asm gen inl; do
        case $v in
          asm) [ -f $M/$base.S ] || continue; $CC -c $M/$base.S -o $O/asm-$base.o; objs=$O/asm-$base.o; bo=$O/b-$fn-$set.o; sym=$fn ;;
          gen) case $base in divsi3|modsi3) objs="$O/divmod-$cfg.o $O/udivmodsi4-$cfg.o" ;;
                 udivsi3|umodsi3) objs="$O/udivmod-$cfg.o $O/udivmodsi4-$cfg.o" ;;
                 mulsi3) [ -f $O/mulc-$cfg.o ] || continue; objs=$O/mulc-$cfg.o ;; esac
               bo=$O/b-$fn-$set.o; sym=$fn ;;
          inl) case $base in mulsi3) case "$F" in *-mno-xl-soft-mul*) ;; *) continue ;; esac ;; *) [ $cfg = alldiv ] || continue ;; esac
               case $base in divsi3) op='(int) a / (int) b' ;; modsi3) op='(int) a % (int) b' ;;
                 udivsi3) op='a / b' ;; umodsi3) op='a % b' ;; mulsi3) op='a * b' ;; esac
               $CC $OPT $F -DNAME=inl_$base "-DOP=$op" -c $D/inline.c -o $O/inl-$base-$cfg.o
               objs=$O/inl-$base-$cfg.o; bo=$O/bi-$fn-$set.o; sym=inl_$base ;;
        esac
        elf=$O/$v-$base-$cfg-$set.elf
        $CC -nostdlib -T $B/link.ld $O/start.o $bo $objs -o $elf
        lo=$($NM $elf | awk -v s=$sym '$3==s{print "0x"$1}')
        hi=$($NM $elf | awk '$3=="_etext"{print "0x"$1}')
        r=$(timeout 300 $QEMU -M petalogix-s3adsp1800 -nographic -icount shift=0 \
            -plugin "$P,lo=$lo,hi=$hi" -plugin "$H,lo=$lo,hi=$hi" -d plugin -kernel $elf 2>&1 | tr -d '\r' | grep -E '^MB(COUNT|HAZ)' | sort | tr '\n' ' ' || true)
        echo "$fn $v $cfg $set $r"
      done
    done
  done
done
