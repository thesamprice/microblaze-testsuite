# `__moddi3` on MicroBlaze: the assembly fix against the generic C

> **Status, 2026-11-08.** The numbers below are instruction counts from
> earlier drafts of `patches/gcc`. The benchmark now also estimates clock
> cycles (`mbcount.c`, from UG984's instruction latencies), and
> `make bench-moddi3` prints them through `summary.py`. The current
> figures, in cycles, are in the cover letters under
> [`patches/series/`](../../patches/series/): the libgcc series
> `gcc-microblaze-generic-moddi3` and the back-end series
> `gcc-microblaze-carry`. [`reproduce.sh`](reproduce.sh) rebuilds them
> from scratch and writes every version side by side, with the slowest
> call for each. The findings below still hold in cycles: the
> remainder-only loop and the fused sign test win, and the sign test beats
> a plain compare and `__builtin_sub_overflow`.

The two alternative fixes for libgcc's broken 64-bit signed remainder were:

- **the assembly patch**: fix `libgcc/config/microblaze/moddi3.S`. This is
  what went upstream, as gcc `3a721dc02` (2026-11-04);
- **the other patch**: delete `moddi3.S` and let libgcc build the generic
  `__moddi3` from `libgcc2.c`.

This compares them instruction for instruction, together with C versions
that borrow the assembly's tricks one at a time, to see which of those
tricks are worth having in C, in libgcc's generic code, for every target.

Reproduce with `make bench-moddi3`. Every number below comes from the run
of 2026-11-07: gcc master `df809a029`, QEMU 10.2.4 with
`patches/qemu/0001`. Two complete runs gave byte-identical results.

## Method

`patches/qemu/0001` adds a test device to `petalogix-s3adsp1800` at
`0xff000000`. A write exits QEMU with that status. Reads return
`icount_get_raw()`, the exact count of guest instructions executed under
`-icount`. Its registers follow the CPU's byte order, so the big-endian
byte-swapping the earlier harness needed is gone.

[`bench.c`](bench.c) calls `__moddi3` through a volatile function pointer
for each of 4701 vectors. It reads the counter before and after each call
and subtracts the cost of two back-to-back reads. A call's count therefore
runs from the indirect branch into `__moddi3` to its return, delay slots
and any libgcc helpers included. The fixture checks every result, then
exits QEMU with the failure count as its status. [`gen.c`](gen.c) makes
the vectors with a fixed splitmix64, so they are the same on any host, in
five classes:

| class | n | operands |
|---|---|---|
| edge | 701 | every pair of 27 boundary values (0, ±1, ±2^31, ±2^32, `LLONG_MIN`, `LLONG_MAX`, ...) |
| small | 1000 | both below 2^31 |
| wide/narrow | 1000 | 63-bit dividend, divisor below 2^31 |
| wide/wide | 1000 | both 63-bit, so the quotient is small |
| mixed | 1000 | dividend 33 to 63 bits, divisor 1 to 63 bits |

A second pass runs each binary under [`mbcount.c`](mbcount.c), a TCG
plugin. It counts the instructions executed from `__moddi3` to the end of
`.text`, which is the routine and the helpers linked after it, by class:
divide, multiply, barrel shift, `clz`, `imm`, load, store, branch, and taken
branches. Its totals equal the fixture's less exactly 2 per call, the
caller's `brald` and delay slot, so the two methods agree.

Each C variant is built twice:

- **def**: no CPU options. This is what libgcc is built with:
  `-mcpu=v4.00.a`, soft multiply, soft divide, no barrel shifter. No
  shipped multilib (`gcc/config/microblaze/t-microblaze`) enables a
  hardware divide.
- **full**: everything QEMU's CPU implements:
  `-mcpu=v11.00.a -mxl-barrel-shift -mxl-pattern-compare -mno-xl-soft-mul
  -mxl-multiply-high -mno-xl-soft-div -mxl-reorder`, all at `-O2`.

The assembly is the same code either way.

| variant | what |
|---|---|
| `stock` | `moddi3.S` before `3a721dc02` |
| `asm` | `moddi3.S` now: **the assembly patch** |
| `generic` | `libgcc2.c` `__moddi3`: **the other patch** |
| `generic-nohw` | the same with `TARGET_HAS_NO_HW_DIVIDE`, libgcc2.c's shift-and-subtract `__udivmoddi4`, which MicroBlaze does not select |
| `rem` | [`moddi3-rem.c`](moddi3-rem.c): shift-and-subtract that keeps only the remainder, divisor aligned under the dividend with `__builtin_clzll` |
| `rem-fused` | the same, with `moddi3.S`'s subtract-and-test-the-sign in place of a compare |
| `rem-left` | the same, but moving the remainder left past a fixed divisor, as `moddi3.S` does |

## Results

Big-endian. Little-endian is the same for `asm` and within 1.2% for every
C variant (`results.txt` has both). All variants returned 4701 correct
results on both byte orders. `stock` did not terminate on either.

| variant | opts | size (insns) | mean insns/call | min | max | taken branches/call | `idiv`/call | ~cycles/call |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| **asm** | | 44 | **522.5** | 18 | 728 | 99.7 | 0 | 720 |
| **generic** | def | 1047 | **1349.8** | 50 | 3129 | 280.4 | 0 | 1909 |
| generic-nohw | def | 263 | 1330.6 | 41 | 5294 | 91.4 | 0 | 1511 |
| rem | def | 155 | 495.8 | 29 | 1469 | 79.2 | 0 | 652 |
| rem-fused | def | 150 | 449.3 | 29 | 1214 | 74.2 | 0 | 596 |
| rem-left | def | 298 | 2214.9 | 41 | 7441 | 96.2 | 0 | 2405 |
| **generic** | full | 422 | **91.7** | 35 | 153 | 8.9 | 2.15 | 174 |
| generic-nohw | full | 147 | 299.7 | 37 | 1131 | 33.6 | 0 | 365 |
| rem | full | 114 | 279.8 | 27 | 1053 | 35.6 | 0 | 349 |
| rem-fused | full | 112 | 235.2 | 28 | 801 | 30.6 | 0 | 294 |
| rem-left | full | 134 | 336.9 | 34 | 1151 | 32.2 | 0 | 399 |

Size is the routine's own object, not counting helpers. With default
options `generic` calls `__udivsi3`, `__umodsi3` and `__mulsi3` and reads
`__clz_tab`; the shift-and-subtract variants call `__clzdi2`. With full
options only `generic` still uses a helper, `__clz_tab`.

**The cycle column is a model, not a measurement.** It assumes 1 cycle per
instruction, 2 extra per taken branch and 31 extra per `idiv`, which is
roughly a 5-stage MicroBlaze with a 32-cycle divider. Those latencies are
not checked against Xilinx's UG984 for any particular configuration. It is
there because instruction counts flatter `generic full`, whose `idivu`
takes many cycles. Its lead survives the model with room to spare.

Mean instructions per call, by vector class:

| variant | opts | edge | small | wide/narrow | wide/wide | mixed |
|---|---|---:|---:|---:|---:|---:|
| asm | | 416.2 | 373.6 | 647.7 | 599.9 | 543.2 |
| generic | def | 970.8 | 859.8 | 2646.0 | 729.9 | 1429.2 |
| generic-nohw | def | 1064.9 | 712.4 | 3168.8 | 196.9 | 1430.5 |
| rem | def | 386.5 | 288.3 | 1045.2 | 191.2 | 535.3 |
| rem-fused | def | 347.6 | 264.1 | 928.3 | 189.8 | 486.1 |
| rem-left | def | 1679.7 | 890.0 | 5677.4 | 298.3 | 2369.1 |
| generic | full | 79.5 | 84.9 | 115.1 | 83.2 | 92.4 |
| generic-nohw | full | 245.0 | 163.5 | 708.3 | 51.1 | 314.2 |
| rem | full | 223.6 | 132.4 | 686.5 | 43.1 | 296.6 |
| rem-fused | full | 186.6 | 109.9 | 571.8 | 43.6 | 249.6 |
| rem-left | full | 266.3 | 151.5 | 831.6 | 55.8 | 358.0 |

### The two patches

**As libgcc is actually built, the assembly patch is 2.6 times faster than
the other patch**: 522.5 against 1349.8 instructions per call, and 44
instructions of code against 1047 plus four helpers. The generic C pays for
`__udiv_qrnnd_c`, which calls the software `__udivsi3`, `__umodsi3` and
`__mulsi3` several times per call. The choice upstream made was right for
every MicroBlaze libgcc that ships.

**On a core with a hardware divider the generic C wins by a factor of
5.7** in instructions (91.7 against 522.5), and by about 4 in the cycle
model. `moddi3.S` cannot use `idiv`, and libgcc is never built to.

## What the assembly does by hand, and what carries over

Here is the assembly's inner loop against the compiler's for the same
algorithm (`rem-fused`, full options), from `work/bench/moddi3/dis/`:

```
moddi3.S, one iteration per dividend bit    gcc, rem-fused full, one per quotient bit
  add   OPX_L,OPX_L,OPX_L   # RES:OPX <<= 1  srl   r12,r4          # Y >>= 1, high
  addc  OPX_H,OPX_H,OPX_H   # through the    rsub  r9,r5,r11       # T = R - Y
  addc  RES_L,RES_L,RES_L   #  carry         rsubc r8,r4,r10
  addc  RES_H,RES_H,RES_H                    bslli r7,r4,31        # Y >>= 1, low (*)
  rsub  TRIAL_L,OPD_L,RES_L # T = R - D      srl   r3,r5
  rsubc TRIAL_H,OPD_H,RES_H                  addk  r4,r12,r0
  blti  TRIAL_H,skip        # sign of T      bltid r8,skip         # sign of T
  or    RES_H,r0,TRIAL_H    # keep T          addik r6,r6,-1       #  (delay slot)
  or    RES_L,r0,TRIAL_L                     addk  r10,r8,r0       # keep T
skip:                                        addk  r11,r9,r0
  addik COUNT,COUNT,-1                     skip:
  bnei  COUNT,loop                           bgeid r6,loop
                                             addk  r5,r7,r3        #  (delay slot)
  9 insns, 11 when kept                      10 insns, 12 when kept
```

(*) objdump prints this `bslli` (`0x64e4041f`) as `bsrli`. That is a
binutils bug, below.

Per iteration they are within one or two instructions of each other. The
difference is how many iterations each runs, and the fixed cost around the
loop. Taking the assembly's techniques one at a time:

**1. Keep only the remainder.** `moddi3.S` drops the quotient. libgcc2.c's
shift-and-subtract `__udivmoddi4` cannot: its loop shifts quotient bits
into the low end of the remainder, and separating them afterwards takes
two variable 64-bit shifts. `rem` against `generic-nohw` measures what a
remainder-only loop saves: **63% with default options** (495.8 against
1330.6), because without a barrel shifter those variable shifts are loops.
With full options it saves **7%** (279.8 against 299.7).
*Generic: not on every target (see the Cortex-M0 section).* A remainder-only path for `__umoddi3` and `__moddi3` under
`TARGET_HAS_NO_HW_DIVIDE` in libgcc2.c would help every target that sets
that macro: cris, pru, pdp11 and msp430, xtensa without `DIV32`, and arm
cores without the divide extension. It matters most where variable
shifts are expensive. Measured on MicroBlaze, and on a host CPU with the
macro forced on (below).

**2. Fuse the compare into the subtraction.** `moddi3.S` subtracts into
scratch and branches on the sign of the result. In `moddi3.S` that is sound
because both operands are magnitudes of signed values, at most 2^63. A C
compiler cannot know such a bound, so `if (r >= y) r -= y` becomes a
64-bit unsigned compare (`cmpu`, `xor`, `cmpu` and three branches)
followed by a separate `rsub`/`rsubc`. The fused form is the `rsub`/`rsubc`
and one branch. Writing the fused form in C (`rem-fused` against `rem`)
saves **9% with default options and 16% with full**.
*Correct for both remainder routines, but only a win without flags (see the Cortex-M0 section).* An earlier version of this
report said the fused test was only valid for signed operands. That was
wrong once the divisor is aligned under the dividend, as libgcc2.c does.
The aligned divisor's top bit is where the dividend's is, so the first
difference is smaller than that bit. After that the remainder stays below
the divisor, which is at most 2^63, so every difference is in signed
range for any operands. An exhaustive check of every 8-, 10- and 12-bit
pair (about 17.9 million) found no wrong remainder. A replay of all
560,327 calls the torture tests make (below) found no step where the sign
test and the unsigned comparison disagree. It should help any target
without a flags register, where a double-word unsigned compare is several
instructions: MicroBlaze, RISC-V, MIPS, LoongArch, Nios II. On ARM or
x86, `subs`/`sbcs` already fuse the two, so expect nothing there.

**3. Shift the remainder left through the carry.** The assembly's
`add`/`addc` chain shifts the 128-bit RES:OPX pair left in four
instructions. C has no carry, and the closest C (`rem-left`) is the worst
variant measured: 2214.9 instructions per call with default options. The
cause is a MicroBlaze back-end weakness, not the algorithm. Without a
barrel shifter, gcc compiles `x >> 31` as 31 consecutive `srl`
instructions, and `(x >> 63)` the same way. The assembly's carry trick does
it in two: `add rT,rX,rX` moves bit 31 into the carry, and `addc rD,r0,r0`
reads it out. That sequence was checked on QEMU on both byte orders.
*Generic: no.* The idiom does not exist in C. It is a MicroBlaze back-end
fix: `lshrsi3` by 31 without a barrel shifter should use `add`/`addc`, and
`ashrsi3` by 31 the same plus a negation. That would speed up any code
that tests or extracts a sign bit, not just this routine.

**4. Skip the dividend's leading zeros.** The assembly normalizes the
dividend one bit at a time (4 instructions a bit), then runs one iteration
per remaining dividend bit, whatever the divisor. The C variants shift the
divisor up under the dividend with `clz` and run one iteration per
*quotient* bit. That is why the assembly costs ~600 instructions on
wide/wide, where the quotient is a bit or two, against 43 for `rem full`
and 190 for `rem-fused def`. Overall that is enough for `rem-fused def`,
compiled C with no special options, to beat the hand-written assembly:
449.3 against 522.5.
*Generic: libgcc2.c already does this.* It is the assembly that should
adopt it. A `moddi3.S` that aligned the divisor would keep the
assembly's per-iteration advantage and lose its worst cases. With
`-mxl-pattern-compare` on v8.10 and later it could use `clz`; without, a
bit loop like the current one.

**5. Early exit for a zero dividend.** That is the assembly's minimum of
18. Rare in real code. *Not worth carrying over.*

**6. Registers.** `moddi3.S` saves and restores four callee-saved
registers (`r25`–`r28`): 8 memory operations and 2 stack adjustments per
call, about 2% of its mean. The caller-saved `r10`, `r11`, `r12` and `r18`
are free in that function, so it needs no frame at all. The compiled C
also spills 3 or 4 callee-saved registers. *MicroBlaze only*: a cheap
follow-up to `moddi3.S`.

**7. Use the hardware divider when there is one.** Not something the
assembly does, but the largest single effect measured: `generic full`
runs at 91.7 instructions per call. gcc predefines `__HAVE_HW_DIV__` for
`-mno-xl-soft-div`, so `moddi3.S` could fall back to the generic C in
that case. In practice that needs a hardware-divide multilib, and
`t-microblaze` has none. That makes it a packaging decision for anyone
building a toolchain for a core with a divider (RTEMS, PetaLinux), more
than a libgcc patch. *MicroBlaze only.*

## Dropping `moddi3.S`: the generic fixes, measured

The question: with the generic changes above made in libgcc2.c, can
MicroBlaze drop `moddi3.S` and still get the assembly's speed without a
hardware divider, and the divider's speed with one?

`patches/gcc/` carries a three-patch series:

1. `libgcc: mask out the quotient bits in __udivmoddi4`. In libgcc2.c's
   shift-and-subtract `__udivmoddi4`, take the quotient's low bits with
   `r & (bit - 1)` rather than `q + r - ((r >> k) << k)`. That is one
   variable double-word shift fewer, and none when the remainder is not
   wanted.
2. `libgcc: remainder-only __umoddi3 and __moddi3`. Under
   `TARGET_HAS_NO_HW_DIVIDE`, one loop that keeps only the remainder
   (point 1 above) and uses the fused sign test (point 2) for both
   routines.
3. `microblaze: use the generic __moddi3, drop moddi3.S`. A new
   `libgcc/config/microblaze/microblaze-lib.h` defines
   `TARGET_HAS_NO_HW_DIVIDE` unless `__HAVE_HW_DIV__`, and `moddi3.S`
   goes.

For comparison, [`moddi3-new.S`](moddi3-new.S) is `moddi3.S` with what the
C does better. It aligns the divisor and runs once per quotient bit, a
word at a time and then a bit at a time, since the baseline CPU has no
`clz`. It returns early when |X| < |D|, has no stack frame, and shifts the
divisor right with `SRL`/`SRC`. It keeps the fused sign test and fills its
delay slots. It is not part of any patch.

Mean instructions per call, big-endian; little-endian is within 1%. All
variants were correct on all 4701 vectors, on both byte orders. `mlib` is
`-mxl-barrel-shift -mno-xl-soft-mul -mxl-multiply-high`, the most capable
multilib gcc ships. `nodiv` is every option except the divider.

| routine | variant | def | mlib | nodiv | full |
|---|---|---:|---:|---:|---:|
| `__moddi3` | upstream `moddi3.S` | 522.5 | 522.5 | 522.5 | 522.5 |
| | `moddi3-new.S` | **220.0** | **220.0** | **220.0** | 220.0 |
| | upstream libgcc2.c | 1349.8 | 902.2 | 901.9 | **91.7** |
| | patched | 457.0 | 275.3 | 238.9 | **91.7** |
| `__umoddi3` | upstream | 921.1 | 625.6 | 625.3 | 54.3 |
| | patched | **338.0** | **197.2** | **170.7** | 54.3 |
| `__divdi3` | upstream | **1303.3** | 903.7 | 903.5 | 88.4 |
| | patched | 1312.7 | **338.4** | **307.5** | 88.4 |
| `__udivdi3` | upstream | **891.1** | 626.7 | 626.6 | 44.2 |
| | patched | 951.0 | **245.4** | **218.4** | 44.2 |

Upstream libgcc links `moddi3.S` whatever the CPU options;
`t-microblaze` adds it unconditionally. So the upstream `__moddi3` a user
actually gets is 522.5 in every column, **including on a core with a
divider and a libgcc built for it**. With the series that core gets the
generic C's 91.7.

- **With the divider** the patched library is identical to upstream's
  generic code for all four routines, and `__moddi3` is 5.7 times faster
  than today's `moddi3.S`.
- **Without the divider**, the generic `__moddi3` beats today's `moddi3.S`
  in every configuration: by 13% with no options, and by 47% and 54% with
  a barrel shifter. `__umoddi3` gets 2.7 to 3.7 times faster.
- **Division with a barrel shifter** gets 2.6 to 2.9 times faster, as a
  side effect of selecting the shift-and-subtract path.
- **Division with no options is the one regression**: `__divdi3` +0.7% and
  `__udivdi3` +6.7% in mean instructions, and the worst case rises by about
  75% (5302 against 3072). The shift-and-subtract loop costs more per
  quotient bit than upstream's long division when the quotient is long,
  and less when it is short. The cycle model, with its caveats, puts
  patched division 14% to 19% *faster* there, because upstream's long
  division calls the software `__udivsi3`, which branches heavily.
  Settling it needs hardware or a validated cycle model.
- **`moddi3-new.S` is the fastest `__moddi3` without a divider**: 2.1 times
  the patched generic code with no options, and 8% to 25% faster with the
  other options. With a divider the generic code wins by 2.4 times, and an
  assembly routine cannot use the divider unless it is written twice.

What each generic patch buys on its own, from upstream libgcc2.c with
`TARGET_HAS_NO_HW_DIVIDE` forced (`generic-nohw` in `results.txt`) to
patched:

| routine | def | mlib | nodiv |
|---|---|---|---|
| `__divdi3` (patch 1) | 1405.5 → 1312.7 | 376.0 → 338.4 | 311.5 → 307.5 |
| `__udivdi3` (patch 1) | 1007.6 → 951.0 | 242.6 → 245.4 | 222.9 → 218.4 |
| `__moddi3` (patch 2) | 1330.6 → 457.0 | 332.4 → 275.3 | 299.7 → 238.9 |
| `__umoddi3` (patch 2) | 959.3 → 338.0 | 238.5 → 197.2 | 203.9 → 170.7 |

Little-endian matches to within 1%, except `__divdi3` with `mlib` before
patch 1: 343.8 there against 376.0 big-endian.

**To get the divider's numbers in practice**, libgcc must be built with
`-mno-xl-soft-div`: a multilib, or the target flags of the build. That
works today for every routine except `__moddi3`, which stays at 522.5
until `moddi3.S` goes.

With the series applied to gcc master `df809a029`, the full
`gcc.c-torture/execute` run gave 24536 passes, 14 failures and 176
unsupported. The failures are `fprintf-2.c` (no filesystem) and
`pr117432.c` (a variadic-argument bug), 7 each; none is in division.

## On a host machine

What reviewers will ask first: does this change anything off MicroBlaze?
[`host/host.sh`](host/host.sh) answers it with a real host gcc (Debian's
gcc 14.2 in Docker), run natively on an Apple M1 Pro (Linux/AArch64) and
as `linux/amd64`. `make bench-moddi3-host` runs both.

**A normal host libgcc does not change.** Every change in the series is
inside `#ifdef TARGET_HAS_NO_HW_DIVIDE`, which no x86 or AArch64
configuration defines. `__moddi3`, `__umoddi3`, `__divdi3`, `__udivdi3`,
`__divmoddi4` and `__udivmoddi4` were compiled from libgcc2.c before and
after, both with 32-bit words and with the host's 64-bit words (where they
are `__modti3`, `__divti3` and so on, which is what a host libgcc has). All
24 disassemblies are identical before and after, on both AArch64 and
x86_64.

