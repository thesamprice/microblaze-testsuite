# MicroBlaze toolchain testsuite

Builds a `microblaze-elf` cross toolchain and QEMU from upstream sources and
runs the binutils and GCC DejaGnu testsuites against them. The GCC execute
tests really run, under QEMU system emulation, through the `microblaze-qemu`
DejaGnu board in [`patches/dejagnu/`](patches/dejagnu/).

```sh
make                     # fetch and build binutils, gcc+newlib+libgloss, DejaGnu, QEMU
make check-gcc-smoke     # eight execute tests across all torture levels
make check-binutils      # binutils, gas and ld testsuites
make check-gcc           # gcc.c-torture/execute, all of it
make summary             # the summaries of the last runs, and the source revisions
make bench-moddi3        # instructions and estimated cycles for libgcc's 64-bit division
```

Or the same in Docker, on any machine:

```sh
make docker-all docker-check-gcc-smoke
```

## What it builds

Everything goes under `work/` (set `WORK=` to move it):

| | source | |
|---|---|---|
| binutils | `binutils-gdb.git` `master` | `--disable-gdb --disable-sim` |
| gcc | `gcc.git` `master` | C only, `--with-newlib --disable-multilib` |
| newlib, libgloss | `newlib-cygwin.git` `main` | symlinked into the gcc tree, so gcc builds them |
| DejaGnu | `dejagnu.git` `master` + the board patch | run from its source tree, nothing installed |
| QEMU | release tarball, 10.2.4 + `patches/qemu` | `microblaze-softmmu`, `microblazeel-softmmu` |

The clones are shallow. The `*_GIT` and `*_REF` variables pick another
repository, branch, tag or full commit hash, e.g.
`make GCC_REF=releases/gcc-15`. `EXTRA_PATCHES_gcc` (and likewise for the
other components) names more directories of patches to apply after
`patches/gcc`, e.g.
`make EXTRA_PATCHES_gcc=patches/series/gcc-microblaze-carry`.

## Patches

Any `patches/<component>/*.patch` (`binutils`, `gcc`, `newlib`, `dejagnu`,
`qemu`) is applied to that component's clone, or for QEMU to the unpacked
tarball, in name order, with `git apply`. Drop a
patch in and run `make`: adding, changing or deleting a patch resets the clone
to the revision it was cloned at, applies the set again, and rebuilds what
depends on it. The source does not move to a newer upstream; delete
`work/stamps/src-<component>` to re-clone. Patches are not applied to trees
given with `*_SRC` (below).

| | |
|---|---|
| `dejagnu/0001` | the `microblaze-qemu` board and the `libxil` UART driver. The copy here leaves out the patch's ChangeLog entry, which conflicted as soon as upstream added one of its own; the full patch is `outbox/dejagnu/` in `rtems-microblaze-linker-relaxation-bug` |
| `gcc/0001`–`0003` | the libgcc series in [`patches/series/gcc-microblaze-generic-moddi3`](patches/series/gcc-microblaze-generic-moddi3/), not yet sent: libgcc2.c's shift-and-subtract `__udivmoddi4` masks out the quotient bits, and `__umoddi3`/`__moddi3` can keep only the remainder; then MicroBlaze uses that code unless `-mno-xl-soft-div`, and drops `moddi3.S` |
| `qemu/0001` | a test device on `petalogix-s3adsp1800` at `0xff000000`: a write exits QEMU with that status, and reads give the exact instruction count under `-icount`. Used by `bench-moddi3`; the DejaGnu board does not need it |

`patches/series/` holds patch series as they will be mailed upstream; see
[`patches/series/README.md`](patches/series/README.md). The MicroBlaze
back-end series there, `gcc-microblaze-carry`, is not in `patches/gcc/`.

On the machine this was developed on (8 cores, Apple silicon), `make` from
nothing takes about 7½ minutes, `check-binutils` about 3½,
`check-gcc-smoke` about 12 and `check-gcc` about 55, of which 10½ is
`pr50865.c` waiting out its timeout seven times. Every other test stops
QEMU as soon as it has printed its exit status, in about 0.3 s. In Docker on the same machine, `docker-all` plus
`docker-check-gcc-smoke` took 23 minutes, and every test result was the same
as the native run.

## Using your own trees

Each component can be one you already have. Whatever is not given is built.

| variable | meaning |
|---|---|
| `BINUTILS_SRC`, `GCC_SRC`, `NEWLIB_SRC` | a source tree to configure and build here, instead of cloning |
| `BINUTILS_BUILD`, `GCC_BUILD` | an already-built build tree, tested in place and not rebuilt |
| `TOOLBIN` | the `bin` directory holding `microblaze-elf-gcc` etc., when `GCC_BUILD` is yours |
| `DEJAGNU_SRC` | a DejaGnu tree, which must already have the board patch |
| `QEMU` | a `qemu-system-microblaze` binary |

