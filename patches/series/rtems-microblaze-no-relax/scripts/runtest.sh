#!/bin/zsh
# runtest.sh EXE [timeout]  -> prints PASS/FAIL/TIMEOUT name; log in $EXE.log
exe=$1; to=${2:-60}
Q=/Volumes/3092583379/src/microblaze-testsuite/work/build/qemu/qemu-system-microblazeel-unsigned
log=${exe%.exe}.qemu.log
rm -f $log
timeout $to $Q -M petalogix-s3adsp1800 -m 256 -display none -serial file:$log -monitor none -kernel $exe -no-reboot >/dev/null 2>&1 &
pid=$!
for i in $(seq 1 $((to*5))); do
  if /usr/bin/grep -q "RTEMS shutdown\|\*\*\* END OF TEST\|fatal\|FATAL" $log 2>/dev/null; then sleep 0.3; break; fi
  kill -0 $pid 2>/dev/null || break
  sleep 0.2
done
kill $pid 2>/dev/null; wait $pid 2>/dev/null
n=$(basename $exe .exe)
if /usr/bin/grep -q "\*\*\* END OF TEST" $log; then echo "PASS $n"
elif /usr/bin/grep -q "RTEMS shutdown" $log; then echo "FAIL $n"
else echo "TIMEOUT $n"; fi
