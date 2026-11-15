# gcc-microblaze-generic-divsi3

One patch: replace libgcc's hand-written MicroBlaze `divsi3.S`, `modsi3.S`,
`udivsi3.S` and `umodsi3.S` with the generic `divmod.c`, `udivmod.c` and
`udivmodsi4.c`. `mulsi3.S`, `moddi3.S`, `stack_overflow_exit.S` and
`divsi3_table.c` stay. Not sent.

- `0001-...patch`: against gcc master `df809a029` plus
  `gcc-microblaze-zero-fails`, `gcc-microblaze-cbranch` and
  `gcc-microblaze-libgcc-asm`. It touches only libgcc, so it applies to
  plain master too, except where `libgcc-asm` 0001 removed the
  `muldi3_hard.S` line next to it.
- `on-runner/0001-...patch`: the same change for the runner, which also
  carries `gcc-microblaze-generic-moddi3` (no `moddi3.S` line). Used as
  `patches/gcc/0013` for the runner run below.

## Status and follow-up

**On hold, not sent** (2026-11-14). Not in `patches/gcc/`; the runner
still uses the assembly.

The generic C is a trade-off, not a clear win (big-endian, no options,
per call; full tables in `0000-cover-letter.txt` and
`bench/results-div.txt`):

| `__divsi3` | assembly | generic C |
|---|---|---|
| random operands, instructions | 280.0 | 209.9 (-25%) |
| short quotient (0-15), instructions | 223.6 | 70.2 (-69%) |
| long quotient (divisor 1-15), instructions | 301.0 | 450.0 (+50%) |
| worst case, five-stage cycles, no branch target cache | 401 | 620 (+55%) |
| worst case, five-stage cycles, perfect branch target cache | 314 | 499 (+59%) |

`__udivsi3`, `__modsi3` and `__umodsi3` behave the same. With every
hardware option except the divider, the C gains about 5% and the shape
stays. With the divider, gcc emits `idiv` inline (36 cycles for a
quotient, 38 for a remainder) and never calls these routines.

Why: `udivmodsi4.c` shifts the divisor up one bit at a time until it
passes the dividend, then subtracts one bit at a time, so it runs two
loops each as long as the quotient. The assembly shifts the dividend
past its leading zeros once and runs one loop.

Options:

1. Send as is. Faster on average and for short quotients, but up to
   about 55-59% slower in the worst case; reviewers who care about
   worst-case timing may object. Not recommended as is.
2. Keep the assembly; this folder stays as a measured negative result.
3. Make the generic `udivmodsi4.c` normalize once, e.g. count leading
   zeros with `__builtin_clz` and start the loop there, under a target
   opt-in macro like `LIBGCC2_MOD_WITHOUT_QUOTIENT` in
   `gcc-microblaze-generic-moddi3`. That could win on both mean and
   worst case, but it is a new generic libgcc patch, reviewed like the
   moddi3 series, and needs measuring on another no-divider target
   (armv6-m) as that series was.

Recommendation: 3 if the speed-up is wanted, otherwise 2.

Other results to keep:

- Keep `mulsi3.S`: every C `__mulsi3` tried is 20-40% slower (below).
- `__muldi3` costs about 1026 estimated cycles per call in a default
  libgcc, 94 when libgcc is built with `-mno-xl-soft-mul`, and 10
  inline with `-mxl-multiply-high`. A multilib toolchain links the
  94-cycle one on a core with the multiplier; a `--disable-multilib`
  toolchain, like the runner's, links the 1026-cycle one.
- Behaviour change in the patch: `0 / 0` returns 1 instead of 0
  (undefined behaviour either way). `x / 0` and `x % 0` still give 0.
- Not done: a little-endian runner run (the correctness tables were run
  on little-endian), and libgcc builds for microblaze-linux and
  microblaze-rtems7.

Cycle-model caveats (from the review of the counter, 2026-11-14):

- "c5" charges every taken branch as if there were no branch target
  cache; "cb" is the bound with a perfect one (5-stage only, and only
  if the core is built with it). The truth for a core with a BTC lies
  between.
- Data-hazard stalls (5-stage) are counted separately by `bench/mbhaz.c`;
  they add at most 2 cycles per call here.
- All cycles are estimates from UG984's per-instruction latencies with
  single-cycle local memory, not hardware measurements. Instruction
  counts are model-free.
