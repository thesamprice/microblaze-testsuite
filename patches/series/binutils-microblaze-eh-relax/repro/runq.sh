#!/bin/sh
# usage: runq.sh exe [timeout] [extra qemu args]
exe=$1; t=${2:-20}; shift; shift
exec timeout $t /Volumes/3092583379/src/microblaze-testsuite/work/install/bin/qemu-system-microblazeel -nographic -no-reboot -net none -serial mon:stdio -machine petalogix-s3adsp1800,endianness=little -cpu microblaze-cpu -global microblaze-cpu.ill-opcode-exception=true -global microblaze-cpu.opcode-0x0-illegal=true -m 256M -kernel "$exe" "$@"
