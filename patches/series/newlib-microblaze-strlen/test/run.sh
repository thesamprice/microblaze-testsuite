#!/bin/sh
# Check and count three strlen implementations, both byte orders, under
# QEMU with -icount and microblaze-testsuite's patches/qemu test device:
#
#   c        newlib's generic word-at-a-time C path in microblaze/strlen.c
#   c-pcmp   the asm-in-C pcmpbf path, before the patch
#   s-pcmp   strlen-pcmp.S, after the patch
#
#   OLD      a newlib tree before the patch
#   NEW      a newlib tree with it
#   TOOLBIN  the directory holding microblaze-elf-gcc
#   QEMU     qemu-system-microblaze; ${QEMU}el is the little-endian one
#   MBCOUNT  optional: bench/moddi3/mbcount.c, for cycle estimates
#   OUT      where to write everything
set -e
: "${OLD:?}" "${NEW:?}" "${TOOLBIN:?}" "${QEMU:?}" "${OUT:?}"
HERE=$(cd "$(dirname "$0")" && pwd)
CC=$TOOLBIN/microblaze-elf-gcc
NM=$TOOLBIN/microblaze-elf-nm
OBJDUMP=$TOOLBIN/microblaze-elf-objdump
MB=newlib/libc/machine/microblaze
# What newlib's build passes for these files, less -g and the include
# paths they do not need.
NLFLAGS="-O2 -fno-builtin -ffreestanding"
PCMP="-mxl-pattern-compare"
mkdir -p "$OUT"

PLUGIN=
if [ -n "$MBCOUNT" ]; then
  PLUGIN=$OUT/libmbcount.so
  QINC=$(dirname "$QEMU")/../include
  case $(uname) in Darwin) SHARED="-bundle -undefined dynamic_lookup" ;;
		   *) SHARED="-shared -fPIC" ;; esac
  cc -O2 $SHARED -I"$QINC" $(pkg-config --cflags glib-2.0) \
    -o "$PLUGIN" "$MBCOUNT"
fi

RES=$OUT/results.txt
: > "$RES"
for e in be le; do
  E=; Q=$QEMU
  [ $e = le ] && { E=-mlittle-endian; Q=${QEMU}el; }
  o=$OUT/$e
  mkdir -p $o
  $CC $E -O2 -ffreestanding -c "$HERE/start.S" -o $o/start.o
  $CC $E -O2 -ffreestanding -fno-builtin \
    -fno-tree-loop-distribute-patterns -c "$HERE/strlen-test.c" -o $o/test.o
  for v in c c-pcmp s-pcmp; do
    case $v in
      c)      $CC $E $NLFLAGS \
		-c $OLD/$MB/strlen.c -o $o/$v.o ;;
      c-pcmp) $CC $E $NLFLAGS $PCMP \
		-c $OLD/$MB/strlen.c -o $o/$v.o ;;
      s-pcmp) $CC $E $NLFLAGS $PCMP -c $NEW/$MB/strlen-pcmp.S -o $o/$v.o ;;
    esac
    # strlen last in .text, so [strlen, _etext) is strlen and nothing else.
    $CC $E -nostdlib -T "$HERE/link.ld" $o/start.o $o/test.o $o/$v.o \
      -o $o/$v.elf
    $OBJDUMP -d --no-show-raw-insn $o/$v.o > $o/$v.dis
    size=$($OBJDUMP -d $o/$v.o | grep -c '^ *[0-9a-f]*:	')
    set +e
    timeout 300 "$Q" -M petalogix-s3adsp1800 -nographic -icount shift=0 \
      -kernel $o/$v.elf > $o/$v.log 2>&1
    st=$?
    set -e
    tr -d '\r' < $o/$v.log | sed "s|^|$v $e status=$st size=$size |" >> "$RES"
    if [ -n "$PLUGIN" ]; then
      lo=$($NM $o/$v.elf | awk '$3=="strlen"{print "0x"$1}')
      hi=$($NM $o/$v.elf | awk '$3=="_etext"{print "0x"$1}')
      timeout 300 "$Q" -M petalogix-s3adsp1800 -nographic -icount shift=0 \
	-plugin "$PLUGIN,lo=$lo,hi=$hi" -d plugin -kernel $o/$v.elf 2>&1 |
	tr -d '\r' | grep '^MBCOUNT' | sed "s|^|$v $e |" >> "$RES"
    fi
    echo "$v $e exit $st"
  done
done