For example, to test your own binutils build with this repo's gcc and QEMU:

```sh
make check-binutils BINUTILS_BUILD=$HOME/build/binutils-mb
```

`libxil.a` is installed beside the toolchain's `libc.a` (see below), so with
`TOOLBIN` pointing at your own toolchain, that toolchain gains a `libxil.a`.

## How the board works, and the three things that bite

GCC's MicroBlaze `LIB_SPEC` links `-lgloss -lxil -lc -lm`. libgloss and newlib
supply three; `-lxil` is the board's own library, which in Xilinx's world comes
from the BSP and upstream builds nothing for. `make libxil` builds it from the
forty-line UART driver the board patch adds, and installs it where the
compiler finds it unprompted.

QEMU cannot return a guest's exit status. The board sets
`needs_status_wrapper`, so GCC's testsuite links DejaGnu's `testglue.c`, which
prints `*** EXIT code N`; DejaGnu reads that, and `contrib/microblaze-qemu-run`
kills QEMU once it appears.

1. **`MB_NO_RELAX=-Wl,--no-relax` is on by default.** MicroBlaze relaxation
   currently mis-places `__wrap_*` symbols, so `testglue.c`'s `__wrap_exit`
   resolves before its own first instruction, no status line is printed, and
   every execution test reports 2. Set `MB_NO_RELAX=` once the linker has the
   fix. While it is on, the suite does not exercise relaxation.
2. **The board does nothing for binutils.** gas never runs target code. ld
   decides whether it can execute by running a test program and reading its
   exit status, and ld's testsuite does not link `testglue.c`, so there is no
   status line and its run tests come out UNSUPPORTED or UNTESTED. The board is
   set for `check-binutils` only so that the target is configured the same way.
3. **ld probes the compiler before the board's flags apply**
   (`ld/testsuite/config/default.exp`). If `-lxil` needed a `-L` from the
   board, the probe would fail and ld would skip every compiling test. Hence
   the install location. The Makefile also passes
   `CC_FOR_TARGET=microblaze-elf-gcc`: a binutils-only tree otherwise looks for
   `microblaze-elf-cc`.

## Running the testsuite by hand

`make env` prints the environment the Makefile runs in. With that exported:

```sh
cd work/build/gcc
make check-gcc RUNTESTFLAGS="--target_board=microblaze-qemu execute.exp=pr50865.c"
```

The board finds QEMU from `MB_QEMU`, the per-test limit from `MB_TIMEOUT`
(default 90 s), and its runner on `PATH`. runtest finds the board through the
site file named by `DEJAGNU`, which holds one line:

```
lappend boards_dir "<DejaGnu source>/baseboards"
```

Without it, runtest reports `couldn't load description file for
microblaze-qemu`.

GCC's `check-gcc` ignores `RUNTEST` and runs the first `runtest` on `PATH`, so
the DejaGnu source directory has to come before any installed DejaGnu there.
`make env` puts it first.

## Docker

`make docker-<target>` runs `make <target>` in the image built from
[`Dockerfile`](Dockerfile) (Debian trixie). The work tree lives in the Docker
volume `microblaze-testsuite-work`, not in a bind mount, because gcc and newlib
are not safe to build on the case-insensitive filesystem macOS shares into
containers. Results are copied to `./results/`.

```sh
make docker-all                 # build everything in the container
make docker-check-gcc-smoke     # then test
make docker-check-binutils
make docker-shell               # a shell in the container; the tree is in /work
make docker-clean               # delete the volume
```

Variables such as `GCC_REF`, `GCC_TESTS`, `RUNTESTFLAGS`, `MB_NO_RELAX` and
`JOBS` given on the command line are passed into the container. The
"own trees" variables are not, since the paths would not exist in there.

## Results

From 2026-11-01: binutils `8614f56cb25`, gcc `a9f669055c2`, newlib
`b097f95233d`, DejaGnu `04e420155f7` plus the board, stock QEMU 10.2.4.

| | pass | fail | xfail | untested | unsupported |
|---|---|---|---|---|---|
| binutils | 272 | 0 | 2 | 0 | 14 |
| gas | 329 | 0 | 0 | 0 | 10 |
| ld | 546 | 1 | 15 | 9 | 232 |
| gcc, `check-gcc-smoke` | 91 | 15 | 0 | 0 | 8 |
| gcc, `check-gcc` (all of `execute.exp`) | 24498 | 38 | 0 | 0 | 176 |

