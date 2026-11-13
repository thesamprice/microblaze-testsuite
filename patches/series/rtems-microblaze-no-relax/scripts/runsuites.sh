#!/bin/zsh
# runsuites.sh BUILDDIR OUT suite...   (same harness as rtems-new/runsuite.sh: runtest.sh, -P 4, 120 s)
b=$1; out=$2; shift 2
d=$b/microblaze/petalogix_s3adsp1800/testsuites
for s in "$@"; do ls $d/$s/*.exe; done | /usr/bin/grep -v norun | xargs -P 4 -I{} $(dirname $0)/runtest.sh {} 120 > $out 2>&1
echo done >> $out
