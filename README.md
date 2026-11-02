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
| QEMU | release tarball, 10.2.4 | `microblaze-softmmu`, `microblazeel-softmmu` |

The clones are shallow. The `*_GIT` and `*_REF` variables pick another
repository or branch, e.g. `make GCC_REF=releases/gcc-15`.

Any `patches/<component>/*.patch` is applied after cloning, in order. That is
how the board gets into DejaGnu, and how to test a patch: drop a binutils or
gcc patch into `patches/binutils/` or `patches/gcc/`, then
`make clean && make`. Delete `work/stamps/src-<component>` too to re-clone.

On the machine this was developed on (8 cores, Apple silicon), `make` from
nothing takes about 7½ minutes, `check-binutils` about 3½ and
`check-gcc-smoke` about 12. In Docker on the same machine, `docker-all` plus
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

The failures:

- **ld `S-records`.** `ld --oformat srec` applies `R_MICROBLAZE_64` through the
  generic howto, which writes the low 16 bits of the address into the `imm`
  instruction and leaves the following one unpatched. Linking to ELF and
  converting with `objcopy` is correct.
- **gcc `pr50865.c` (7) and `arith-rand-ll.c` (8).** `__moddi3` in libgcc is
  wrong on MicroBlaze. `pr50865.c` hangs; `arith-rand-ll.c` aborts. Both pass
  with a fixed `__moddi3` linked ahead of libgcc.
- `pr28982b.c` is UNSUPPORTED. It says `dg-require-stack-size "0x80100"`,
  and the board declares `gcc,stack_size 16384`, though the stack it links
  is 4 MB. The board understates it; raising the declared size would let the
  test run.
