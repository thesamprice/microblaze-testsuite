#!/bin/sh
# Usage: run.sh QEMU_BE QEMU_LE
# 1. One-instruction programs: each executes INSN and then exits with 7.
#    "halts" means QEMU was still running at the 3 s timeout.
# 2. wake.c: hibernate/sleep/suspend must wait for a timer interrupt.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
Q=${1:?qemu-system-microblaze path}
QEL=${2:?qemu-system-microblazeel path}
CC=${CC:-/Volumes/3092583379/src/microblaze-testsuite/work/install/bin/microblaze-elf-gcc}
O=${O:-$(mktemp -d)}
mkdir -p "$O"
LD1=/Volumes/3092583379/src/microblaze-testsuite/patches/series/qemu-local-ldst-rev/test/link.ld
F="-mcpu=v9.0 -mxl-barrel-shift"
for e in be le; do
  E=; QQ=$Q
  [ $e = le ] && { E=-mlittle-endian; QQ=$QEL; }
  for i in nop "mbar 1" "mbar 2" sleep hibernate suspend "mbar 9" "mbar 17"; do
    f=$O/one-$e-$(echo "$i" | tr -d ' ').elf
    printf '\t.text\n\t.globl _start\n_start:\t%s\n\taddik r3, r0, 7\n\taddik r4, r0, 0xff000000\n\tswi r3, r4, 0\n1:\tbri 1b\n' "$i" > "$O/one.S"
    $CC $E -nostdlib -T "$LD1" "$O/one.S" -o "$f" || exit 2
    timeout 3 "$QQ" -M petalogix-s3adsp1800 -nographic -kernel "$f" 2>/dev/null
    s=$?
    case $s in 7) r="runs on";; 124|137) r="halts";; *) r="exit $s";; esac
    printf '%s %-10s %s\n' $e "$i" "$r"
  done
  for i in hibernate sleep suspend nop; do
    f=$O/wake-$e-$i.elf
    $CC $E $F -O2 -nostdlib -T "$HERE/link.ld" -DINSN="\"$i\"" \
      "$HERE/crt.S" "$HERE/wake.c" -o "$f" || exit 2
    timeout 10 "$QQ" -M petalogix-s3adsp1800 -nographic -kernel "$f"
    printf '%s wake %-10s exit %d\n' $e $i $?
  done
done
