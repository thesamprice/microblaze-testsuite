# MicroBlaze toolchain testsuite

Builds a `microblaze-elf` cross toolchain and QEMU from upstream sources and
runs the binutils and GCC DejaGnu testsuites against them. The GCC execute
tests really run, under QEMU system emulation, through the `microblaze-qemu`
DejaGnu board in [`patches/dejagnu/`](patches/dejagnu/).

```sh
make                     # fetch and build binutils, gcc+newlib+libgloss, DejaGnu, QEMU
make check-gcc-smoke     # eight execute tests across all torture levels
make check-binutils      # binutils, gas and ld testsuites
make check-gcc           # gcc.c-torture/execute and gcc.target/microblaze
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
| `gcc/0004`–`0007` | [`patches/series/gcc-microblaze-zero-fails`](patches/series/gcc-microblaze-zero-fails/), not yet sent: `va_arg` with no named parameter, the `-fPIE -mpic-data-is-text-relative` ICE, and the `gcc.target/microblaze` and `fileio` testsuite fixes |
| `gcc/0008`–`0010` | [`patches/series/gcc-microblaze-cbranch`](patches/series/gcc-microblaze-cbranch/), not yet sent: removes the dead, wrong `cbranchsi4_reg`, adds run tests for integer compare and branch, and fixes unsigned comparisons against zero being tested as signed |
| `binutils/0001` | [`patches/series/binutils-microblaze-srec-64`](patches/series/binutils-microblaze-srec-64/): `IMM`-pair relocations for `--oformat srec` and other non-ELF output |
| `dejagnu/0002` | [`patches/series/dejagnu-spawn-split`](patches/series/dejagnu-spawn-split/), without its ChangeLog entry: DejaGnu master's `local_exec` passes the command line to `spawn` as one word, so nothing runs |
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

From 2026-11-14, `make check` from a fresh `work/`: binutils `2e7f60647f1`,
gcc `df809a029`, newlib `041b6410bfa`, DejaGnu `6ea0ff70328`, each plus
the patches here, and QEMU 10.2.4 plus `patches/qemu`. Big-endian, the
default `MB_NO_RELAX`.

| | pass | fail | xfail | untested | unsupported |
|---|---|---|---|---|---|
| binutils | 272 | 0 | 2 | 0 | 14 |
| gas | 331 | 0 | 0 | 0 | 10 |
| ld | 548 | 0 | 15 | 9 | 232 |
| gcc `execute.exp` | 24536 | 0 | 0 | 0 | 183 |
| gcc `microblaze.exp` | 756 | 0 | 0 | 0 | 0 |

There is no FAIL, UNRESOLVED or XPASS anywhere. The gcc rows are from a
later `check-gcc` with `patches/gcc/0008`-`0010` added; before them,
`microblaze.exp` gave 644 passes, also with no failures. `execute.exp` and
`microblaze.exp` also had no failures on `microblazeel-elf`, built by hand
with these gcc patches and the `gcc-microblaze-fixes` series.

gcc is pinned to `df809a029` for this run (`GCC_REF=df809a029f52...`):
gcc master `fceddda85` of 2026-11-14 does not build on macOS, because
`lto1` fails to link with an undefined analyzer symbol. The patches here
also apply to that revision.

What it took to get to zero:

- **ld `S-records`**: `patches/binutils/0001`. `ld --oformat srec` applied
  `R_MICROBLAZE_64` through the generic howto, which wrote the low 16 bits
  of the address into the `imm` instruction and left the following one
  unpatched.
- **gcc `pr117432.c`** (7): `patches/gcc/0004`. `void f (...)`, a C23
  variadic function with no named parameter, read garbage from `va_arg`.
- **gcc `picdtr.c`** (112): `patches/gcc/0005`. `-fPIE
  -mpic-data-is-text-relative` ICEd on any data access, and the test had
  never compiled because it held two copies of itself.
- **The rest of `microblaze.exp`**: `patches/gcc/0006`, testsuite only. Six `isa/` tests called `print` undeclared, `fcmp4.c` wanted
  `fcmp.eq` where gcc now emits `fcmp.ne`, and every `scan-assembler` test
  failed in the `-fno-fat-lto-objects` run.
- **gcc `fprintf-2.c`** (7): `patches/gcc/0007`. The `fileio` effective
  target only checked that `fopen` links, which it does against libgloss's
  stubs; it now runs the program, so the test is UNSUPPORTED on bare metal.
- **DejaGnu master** ran nothing: `patches/dejagnu/0002`. Since 2026-11-06
  it passes the whole command line to `spawn` as one word.

Before these patches, with gcc `df809a029`, `execute.exp` gave 24536 PASS
and 14 FAIL (`fprintf-2.c` and `pr117432.c`), and `microblaze.exp` 554
PASS, 142 FAIL and 31 UNRESOLVED. The first run, on 2026-11-01, also had 30 `__moddi3` failures,
fixed upstream as gcc `3a721dc02`.

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