The earlier `patches/gcc/0001`, the `__moddi3` fix, was dropped on
2026-11-07: it is upstream as gcc `3a721dc02`. With gcc master `df809a029`
and the current `patches/gcc`, the full `check-gcc` gave 24536 passes, 14
failures (`fprintf-2.c` and `pr117432.c`, below) and 176 unsupported, both
big- and little-endian.

The failures:

- **ld `S-records`.** `ld --oformat srec` applies `R_MICROBLAZE_64` through the
  generic howto, which writes the low 16 bits of the address into the `imm`
  instruction and leaves the following one unpatched. Linking to ELF and
  converting with `objcopy` is correct.
- **gcc: 30 of the 38 are `__moddi3`.** libgcc's 64-bit signed remainder is
  wrong on MicroBlaze: `arith-rand-ll.c` (8), `vector-div-neg-pow2.c` (8),
  `pr50865.c` (7) and `pr33669.c` (1, `-O0` only). `pr50865.c` hangs until the
  timeout; the others abort. All four pass at `-O0` with a fixed `__moddi3`
  linked ahead of libgcc, which leaves the other two tests failing. These
  numbers predate the fix, now upstream as gcc `3a721dc02`.
- **gcc `pr117432.c` (7): C23 variadic functions with no named parameter.**
  `void qux (...)` reads garbage from `va_arg` at `-O0` and `-O2`, while
  `void baz (int, ...)` is right. A compiler bug, and not the IPA problem the
  PR is about.
- **gcc `fprintf-2.c` (7): no filesystem.** GCC's `fileio` effective target
  only checks that `fopen` links, which it does against libgloss's stubs; on
  bare metal it fails at run time and the test exits 1. A limitation of the
  environment, not of the compiler.
- `pr28982b.c` is UNSUPPORTED. It says `dg-require-stack-size "0x80100"`,
  and the board declares `gcc,stack_size 16384`, though the stack it links
  is 4 MB. The board understates it; raising the declared size would let the
  test run.

## 64-bit division benchmark

`make bench-moddi3` builds libgcc's 64-bit divide and remainder routines
in several variants: the hand-written `moddi3.S`, upstream `libgcc2.c`,
`libgcc2.c` with `patches/gcc`, and C versions that borrow the assembly's
techniques one at a time. It builds them with libgcc's default CPU options
and with more of them, up to every option QEMU implements, for both byte
orders, and checks each against 4701 vectors. For each it reports the
instructions per call, counted through `patches/qemu/0001`'s device, and
estimated clock cycles per call for the five-stage and three-stage
MicroBlaze pipelines.

The cycle figures come from [`bench/moddi3/mbcount.c`](bench/moddi3/mbcount.c),
a QEMU plugin that costs each executed instruction with UG984's latency
for it, and costs each branch by whether it was taken and whether it has a
delay slot. It assumes single-cycle local memory, no branch target cache
and no data hazard stalls. They are estimates, not measurements on
hardware. [`bench/moddi3/summary.py`](bench/moddi3/summary.py) prints them,
and [`bench/moddi3/REPORT.md`](bench/moddi3/REPORT.md) discusses the
variants.

### Reproducing the published numbers

```sh
bench/moddi3/reproduce.sh [DIR]
```

rebuilds everything behind the cycle tables in the
[`patches/series/`](patches/series/) cover letters from scratch, at the
gcc, binutils and newlib revisions they were measured at. It builds two
toolchains in `DIR` (default `./work-reproduce`): one with the libgcc
series (`patches/gcc`), and one with the back-end series
(`gcc-microblaze-carry`) as well. It runs the benchmark with each and
writes `DIR/tables.md` (big-endian) and `DIR/tables-le.md`. Each table
gives every version of each routine, from the original Xilinx assembly to
the libgcc series with the back end, for each set of CPU options. Each
cell gives the mean and the slowest call. It needs about 9 GB, and took
22 minutes on an 8-core Mac. To recompute the tables from finished runs:

```sh
python3 bench/moddi3/table.py DIR/series1/bench/results.txt \
    DIR/carry/bench/results.txt [be|le]
```

### More

Two more targets go with it:

- `make bench-moddi3-host` compiles the same libgcc2.c routines for a host
  machine, in Docker, before and after `patches/gcc`. It checks that a
  normal host libgcc does not change, and times the new code with
  `TARGET_HAS_NO_HW_DIVIDE` forced on.
- `make coverage-moddi3` measures line and branch coverage of the 64-bit
  divide and remainder routines with
  [tcgcov](https://github.com/thesamprice/tcgcov), over all of
  `gcc.c-torture/execute` and over the bench vectors. It takes about an
  hour. `TCGCOV` names a tcgcov checkout (default `~/src/tcgcov`).
