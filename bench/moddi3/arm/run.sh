#!/bin/sh
# Cortex-M0 (armv6-m) instruction counts for libgcc's 64-bit divide and
# remainder, before and after patches/gcc/0001-0002 (the generic libgcc
# patches), for the gcc-microblaze-generic-moddi3 cover letter.  See
# REPORT.md, "On a real no-divider target: Cortex-M0".
#
#   ARM_BUILD  a gcc build tree configured --target=arm-none-eabi
#              --with-cpu=cortex-m0 --with-mode=thumb --disable-multilib,
#              with all-gcc and all-target-libgcc built, from gcc
#              df809a029.  Its libgcc gives the compile flags; its
#              srcdir gives the "before" libgcc2.c.
#   ARM_CC     the compiler for the routines; default: arm-none-eabi-gcc
#              14.2 in the mb-armgcc142 image (docker build -t
#              mb-armgcc142 bench/moddi3/arm), run with the work tree
#              mounted at the same path.
#   QEMU       qemu-system-arm with plugin support (QEMU 9 or later)
#   OUT        where to write everything
#
# For each routine and variant: build, link for the micro:bit, run under
# armcount.c, check every result, and write one count per call.
# summary.py prints the table.  Variants:
#   before   libgcc2.c from ARM_BUILD's srcdir
#   after    the same with patches/gcc/0001 and 0002
#   forced   "after" with LIBGCC2_MOD_WITHOUT_QUOTIENT defined, as an
#            earlier version of patch 2 had it on every no-divider target
#            (__moddi3 and __umoddi3 only)
# and the operand sets: "signed" for the signed routines; "unsigned"
# (gen unsigned) for the unsigned ones, plus "signed" for them too, which
# is what the figures before the 2026-11-14 bench fix used.
set -e
: "${ARM_BUILD:?}" "${QEMU:?}" "${OUT:?}"
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
LGB=$ARM_BUILD/arm-none-eabi/libgcc
SRCDIR=$(sed -n 's/^srcdir = //p' "$LGB/Makefile")
SRCDIR=$(cd "$LGB/$SRCDIR" 2>/dev/null && pwd || echo "$SRCDIR")
[ -f "$SRCDIR/libgcc2.c" ] || { echo "no libgcc2.c in $SRCDIR"; exit 1; }
if [ -z "$ARM_CC" ]; then
  W=$(cd "$REPO/.." && pwd)
  ARM_CC="docker run --rm -v $W:$W -w $OUT mb-armgcc142 arm-none-eabi-gcc"
fi
$ARM_CC --version | head -1 > "$OUT/compiler.txt"

# libgcc's own compile commands (mkcmd.py), with the CPU the build
# compiler was configured for spelled out, since another driver has to be
# told.
CPU="-mcpu=cortex-m0 -mthumb -mfloat-abi=soft"

# The "after" libgcc2.c.
rm -rf "$OUT/after" && mkdir -p "$OUT/after/libgcc"
cp "$SRCDIR/libgcc2.c" "$OUT/after/libgcc/libgcc2.c"
for p in "$REPO"/patches/gcc/0001-*.patch "$REPO"/patches/gcc/0002-*.patch; do
  (cd "$OUT/after" && GIT_CEILING_DIRECTORIES="$OUT" git apply --include=libgcc/libgcc2.c "$p")
done
AFTER=$OUT/after/libgcc/libgcc2.c
cmp -s "$SRCDIR/libgcc2.c" "$AFTER" && { echo "patches did not apply"; exit 1; }

