#!/bin/sh
# usage: build-cdtest.sh <bspbuild-dir> <out.exe> [extra link flags...]
# Env: BEXTRA (e.g. -B<dir with as/ld>), TOOLBIN.
set -e
R=/Volumes/3092583379/src/microblaze-testsuite/work
S=$R/src/rtems-new-main
B=$1; out=$2; shift 2
T=${TOOLBIN:-$R/build/rtems-new/rsb/install/bin}/microblaze-rtems7
BB=$B/microblaze/petalogix_s3adsp1800
I="-I$BB/bsps/include -I$BB/cpukit/include -I$S/cpukit/include -I$S/cpukit/contrib/include -I$S/cpukit/score/cpu/microblaze/include -I$S/bsps/include -I$S/bsps/microblaze/include -I$S/bsps/microblaze/microblaze_fpga/include -I$S/testsuites/support/include"
FL="-mlittle-endian -mno-xl-soft-div -mno-xl-soft-mul"
C=$S/testsuites/samples/cdtest
o=${out%.exe}
$T-g++ $BEXTRA $FL -O2 -g $I -c $C/main.cc -o $o.main.o
$T-gcc $BEXTRA $FL -O2 -g -std=gnu2x $I -c $C/init.c -o $o.init.o
$T-g++ $BEXTRA $FL -qrtems -Wl,-EL -Wl,--gc-sections -B$BB -L$BB -L$S/bsps/microblaze/shared/start -L$S/bsps/microblaze/microblaze_fpga/start $o.main.o $o.init.o -lrtemstest -o $out "$@"
