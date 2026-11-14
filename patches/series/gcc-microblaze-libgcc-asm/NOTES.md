# gcc-microblaze-libgcc-asm

From the audit of libgcc's hand-written MicroBlaze routines that followed
the `moddi3.S` bug. `__divsi3`, `__modsi3`, `__udivsi3`, `__umodsi3`,
`__mulsi3`, `_divsi3_table` and the crt files were correct: about 700,000
boundary and random checks per endian, against results computed on the
host, with 0 mismatches. Two problems, one patch each.

Base: gcc master `df809a029`; both apply there. `on-moddi3/0001` is 0001
rebased for a tree that also has `gcc-microblaze-generic-moddi3`, which
removes the `moddi3.S` line next to it in `t-microblaze`. That copy is
`patches/gcc/0011`, and 0002 is `patches/gcc/0012`.

- 0001 (#77) removes `muldi3_hard.S`. `muldi3_hardproc` has no caller
  (`__muldi3` comes from libgcc2.c) and is wrong on little-endian: it
  reloads 16-bit halves at big-endian offsets, so `muldi3_hardproc (2, 1)`
  is 0. On a 59x59 table of 64-bit values it got 3344 of 3481 products
  wrong on little-endian, none on big-endian. No test: it removes dead
  code.
- 0002 (#78) makes `_stack_overflow_exit`, the target of
  `-mxl-stack-check`'s prologue check, set r5 to 1 and branch to `_exit`.
  It branched to `exit` with r5 unset, so the status was the overflowing
  function's first argument, and atexit handlers and stdio cleanup ran on
  the overflowed stack. New test `others/stack-check-exit.c`
  (`dg-shouldfail`) recurses with 1 MB frames and a first argument of 0.

## Testing

Runner (`make check-gcc`, big-endian, gcc `df809a029` + `patches/gcc/0001`
to `0012`, stock QEMU 10.2.4):

- Without 0002, on the runner's build of 0001-0010: stack-check-exit.c
  fails all 7 execution tests, each `*** EXIT code 0`.
- With both: execute.exp 24536 PASS, microblaze.exp 770 PASS (756 plus the
  new test's 14), 0 FAIL. Its execution tests exit with status 1.
- `nm libgcc.a` no longer lists `muldi3_hardproc`.
- 0002's routine assembles with and without `-fPIC` (`_exit@PLT`) and with
  `-mlittle-endian`.
- Both commits pass `git_check_commit.py`.

Not done: a little-endian run of stack-check-exit.c, and a build of libgcc
for microblaze-linux and microblaze-rtems7 with 0001-0002 (they need
`_exit`, which both C libraries provide).