**With `TARGET_HAS_NO_HW_DIVIDE` forced on**, as on the targets that do
define it, the new code runs on a host CPU. All variants were correct on
all 4701 vectors, on both architectures. Best of 9 trials, nanoseconds per
call, native AArch64, from two runs:

| routine | host's divide instruction | upstream default (long division) | NO_HW before | NO_HW after |
|---|---:|---:|---:|---:|
| `__moddi3` | 2.6, 2.3 | 9.7, 9.1 | 20.4, 20.5 | **16.7, 16.6** |
| `__umoddi3` | 2.2, 2.2 | 5.1, 5.0 | 13.7, 13.6 | **12.1, 11.3** |
| `__divdi3` | 2.2, 2.1 | 9.0, 9.3 | 22.1, 22.0 | 21.5, 20.9 |
| `__udivdi3` | 2.3, 2.1 | 4.1, 4.2 | 14.7, 14.1 | 14.9, 14.3 |

These are from the final series, after the `__umoddi3` correction. The
remainder routines get 11% to 19% faster, as on MicroBlaze. The division
differences are within run-to-run noise. AArch64 has condition flags, so
its compiler already fuses compare and subtract, and the fused test gains
less there than on MicroBlaze. The x86_64 timings come from emulation, so
they are not quoted. With a hardware divider the shift-and-subtract path
is far slower than long division, which is why it is only for targets
without one.

