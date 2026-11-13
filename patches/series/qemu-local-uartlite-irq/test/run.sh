#!/bin/sh
# Usage: run.sh QEMU_BE QEMU_LE
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
Q=${1:?qemu-system-microblaze path}
QEL=${2:?qemu-system-microblazeel path}
CC=${CC:-/Volumes/3092583379/src/microblaze-testsuite/work/install/bin/microblaze-elf-gcc}
O=${O:-$(mktemp -d)}
mkdir -p "$O"
F="-mcpu=v9.0 -O2"
rc=0
for e in be le; do
  E=; QQ=$Q
  [ $e = le ] && { E=-mlittle-endian; QQ=$QEL; }
  $CC $E $F -nostdlib -T "$HERE/link.ld" "$HERE/crt.S" "$HERE/uart.c" -o "$O/uart-$e.elf" || exit 2
  # Send "xy" after the transmit checks; hold stdin open after it.
  { sleep 1; printf xy; sleep 3; } | timeout 20 "$QQ" -M petalogix-s3adsp1800 \
    -display none -serial stdio -monitor none -kernel "$O/uart-$e.elf" > "$O/uart-$e.out"
  s=$?
  printf 'uart %s: exit status %d, serial output "%s"\n' $e $s "$(tr '\n' '|' < "$O/uart-$e.out")"
  [ $s = 0 ] || rc=1
done
exit $rc