# The objects, in one container run: every routine the six entry points
# reach, each from the file libgcc builds it from.  On Thumb-1,
# __aeabi_ldivmod, __aeabi_uldivmod, __clzsi2 and __clzdi2 come from
# lib1funcs.S (built from libgcc2.c, __clzsi2 would call itself), the
# AEABI helpers from bpabi.c and the rest from libgcc2.c; __aeabi_lmul
# is libgcc2.c's __muldi3.  Only the libgcc2.c objects differ between
# the variants.
L2="_divdi3 _udivdi3 _moddi3 _umoddi3 _udivmoddi4 _muldi3"
OTHER="_aeabi_ldivmod _aeabi_uldivmod _clzsi2 _clzdi2 bpabi"
{
  echo "set -e"
  for o in $L2 $OTHER; do
    python3 "$HERE/mkcmd.py" "$LGB" $o.o > "$OUT/cmd-$o.txt"
  done
  for v in before after forced; do
    mkdir -p "$OUT/obj-$v"
    case $v in forced) extra=-DLIBGCC2_MOD_WITHOUT_QUOTIENT=1 ;; *) extra= ;; esac
    for o in $L2; do
      flags=$(cut -f1 "$OUT/cmd-$o.txt"); src=$(cut -f2 "$OUT/cmd-$o.txt")
      [ $v = before ] || src=$AFTER
      echo "arm-none-eabi-gcc $CPU $flags $extra -c $src -o $OUT/obj-$v/lg-$o.o"
    done
  done
  for o in $OTHER; do
    flags=$(cut -f1 "$OUT/cmd-$o.txt"); src=$(cut -f2 "$OUT/cmd-$o.txt")
    echo "arm-none-eabi-gcc $CPU $flags -c $src -o $OUT/lg-$o.o"
  done
  echo "arm-none-eabi-gcc -O2 $CPU -ffreestanding -fno-tree-loop-distribute-patterns -c $HERE/rt.c -o $OUT/rt.o"
} > "$OUT/compile.sh"
cp "$OUT/compile.sh" "$OUT/compile-commands.txt"
${ARM_CC%arm-none-eabi-gcc} sh "$OUT/compile.sh"

# The host programs and the plugin.
cc -O2 -o "$OUT/gen" "$REPO/bench/moddi3/gen.c"
mkdir -p "$OUT/vs" "$OUT/vu"
"$OUT/gen" > "$OUT/vs/vectors.h" 2>/dev/null
"$OUT/gen" unsigned > "$OUT/vu/vectors.h" 2>/dev/null
cc -O2 -I"$OUT/vs" -o "$OUT/mkvec-s" "$HERE/mkvec.c"
cc -O2 -I"$OUT/vu" -o "$OUT/mkvec-u" "$HERE/mkvec.c"
QINC=$(dirname "$(command -v "$QEMU")")/../include
cc -O2 -shared -fPIC -undefined dynamic_lookup -I"$QINC" \
  $(pkg-config --cflags glib-2.0) -o "$OUT/libarmcount.so" "$HERE/armcount.c"

: > "$OUT/results.txt"
for op in 0 1 2 3 4 5; do
  case $op in
    0) fn=__moddi3; sets=s; vs="before after forced" ;;
    1) fn=__umoddi3; sets="u s"; vs="before after forced" ;;
    2) fn=__divdi3; sets=s; vs="before after" ;;
    3) fn=__udivdi3; sets="u s"; vs="before after" ;;
    4) fn=__aeabi_ldivmod; sets=s; vs="before after" ;;
    5) fn=__aeabi_uldivmod; sets="u s"; vs="before after" ;;
  esac
  for set in $sets; do
    d=$OUT/op$op-$set; mkdir -p "$d"
    "$OUT/mkvec-$set" $op > "$d/cvec.h" 2> "$d/classes.txt"
    $ARM_CC -O2 -mcpu=cortex-m0 -mthumb -ffreestanding -DOP=$op \
      -I"$d" -c "$HERE/bench.c" -o "$d/bench.o"
    for v in $vs; do
      e=$d/$v.elf
      $ARM_CC -mcpu=cortex-m0 -mthumb -nostartfiles -nostdlib \
	-T "$HERE/link.ld" "$d/bench.o" "$OUT/rt.o" "$OUT"/obj-$v/lg-*.o \
	"$OUT"/lg-*.o -lgcc -o "$e"
      ${ARM_CC%gcc}nm "$e" > "$d/$v.nm"
      ${ARM_CC%gcc}objdump -d -j .lg "$e" > "$d/$v.dis"
      lo=0x$(awk '$3=="__lg_lo"{print $1}' "$d/$v.nm")
      hi=0x$(awk '$3=="__lg_hi"{print $1}' "$d/$v.nm")
      # Every call out of the counted range would go uncounted: refuse.
      python3 "$HERE/checkcalls.py" "$d/$v.dis" "$lo" "$hi"
      st=0
      timeout 600 "$QEMU" -M microbit -nographic \
	-semihosting-config enable=on,target=native \
	-plugin "$OUT/libarmcount.so,lo=$lo,hi=$hi,out=$d/$v.counts" \
	-d plugin -kernel "$e" > "$d/$v.log" 2>&1 || st=$?
      echo "$fn $v $set status=$st $(grep -h BENCH "$d/$v.log" | tr -d '\r') $(grep -h ARMCOUNT "$d/$v.log")" \
	| tee -a "$OUT/results.txt"
    done
  done
done
python3 "$HERE/summary.py" "$OUT"
