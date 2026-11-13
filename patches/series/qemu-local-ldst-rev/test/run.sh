#!/bin/sh
# Build revldst.S for both byte orders and run it under QEMU.
# Usage: run.sh QEMU_BE QEMU_LE
#   (qemu-system-microblaze and qemu-system-microblazeel)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
Q=${1:?qemu-system-microblaze path}
QEL=${2:?qemu-system-microblazeel path}
CC=${CC:-/Volumes/3092583379/src/microblaze-testsuite/work/install/bin/microblaze-elf-gcc}
O=${O:-$(mktemp -d)}
mkdir -p "$O"
rc=0
for e in be le; do
  E=; QQ=$Q
  [ $e = le ] && { E=-mlittle-endian; QQ=$QEL; }
  $CC $E -nostdlib -T "$HERE/link.ld" "$HERE/revldst.S" -o "$O/revldst-$e.elf" || exit 2
  timeout 10 "$QQ" -M petalogix-s3adsp1800 -nographic -kernel "$O/revldst-$e.elf"
  s=$?
  printf '%s: exit status %d (0x%x)\n' "$e" $s $s
  [ $s = 0 ] || rc=1
done
exit $rc
