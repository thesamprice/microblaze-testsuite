#!/bin/sh
# Reproduce the cycle tables in patches/series/*/0000-cover-letter.txt from
# nothing: every version of libgcc's 64-bit divide and remainder, with and
# without the back-end series, for each set of CPU options.
#
#   bench/moddi3/reproduce.sh [DIR]
#
# DIR (default ./work-reproduce) gets two complete builds from the pinned
# revisions below:
#
#   DIR/series1  binutils, gcc + patches/gcc (the libgcc series), newlib,
#                and QEMU + patches/qemu
#   DIR/carry    the same gcc + patches/series/gcc-microblaze-carry (the
#                back-end series), reusing series1's QEMU
#
# runs bench/moddi3/run.sh with each, and writes DIR/tables.md: mean and
# slowest-call estimated cycles for both pipelines, big-endian.
# DIR/tables-le.md is the same for little-endian.  About 9 GB of disk, and
# 22 minutes on an 8-core Mac, most of it building gcc twice.
# Rerunning skips the builds that are done.
#
# Needs what the top-level Makefile needs to build gcc and QEMU (see
# README.md), plus python3, pkg-config with glib-2.0, and timeout(1).
set -e

# The revisions the published numbers came from.  Override any of them
# from the environment to try another.
: "${BINUTILS_REF:=19c3a4c423b1251c4662d3bec7ff818ce29f57f7}"   # 2026-11-02
: "${GCC_REF:=df809a029f522bc22265ad5ec0eb98f46421030e}"        # 2026-11-07
: "${NEWLIB_REF:=b097f95233d26da7af6887798297d1efadb75370}"     # 2026-10-30
: "${QEMU_VERSION:=10.2.4}"

REPO=$(cd "$(dirname "$0")/../.." && pwd)
DIR=${1:-$PWD/work-reproduce}
mkdir -p "$DIR"
DIR=$(cd "$DIR" && pwd)
MAKE=${MAKE:-make}

for t in python3 pkg-config timeout; do
  command -v $t >/dev/null || { echo "reproduce.sh: needs $t" >&2; exit 1; }
done
pkg-config --exists glib-2.0 ||
  { echo "reproduce.sh: needs glib-2.0 for the QEMU plugin" >&2; exit 1; }

PINS="BINUTILS_REF=$BINUTILS_REF GCC_REF=$GCC_REF NEWLIB_REF=$NEWLIB_REF
      QEMU_VERSION=$QEMU_VERSION"

# build NAME [MAKE-VARIABLE...]: the toolchain in DIR/NAME.
build() {
  w=$DIR/$1; shift
  echo "== building in $w (logs in $w/logs)"
  $MAKE -C "$REPO" WORK="$w" $PINS "$@" toolchain
}

# bench NAME: run.sh with DIR/NAME's toolchain.
bench() {
  w=$DIR/$1
  echo "== benchmarking with $w"
  TOOLBIN=$w/install/bin GCC_SRC=$w/src/gcc GCC_BUILD=$w/build/gcc \
    QEMU=$QEMU OUT=$w/bench sh "$REPO/bench/moddi3/run.sh" \
    > "$w/bench.log"
}

QEMU=$DIR/series1/install/bin/qemu-system-microblaze
build series1
$MAKE -C "$REPO" WORK="$DIR/series1" $PINS qemu
build carry EXTRA_PATCHES_gcc="$REPO/patches/series/gcc-microblaze-carry"
bench series1
bench carry

{
  echo "# 64-bit divide and remainder, estimated cycles per call"
  echo
  echo "Made by bench/moddi3/reproduce.sh, microblaze-testsuite" \
    "$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo '?'), with:"
  echo
  echo '```'
  cat "$DIR/series1/src/"*.rev
  echo '```'
  echo
  echo "Each cell is the mean over 4701 operand pairs, then the slowest"
  echo "single call in brackets.  \"Upstream C\" is libgcc2.c as gcc has it."
  echo "For __moddi3 it is what deleting moddi3.S would give; for the other"
  echo "three it is what libgcc builds today.  \"No-divider code\" is the"
  echo "same with TARGET_HAS_NO_HW_DIVIDE, its shift-and-subtract division."
  echo "\"+ back end\" is compiled by a gcc with the back-end series."
  echo
} > "$DIR/head.md"
status=0
for e in be le; do
  f=$DIR/tables.md; [ $e = le ] && f=$DIR/tables-le.md
  cp "$DIR/head.md" "$f"
  python3 "$REPO/bench/moddi3/table.py" "$DIR/series1/bench/results.txt" \
    "$DIR/carry/bench/results.txt" $e >> "$f" || status=1
done
echo "== wrote $DIR/tables.md and $DIR/tables-le.md"
exit $status
