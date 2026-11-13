#!/bin/sh
# Build fpu.S and fpu-c.c for both byte orders and run them under QEMU.
# Usage: run.sh QEMU_BE QEMU_LE
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
Q=${1:?qemu-system-microblaze path}
QEL=${2:?qemu-system-microblazeel path}
CC=${CC:-/Volumes/3092583379/src/microblaze-testsuite/work/install/bin/microblaze-elf-gcc}
O=${O:-$(mktemp -d)}
mkdir -p "$O"
F="-mcpu=v9.0 -mhard-float -mxl-float-convert"
rc=0
for e in be le; do
  E=; QQ=$Q
  [ $e = le ] && { E=-mlittle-endian; QQ=$QEL; }
  $CC $E $F -nostdlib -T "$HERE/link.ld" "$HERE/fpu.S" -o "$O/fpu-$e.elf" || exit 2
  $CC $E $F -O2 -nostdlib -T "$HERE/link.ld" "$HERE/start.S" "$HERE/fpu-c.c" -o "$O/fpu-c-$e.elf" || exit 2
  for t in fpu fpu-c; do
    timeout 10 "$QQ" -M petalogix-s3adsp1800 -nographic -kernel "$O/$t-$e.elf"
    s=$?
    printf '%s %s: exit status %d\n' $t $e $s
    [ $s = 0 ] || rc=1
  done
done
exit $rc