This is timing, not instruction counting, so read it as about ±5%. In the
"all" column the classes are interleaved, which defeats the branch
predictor more than any one class does alone, so it is not their
average.

## On a real no-divider target: Cortex-M0

ARM Cortex-M0 (armv6-m) defines `TARGET_HAS_NO_HW_DIVIDE`, so the generic
gcc patches 1 and 2 apply to it as they are. The routines were built from
libgcc2.c, before and after, by Debian's `arm-none-eabi-gcc` 14.2 at
`-O2 -mcpu=cortex-m0 -mthumb`. They ran on QEMU's `microbit` machine, a
real Cortex-M0 model, and a TCG plugin counted instructions in the libgcc
address range. Same 4701 vectors; all 108 runs correct. The scripts are in
the session scratchpad (`gaps-arm/`), not in this repo.

| routine | before | after | change |
|---|---:|---:|---:|
| `__aeabi_ldivmod`, what C's signed `/` and `%` call | 487.7 | 483.6 | -0.9% |
| `__aeabi_uldivmod`, what C's unsigned `/` and `%` call | 249.1 | 252.1 | **+1.2%** |
| `__udivdi3` | 229.9 | 207.3 | -9.8% |
| `__divdi3` | 406.5 | 402.3 | -1.0% |
| `__moddi3` | 280.7 | 356.5 | **+27.0%** |
| `__umoddi3` | 193.6 | 282.0 | **+45.7%** |

