#!/bin/sh
# usage: build.sh <bspbuild-dir> <out.exe> [extra link flags...]
set -e
R=/Volumes/3092583379/src/microblaze-testsuite/work
S=$R/src/rtems-new-main
B=$1; out=$2; shift 2
T=${TOOLBIN:-$R/build/rtems-new/rsb/install/bin}/microblaze-rtems7
BB=$B/microblaze/petalogix_s3adsp1800
I="-I$BB/bsps/include -I$BB/cpukit/include -I$S/cpukit/include -I$S/cpukit/contrib/include -I$S/cpukit/score/cpu/microblaze/include -I$S/bsps/include -I$S/bsps/microblaze/include -I$S/bsps/microblaze/microblaze_fpga/include"
FL="-mlittle-endian -mno-xl-soft-div -mno-xl-soft-mul"
D=$(dirname $0)
[ -n "$ASM" ] && $T-g++ $BEXTRA $FL $CXXEXTRA -O2 $I -S $D/eh.cc -o ${out%.exe}.s; $T-g++ $BEXTRA $FL $CXXEXTRA -O2 -g $I -c $D/eh.cc -o ${out%.exe}.o
$T-g++ $BEXTRA $FL -qrtems -Wl,-EL -Wl,--gc-sections -B$BB -L$BB -L$S/bsps/microblaze/shared/start -L$S/bsps/microblaze/microblaze_fpga/start ${out%.exe}.o -o $out "$@"
