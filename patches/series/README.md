# Patch series for upstream

Each directory here is a patch series as it will be mailed upstream: a
`0000-cover-letter.txt` and the `git format-patch` output. The Makefile
does not apply them. A series the build should use is also copied into
`patches/<component>/`.

| series | for | status |
|---|---|---|
| `binutils-microblaze-opcodes` | binutils@sourceware.org | seven patches against binutils master `1b10c36dfd4`, not yet sent. Fixes the `bslli`/`bsrai`/`bsrli` decoding, `wdc.ext.clear`, the `mbar` pseudo-instruction aliases and the zero word, comments the `mbar` forms that enter a sleep mode, removes the undocumented `pcmpbc`, and adds a test of every instruction whose expected encodings were checked against QEMU and UG984. Issues #40 to #44 in thesamprice/rtems-microblaze-linker-relaxation-bug |
| `gcc-microblaze-generic-moddi3` | gcc-patches@gcc.gnu.org | three patches against gcc master `df809a029`, ready to send. Makes `__udivdi3` and `__divdi3` mask out the quotient bits, adds a remainder-only loop for `__umoddi3`/`__moddi3` that a target opts into with the documented `LIBGCC2_MOD_WITHOUT_QUOTIENT`, and has MicroBlaze opt in and drop `moddi3.S`. Figures are estimated cycles. Tested big- and little-endian and with the divider; nothing slower on Cortex-M0. Also in `patches/gcc/`. GCC 17 stage 1 ends 2026-11-16, so post before then |
| `gcc-microblaze-carry` | gcc-patches@gcc.gnu.org | three MicroBlaze back-end patches against gcc master `df809a029`, ready to send. 64-bit shifts by one, 32-bit shifts by 31 and unsigned 64-bit overflow checks go through the carry flag. Independent of the libgcc series, but its division speed-ups show only with it: with both, `__divdi3` without a divider drops from 1717 to 524 estimated cycles per call. Shrinks the default multilib's libc by 7.7%. Tested big- and little-endian. Not in `patches/gcc/`, so `make` builds without it |

Add `Signed-off-by:` before sending.