Every patched object is smaller (by 4 to 76 bytes).

**Patch 2 loses on ARM.** On ARM EABI ordinary C never calls `__moddi3`
or `__umoddi3`: `%` goes through `__aeabi_ldivmod` (via `__divdi3`) and
`__aeabi_uldivmod` (via `__udivmoddi4`). So only code that names them is
slowed. The reason is the two machines' strengths:

- `__udivmoddi4`'s loop shifts the remainder left, which on Thumb-1 is
  `adds`/`adcs`. The remainder-only loop shifts the divisor right, about
  5 instructions, and runs one more iteration.
- ARM compares with flags, so the fused sign test saves nothing.
- MicroBlaze has neither a barrel shifter nor flags, so there the final
  variable shift `__udivmoddi4` needs is a loop and the fused test saves
  a compare. That is why the same change wins on MicroBlaze.

**Patch 1 is mixed on ARM.** It wins where the remainder is dead
(`__udivdi3`, `__divdi3`), and loses 1.2% on the exported `__udivmoddi4`
behind `__aeabi_uldivmod`. Keeping the 64-bit `bit` live across the loop
spills on Thumb-1's eight low registers.

So the two "generic" patches are MicroBlaze wins, not general ones. See
"Suggested follow-ups" for the options.

## Coverage: do the torture tests reach every case?

