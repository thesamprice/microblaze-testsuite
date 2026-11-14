# gcc-microblaze-zero-fails

Four patches that take gcc.c-torture/execute and gcc.target/microblaze
to zero FAIL and UNRESOLVED on microblaze-elf and microblazeel-elf. Two
fix the compiler; two fix the testsuite. See `0000-cover-letter.txt`.

Base: gcc master `df809a029`. They also apply, after `patches/gcc/0001`
to `0003`, to master `fceddda85` (2026-11-14). They are in
`patches/gcc/` as 0004 to 0007, so `make check` uses them.

| patch | failures it removes |
|---|---|
| 1/4, varargs with no named parameter | `pr117432.c`, 7 |
| 2/4, `-fPIE -mpic-data-is-text-relative` ICE | `picdtr.c`, 112 |
| 3/4, testsuite | isa print (6 files), `fcmp4.c` (1), LTO no-fat scans (17 files) |
| 4/4, `fileio` at run time | `fprintf-2.c`, 7 (now UNSUPPORTED) |

The numbers in the cover letter were measured with the series on top of
`gcc-microblaze-fixes`. That series adds tests to microblaze.exp, so its
pass count is higher than with this series alone.

4/4 is the only generic change. The alternative for `fprintf-2.c` was a
RAM filesystem in the board, about 150 lines for one test.

Each compiler fix is checked with `check_GNU_style.py`, and every commit
message with `git_check_commit.py`.

With this series alone on `df809a029`, as `patches/gcc/0004`-`0007`, the
runner's `make check` gave `execute.exp` 24536 PASS, 183 UNSUPPORTED and
`microblaze.exp` 644 PASS, with no failures (2026-11-14, big-endian).
