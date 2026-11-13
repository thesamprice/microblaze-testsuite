#!/bin/sh
# Usage: run.sh QEMU_BE QEMU_LE
# Runs timer.c with -icount shift=0 (deterministic) and without it.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
Q=${1:?qemu-system-microblaze path}
QEL=${2:?qemu-system-microblazeel path}
CC=${CC:-/Volumes/3092583379/src/microblaze-testsuite/work/install/bin/microblaze-elf-gcc}
O=${O:-$(mktemp -d)}
mkdir -p "$O"
F="-mcpu=v9.0 -O2"
for e in be le; do
  E=; QQ=$Q
  [ $e = le ] && { E=-mlittle-endian; QQ=$QEL; }
  $CC $E $F -nostdlib -T "$HERE/link.ld" "$HERE/crt.S" "$HERE/timer.c" -o "$O/timer-$e.elf" || exit 2
  for ic in "-icount shift=0" ""; do
    timeout 60 "$QQ" -M petalogix-s3adsp1800 -display none -serial stdio \
      -monitor none ${ic} -kernel "$O/timer-$e.elf" > "$O/out" < /dev/null
    s=$?
    echo "== $e ${ic:-no icount}: exit $s"
    cat "$O/out"
  done
done