Measured with [tcgcov](https://github.com/thesamprice/tcgcov) on the
patched libgcc, and checked a second way by capturing the operands of
every call. `make coverage-moddi3` runs it (about an hour); the scripts
are in [`coverage/`](coverage/).

**Lines and branches.** All of `gcc.c-torture/execute` ran through the
DejaGnu board with [`coverage/qemu-cov`](coverage/qemu-cov) standing in
for QEMU. It records every run that links one of the four routines: 385
runs from 61 test sources, many of them the `printf` family, since newlib's
`vfprintf` uses `__udivdi3` and `__umoddi3`. The 4701 bench vectors were
recorded the same way against the installed libgcc. Every coverable line
and every branch outcome of the new and changed code was reached by both:

| libgcc2.c function | lines (torture / vectors) | branch outcomes (torture / vectors) |
|---|---|---|
| `__udivmoddi4` (no-divider path) | 18/18, 18/18 | 36/36, 40/40 |
| `__umoddi_no_hw_divide` | 8/8, 8/8 | 16/16, 22/22 |
| `__divdi3` | 12/12, 12/12 | 6/6, 12/12 |
| `__moddi3` | 11/11, 10/10 | 6/6, 6/6 |
| `__umoddi3` | 3/3, 3/3 | none |
| `__udivdi3` | 3/3, 3/3 | 0/0, 6/6 |

The two sources compile to different binaries, so their branch counts
differ. `work/coverage/annotated.txt` has the line-by-line listing. This
is the default multilib only: big-endian, no CPU options.

**Value corners.** Branch coverage cannot say which inputs reached a
branch. [`coverage/argcap.c`](coverage/argcap.c), a second QEMU plugin,
logged the operands of all 586,641 calls the 61 tests make.
[`coverage/analyse-args.py`](coverage/analyse-args.py) classifies them
and replays the patched algorithms on each. Its call counts match
tcgcov's entry counts exactly. The torture tests reach:

- every sign combination, a zero dividend, divisor ±1, |n| = |d|, and
  exact division, for all four routines;
- `LLONG_MIN` as dividend and as divisor, and a partial remainder of
  2^63 in `__moddi3`, but **only through `divmod-2.c`** (gcc `9bc2d240b`,
  added from this work in October). Without it the suite would miss those
  states;
- the longest loop, 64 steps, in `__moddi3` (only `pr50865.c`),
  `__umoddi3` and `__udivdi3` (only `arith-rand-ll.c`);
- operands with the top bit set in the unsigned routines (only
  `arith-rand-ll.c`, `pr69447.c`, `pr99079.c` and `pr42721.c`).

**One gap**: no test runs `__divdi3` with a 64-step loop. For signed
division that needs `LLONG_MIN / 1`: `LLONG_MIN / -1` is undefined, and
`pr50865.c` only tests `%`. A line in `divmod-2.c` would close it. The
bench vectors do cover it.

Across all 586,641 calls and all 4701 vectors, the sign test agreed with
the unsigned comparison at every step (point 2).

## Found on the way: objdump mislabels immediate barrel shifts

binutils' MicroBlaze disassembler prints `bslli`, `bsrai` and `bsrli` all
as `bsrli`. gas encodes them correctly (`0x400`, `0x200` and `0` in bits
10 and 9). The entries in `opcodes/microblaze-opc.h` use
`OPCODE_MASK_H3B`, `0xFC00F9E0`, which leaves out exactly those two bits.
The decoder takes the first entry with `bit_sequence == (inst & mask)`,
and the `bslli` and `bsrai` patterns have bits outside the mask, so they
can never match and everything decodes as `bsrli`. Filed as
[issue #40](https://github.com/thesamprice/rtems-microblaze-linker-relaxation-bug/issues/40).

It is worse than a wrong listing. The gdb simulator decodes through the
same table, so it *executes* `bslli` and `bsrai` as `bsrli`: `bslli r3,
r4, 4` with r4 = 1 gives 0, not 16. GDB disassembles through it as well.
The mask came in with binutils commit `2d1777b530d` (2023-10-19), so
binutils 2.42 was the first affected release.

A check of the whole opcode table against QEMU's decoder, with UG984 as
the referee, then found three more disassembler bugs of the same family:
`wdc.ext.clear` prints as `wdc.clear`, `mbar 9`, `17` and `31` print as
`hibernate`, `sleep` and `suspend`, and objdump stops at a zero word. It
also found one QEMU bug: `mbar 8` (Hibernate) does not halt. A five-patch
binutils series fixes the four bugs, then adds a test of 277 of the 278
instructions, plus the `sleep`, `hibernate` and `suspend`
pseudo-instructions. Its expected encodings come from QEMU and UG984, not
from the table. Each stage was built and tested (gas 331 → 333 passes,
binutils and ld unchanged). It has not been sent.

## Suggested follow-ups

In order of benefit for the effort:

1. **MicroBlaze back end**: shift right by 31 without a barrel shifter as
   `add`/`addc`, not 31 `srl`. It is general-purpose, small, and verified
   on QEMU.
2. **`moddi3.S` or the generic code, decide which.** The series in
   `patches/gcc/` drops `moddi3.S` for libgcc2.c (see "Dropping
   `moddi3.S`"). Keeping assembly instead, `moddi3-new.S` with the
   divisor aligned and no stack frame is 2.4 times faster than today's
   `moddi3.S`: 220.0 against 522.5. It cannot use a divider, though, and
   with one the generic code is 2.4 times faster than it.
3. **libgcc2.c, generic**: patches 1 and 2 of the gcc series help
   MicroBlaze but not Cortex-M0, where patch 2 slows `__moddi3` and
   `__umoddi3` by 27% and 46% (see "On a real no-divider target").
   Options: make them opt-in for targets that want them, through a macro
   only MicroBlaze defines; or keep libgcc2.c as it is and put the
   remainder loop in a MicroBlaze C file that replaces `moddi3.S`.
4. **Testsuite**: add `LLONG_MIN / 1` to `divmod-2.c`, the one corner no
   torture test reaches (see "Coverage").
5. **binutils**: send the five-patch series that fixes issue #40 and the
   three bugs the UG984 cross-check found, and adds a test of every
   instruction.
6. **QEMU**: report that `mbar 8` (Hibernate) does not halt; UG984 p. 285
   says `IMM & 24` enters sleep, QEMU tests `IMM & 16`.
7. **Packaging**: a `-mno-xl-soft-div` multilib, or the generic C when
   `__HAVE_HW_DIV__`, for cores with a divider (point 7).

## Files

| | |
|---|---|
| [`run.sh`](run.sh) | builds and runs everything; `make bench-moddi3` calls it |
| [`bench.c`](bench.c), [`start.S`](start.S), [`link.ld`](link.ld) | the fixture |
| [`gen.c`](gen.c) | the vectors |
| [`mbcount.c`](mbcount.c) | the instruction-class plugin |
| [`moddi3-rem.c`](moddi3-rem.c) | the `rem`, `rem-fused` and `rem-left` variants |
| [`moddi3-new.S`](moddi3-new.S) | `moddi3.S` with the C's improvements, for comparison only |
| [`moddi3-stock.S`](moddi3-stock.S) | `moddi3.S` as it was before `3a721dc02`, byte for byte |

The upstream `moddi3.S` and `libgcc2.c` are read from the gcc tree's
`HEAD`, and the patched ones from its working tree, where `patches/gcc` has
been applied. Results,
logs and disassembly land in `work/bench/moddi3/`.