- This bench carries its own plugin, `bench/mbcount3.c` (the reviewed
  counter plus the perfect-BTC bound), because `bench/moddi3/mbcount.c`
  is being fixed separately (taken branch to the fall-through address,
  BTC and hazard fields). Once that lands, `bench.sh` should use
  `bench/moddi3/mbcount.c` and drop `mbcount3.c` and `mbhaz.c`. No
  branch in any routine measured here targets its own fall-through
  address (438 checked), so that bug does not affect these numbers.

## Multiply: keep `mulsi3.S`

libgcc2.c has no 32-bit `__mulsi3`. Three C loops from other ports, no
options, mean (max) per call:

| `__mulsi3` | operands | insns | c5 (max) | perfect BTC (max) |
|---|---|---|---|---|
| asm | random | 102.6 | 134.0 (225) | 102.6 (182) |
| C over the smaller \|operand\| (`bench/mulc/c-smaller.c`) | random | 141.3 | 162.9 (269) | 141.3 (233) |
| asm | small multiplier | 27.3 | 36.2 (44) | 27.3 (35) |
| C, smaller operand | small multiplier | 38.1 | 44.9 (53) | 38.1 (44) |

epiphany's `mulsi3.c` (loop over a) and lm32's `_mulsi3.c` (loop over b)
were slower still: 251.6 (260) and 203.7 (261) c5 on random operands, on an
earlier draw of the same distribution. On small multipliers the epiphany
loop takes 256 cycles against the asm's 36, because it loops over the other
operand.

The asm wins every comparison, by about 20-40%: its loop (`srl`, `addc`,
`beqi`, `bneid` + `add` in the slot) uses the carry, which C cannot. The C
loops never become `mul` with `-mno-xl-soft-mul`; with it, gcc inlines
`mul` (3 cycles c5 per call through a wrapper) and never calls
`__mulsi3`. The barrel shifter does not change any of them. Not replaced.

## `__muldi3` (64-bit multiply)

| | random 64-bit | 32x32-bit | c5 |
|---|---|---|---|
| libgcc `__muldi3`, default build (calls `mulsi3.S` 4+ times) | 811.6 insns | 499.0 | 1025.8 (1084) |
| same with the C `__mulsi3` above | 1036.1 | 620.6 | 1181.3 (1271) |
| `__muldi3` built with `-mno-xl-soft-mul` | 91.1 | 91.1 | 94.0 (94) |
| inline, `-mno-xl-soft-mul -mxl-multiply-high` | 9.0 | 9.0 | 10.0 (10) |

gcc inlines a 64-bit multiply only with `-mxl-multiply-high`; with the
multiplier alone it calls `__muldi3`. Upstream `t-microblaze` has a
`mno-xl-soft-mul` multilib, so a multilib toolchain links the 94-cycle
version. A `--disable-multilib` toolchain, like this runner's, links the
default one: about 1026 cycles, eleven times slower, on a core that has
the multiplier. Not a bug; worth knowing when configuring.

## How to recreate

Everything below runs from a clone of microblaze-testsuite; no other
files are needed. Times are from an 8-core Apple M1 Pro.

### 1. Toolchain, QEMU and sources (the runner)

```sh
git clone https://github.com/thesamprice/microblaze-testsuite
cd microblaze-testsuite
make GCC_REF=df809a029f522bc22265ad5ec0eb98f46421030e
```

`make` takes about 8 minutes on an idle machine (the top-level README);
a rebuild of gcc, newlib and QEMU took 18 minutes here with other
builds running. The little-endian toolchain takes a little less. This
builds `work/install` (microblaze-elf binutils, gcc, newlib),
`qemu-system-microblaze[el]` with `patches/qemu/0001`'s exit device
(the benches need it), and the patched DejaGnu whose
`contrib/microblaze-qemu-run` `check.sh` uses. Its `work/src/gcc` has
`patches/gcc` applied but not this series, so `work/src/gcc/libgcc` still
has the assembly the benches compare against: that is the default
`LIBGCC_SRC`. The published numbers were made with an earlier runner
toolchain, `work/install` from 2026-11-07 (gcc `df809a029`); a different
gcc may change the C columns slightly. The assembly columns depend only
on the `.S` files.

For little-endian `check.sh le`, also build a microblazeel-elf
toolchain from the same, already patched, sources:

```sh
W=$PWD/work
make toolchain libxil TARGET=microblazeel-elf \
  PREFIX=$W/install-le STAMP=$W/stamps-le BUILD=$W/build-le LOGS=$W/logs/le \
  BINUTILS_SRC=$W/src/binutils GCC_SRC=$W/src/gcc \
  NEWLIB_SRC=$W/src/newlib DEJAGNU_SRC=$W/src/dejagnu
```

