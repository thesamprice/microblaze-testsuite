#!/bin/sh
# Line and branch coverage of libgcc's 64-bit divide and remainder on
# MicroBlaze, with tcgcov (https://github.com/thesamprice/tcgcov), from two
# sources:
#
#   torture  all of gcc.c-torture/execute, through the DejaGnu board, with
#            bench/moddi3/coverage/qemu-cov standing in for QEMU so that
#            every run linking one of the routines is recorded
#   vectors  bench/moddi3's 4701 vectors for each of the four routines,
#            linked against the installed libgcc
#
# then merges each into one LCOV file and annotates the division code in
# libgcc2.c (annotate.py).  "make coverage-moddi3" runs it with:
#
#   TOOLBIN   the directory holding microblaze-elf-gcc
#   GCC_SRC   the gcc tree libgcc was built from, with patches/gcc applied
#   QEMU      qemu-system-microblaze, with patches/qemu/0001's test device
#   TCGCOV    a tcgcov checkout
#   OUT       where to write everything
#   SKIP_TORTURE  set to reuse an earlier torture run's artifacts
#
# The torture run takes about an hour.  Only the default multilib is
# covered: big-endian, no CPU options, which is the libgcc a MicroBlaze
# toolchain installs.
set -e
: "${TOOLBIN:?}" "${GCC_SRC:?}" "${QEMU:?}" "${TCGCOV:?}" "${OUT:?}"
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../../.." && pwd)
BENCH=$HERE/..
CC=$TOOLBIN/microblaze-elf-gcc
export PATH=$TOOLBIN:$PATH
tcgcov () { PYTHONPATH=$TCGCOV python3 -m tcgcov "$@"; }

mkdir -p "$OUT"

# The plugin, built against the QEMU it is loaded into.
mkdir -p "$OUT/plugin"
cp "$TCGCOV"/plugin/*.c "$TCGCOV"/plugin/*.h "$TCGCOV"/plugin/Makefile \
  "$OUT/plugin/"
make -s -C "$OUT/plugin" QEMU_PLUGIN_H="$(dirname "$QEMU")/../include/qemu-plugin.h"
PLUGIN=$(ls "$OUT"/plugin/libtcgcov.so "$OUT"/plugin/libtcgcov.dylib 2>/dev/null | head -1)

# torture
if [ -z "$SKIP_TORTURE" ]; then
  rm -rf "$OUT/torture"
  MBCOV_QEMU=$QEMU MBCOV_PLUGIN=$PLUGIN MBCOV_DIR=$OUT/torture \
  MBCOV_NM=$TOOLBIN/microblaze-elf-nm \
    make -C "$TOP" check-gcc QEMU="$HERE/qemu-cov" > "$OUT/torture.log" 2>&1
fi

# vectors
rm -rf "$OUT/vectors"
mkdir -p "$OUT/vectors"
v=$OUT/vectors
cc -O2 -o "$v/gen" "$BENCH/gen.c"
"$v/gen" > "$v/vectors.h"
$CC -O2 -c "$BENCH/start.S" -o "$v/start.o"
for op in moddi3 umoddi3 divdi3 udivdi3; do
  case $op in moddi3) n=0 ;; umoddi3) n=1 ;; divdi3) n=2 ;; udivdi3) n=3 ;; esac
  $CC -O2 -ffreestanding -I"$v" -DOP=$n -c "$BENCH/bench.c" -o "$v/bench-$op.o"
  $CC -nostdlib -T "$BENCH/link.ld" "$v/start.o" "$v/bench-$op.o" -lgcc \
    -o "$v/$op.elf"
  timeout 120 "$QEMU" -M petalogix-s3adsp1800 -nographic -icount shift=0 \
    -plugin "$PLUGIN,out=$v/$op.cov,elf=$v/$op.elf" -kernel "$v/$op.elf" \
    > "$v/$op.log" 2>&1 || :
  tr -d '\r' < "$v/$op.log" | grep 'BENCH all' || echo "$op: no result"
done

# Per-run LCOV, eight at a time, then one aggregate per source.
for src in torture vectors; do
  rm -rf "$OUT/lcov-$src"
  mkdir -p "$OUT/lcov-$src"
  n=$(ls "$OUT/$src"/*.cov 2>/dev/null | wc -l | tr -d ' ')
  echo "$src: $n runs"
  [ "$n" -gt 0 ] || continue
  export GCC_SRC TCGCOV
  ls "$OUT/$src"/*.cov | xargs -P 8 -I % "$HERE/one-run.sh" % "$OUT/lcov-$src"
  tcgcov merge --out "$OUT/$src.info" --name "$src" "$OUT/lcov-$src"/*.info
done

python3 "$HERE/annotate.py" "$GCC_SRC/libgcc/libgcc2.c" \
  "$OUT/torture.info" "$OUT/vectors.info" > "$OUT/annotated.txt"
cat "$OUT/annotated.txt"