Pass the four `*_SRC` variables: with a new `STAMP` directory and no
`*_SRC`, `make` would re-clone every source, and its clone step deletes
`work/src/<name>` first. Pass `BUILD=`, not `*_BUILD=`: the Makefile
treats a `*_BUILD` you set as an existing tree and skips building it.

The plugins need the host compiler, `pkg-config` and glib (Homebrew or
MacPorts `glib`), and `timeout` (GNU coreutils) on PATH; the scripts
need bash 4 or later.

### 2. Run

```sh
B=patches/series/gcc-microblaze-generic-divsi3/bench
$B/check.sh be                       # correctness, 5 configurations, ~10 s
$B/check.sh le                       # needs work/install-le
$B/bench.sh > div-raw.txt            # division, 4 configurations, ~40 s
python3 $B/table2.py div-raw.txt     # = $B/results-div.txt
CFGS="def bs bsonly allnomul" $B/bench.sh __mulsi3 > mul-raw.txt   # ~15 s
python3 $B/table2.py mul-raw.txt     # = $B/results-mulsi3.txt
$B/muldi3/run.sh > muldi3-raw.txt    # ~5 s; = $B/results-muldi3-raw.txt
$B/audit/run.sh be                   # the original audit of libgcc's assembly
```

Objects, ELFs and plugins go to `$OUT`, default `work/bench/divsi3`.
`check.sh` prints one line per configuration and should say `0
mismatches` everywhere, with `0/0=0x00000001` from the generic C.

Each script documents its environment variables at the top: `WORK`,
`INSTALL`, `INSTALL_LE`, `QEMU`, `LIBGCC_SRC`, `LIBGCC_BUILD` (muldi3:
the configured libgcc build directory whose `_muldi3.o` compile command
is reused, default `work/build/gcc/microblaze-elf/libgcc`), `OUT`,
`CFGS`, `MULC`.

To build gcc with the patch itself (for `make check-gcc`), copy
`on-runner/0001-*.patch` to `patches/gcc/0013-...patch` and run `make`
and `make check-gcc` again; the runner re-applies `patches/gcc` and
rebuilds. Remove it afterwards to go back to the assembly. To apply it
to plain gcc, `git apply` `0001-*.patch` onto a `df809a029` checkout
that has `gcc-microblaze-libgcc-asm` 0001, or the `on-runner` copy onto
one that also has `gcc-microblaze-generic-moddi3`.

### 3. Files

| file | what |
|---|---|
| `bench/bench.sh` | the asm/C/inline cycle bench (division, `__mulsi3`) |
| `bench/genbench.py` | operand sets (seed 2026), written to `$OUT/bench.h` |
| `bench/cbench.c`, `bench/inline.c` | the calling loop; the inline reference |
| `bench/mbcount3.c`, `bench/mbhaz.c` | QEMU plugins: counts and cycles; 5-stage hazard stalls |
| `bench/table2.py` | raw lines to tables |
| `bench/check.sh`, `bench/audit/` | correctness: `gen.py` writes host-computed tables (`$OUT/.../tables.h`), `test.c` and `ops.c` run them |
| `bench/mulc/` | the three C `__mulsi3` candidates |
| `bench/muldi3/` | `run.sh`, `genb64.py` (seed 64), `cb64.c`, `inl.c` |
| `bench/results-*.txt` | the published raw output and tables |

### 4. Reproduction check

On 2026-11-14 the scripts above, run from an empty `$OUT` with the
default paths against the 2026-11-07 runner toolchain, reproduced
`results-div-raw.txt`, `results-div.txt` and `results-muldi3-raw.txt`
byte for byte, and `results-mulsi3-raw.txt` line for line (the saved
file lists its configurations in the order `def bsonly allnomul bs`).
`genbench.py`, `genb64.py` and `audit/gen.py` regenerate the original
`bench.h`, `b64.h` and `tables.h` byte for byte. `check.sh be` gave 0
mismatches in all five configurations.

## Runner

`make check-gcc` in `work/wt-zero` with `patches/gcc/0001`-`0012` plus this
patch as `0013` (big-endian, gcc `df809a029`, stock QEMU 10.2.4):
execute.exp 24536 PASS, 183 UNSUPPORTED; microblaze.exp 770 PASS; 0 FAIL.
That's the same as the baseline with 0001-0012. `libgcc.a` has
`__udivmodsi4` and no assembly division labels.

Not done: a little-endian runner run (the boundary tables were run on
little-endian), and libgcc builds for microblaze-linux and
microblaze-rtems7.

Estimates, not hardware measurements.
