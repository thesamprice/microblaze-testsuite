# rtems-microblaze-no-relax

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#15 (workaround
for #71). For: GitLab MR against rtems/rtos/rtems. Goes together with
`../rsb-microblaze-default-toolchain/` (RSB moves microblaze to GCC 15.2 /
binutils 2.47).

Base: RTEMS `origin/main` 53d56d9494 (fetched 2026-11-13; it had not moved
since the earlier RSB runs, so the base is the same tree as `rsb-base`).
Branch `rtems-new-norelax` (worktree `work/src/rtems-new-norelax`), commit
269e919bb5e6. One patch: `0001-bsps-microblaze-Link-with-no-relax.patch`.
Not pushed. No Signed-off-by; it has `Assisted-by: Claude`.

## What it does

Adds `-Wl,--no-relax` to `ABI_FLAGS` in
`spec/build/bsps/microblaze/microblaze_fpga/abi.yml`. That item is the
ABI_FLAGS for every microblaze BSP (kcu105, kcu105_qemu,
petalogix_s3adsp1800 are all family microblaze_fpga and link `abi`).
ABI_FLAGS also go into the installed `<arch>-rtems7-<bsp>.pc`
(`Cflags`/`Ldflags`/`Libs`), so applications built with pkg-config or
rtems_waf get `--no-relax` too.

GCC's microblaze `*link` spec is
`%{shared:-shared} -N -relax %{mlittle-endian:-EL ...} ...`. The driver puts
the spec's `-relax` before the user's `-Wl,` options, and ld takes the last
of `-relax` / `--no-relax`. Checked (verified) with `gcc -###` on the exact
link command waf used for samples/hello: the collect2 line has `-relax` at
argument 13 and `--no-relax` at argument 36.

Why: #71. GCC writes the C++ LSDA call-site table as `.uleb128` differences
of code labels; gas resolves them without relocations; `ld -relax` deletes
IMM prefixes and the table goes stale. The binutils fix is #47 A-F (patches
0001-0015 in `../binutils-microblaze-eh-relax/` and `patches/binutils/`),
not posted upstream yet. Revert this patch once the RSB default binutils
has it.

## Build (exact, verified)

Tools: RSB 7/rtems-microblaze from `../rsb-microblaze-default-toolchain/`
(work/build/rtems-new/rsb/install: GCC 15.2.0 20250808, GNU ld 2.47.20260726).

```
cd work/src/rtems-new-norelax
B=work/build/rtems-new/norelax-patch
# config.ini: [microblaze/petalogix_s3adsp1800] BUILD_SAMPLES, BUILD_SPTESTS,
#             BUILD_TMTESTS, BUILD_PSXTESTS, BUILD_LIBTESTS = True
./waf configure -o $B --rtems-config=$B/config.ini \
  --rtems-tools=work/build/rtems-new/rsb/install --prefix=$B/install
caffeinate -i ./waf build -v > $B/build.log 2>&1
```

- All five testsuites build: samples 11, sptests 225, tmtests 41,
  psxtests 87, libtests 157 .exe (521, of which 47 are `*.norun.exe`).
  **0 warnings** (`grep -c warning: build.log`).
- kcu105 and kcu105_qemu (samples only, `work/build/rtems-new/norelax-kcu105`):
  build, 0 warnings, `-Wl,--no-relax` on the link lines. Not run (need the
  Xilinx QEMU).

Relaxed twins for comparison, built from the unpatched `work/src/rtems-new-main`
(same commit) with the same config.ini:

- `work/build/rtems-new/rsb-base-all`: RSB tools (GCC 15.2 / 2.47), relaxed.
  0 warnings.
- `work/build/rtems-new/bsp-base-all`: RTEMS 7 tools in `~/rtems/7`
  (GCC 12.4.1 20240905, GNU ld 2.36.1.20210409 = the Xilinx pin), relaxed.
  0 warnings, **but the 2.36 ld segfaulted twice, intermittently**, linking
  `libtests/dup2.norun.exe` (first build) and `libtests/gettimeofday.norun.exe`
  (`waf build -k` rerun); a third `waf build` relinked it and finished. Both
  are norun programs. Not investigated (not with the new tools).

## Relaxation is off (verified)

`size` text of every program, rsb-base-all (relaxed) vs norelax-patch:

| suite | programs | larger with patch | text relaxed | text --no-relax | growth |
|---|---|---|---|---|---|
| samples | 11 | 11 | 4,517,175 | 4,631,331 | 2.53% |
| sptests | 225 | 225 | 49,659,887 | 51,464,571 | 3.63% |
| tmtests | 41 | 41 | 8,491,799 | 8,809,607 | 3.74% |
| psxtests | 87 | 87 | 20,183,074 | 20,903,918 | 3.57% |
| libtests | 157 | 157 | 45,762,439 | 47,205,435 | 3.15% |
| all | 521 | 521 | 128,614,374 | 133,014,862 | **3.42%** |

hello 250,008 -> 258,780 (+3.51%), cdtest 383,663 -> 393,199, ticker
214,065 -> 221,777. These are 16-24 bytes more than the earlier
`rsb-norelax` build (258,764 / 393,179 / 221,753), which had the same flags
but was built from `rtems-new-main`; the difference is the longer source
path in `__FILE__` strings (`rtems-new-norelax` vs `rtems-new-main`). Code
size cost: about 3.4-3.5%.

## Tests (exact, verified)

Harness: the one used for the earlier rsb-base run
(`scripts/runtest.sh`, `scripts/runsuites.sh`): QEMU 10.2.4
`work/build/qemu/qemu-system-microblazeel-unsigned -M petalogix-s3adsp1800
-m 256`, serial to a file, 4 in parallel, 120 s timeout; PASS = `*** END OF
TEST`, FAIL = `RTEMS shutdown` without it, TIMEOUT otherwise. `*.norun.exe`
skipped.

```
scripts/runsuites.sh work/build/rtems-new/norelax-patch OUT sptests samples tmtests psxtests libtests
python3 scripts/cmp.py results/old-tools.txt results/rsb-relax.txt results/norelax-patch.txt
```

The norelax-patch run was split in two (sptests+samples 12:11-12:18, then
tm/psx/lib 12:19-12:25, host load 11-17 on 8 cores); the two relaxed twins
ran after it back to back (12:30-12:53, load 6-10). Results per program are
in `results/`.

474 programs (sptests 225 + samples 11 + tmtests 41 + psxtests 87 +
libtests 157, minus 47 norun):

| tools | pass | fail | timeout |
|---|---|---|---|
| RTEMS 7 (GCC 12.4.1, Xilinx 2.36), relaxed (`bsp-base-all`) | 469 | 5 | 0 |
| GCC 15.2 + 2.47, relaxed (`rsb-base-all`) | 468 | 4 | 2 |
| **GCC 15.2 + 2.47 + this patch** (`norelax-patch`) | **470** | **4** | **0** |

Non-passing, all rerun once with the same harness:

| test | old tools | 2.47 relaxed | 2.47 + patch | rerun | note |
|---|---|---|---|---|---|
| samples/cdtest | PASS | TIMEOUT | **PASS** | relaxed: TIMEOUT again | #71 |
| libtests/dl05 | PASS | TIMEOUT | **PASS** | relaxed: TIMEOUT again | C++ exceptions with libdl; relaxed build stops after `exception_base: begin`, then a `TOO_LITTLE_WORKSPACE` fatal with no executing thread (looks like a wild jump back to start). Not root-caused; same symptom class as #71 |
| libtests/dl06 | FAIL | FAIL | FAIL | FAIL | `TEST STATE: EXPECTED_FAIL` (all BSPs) |
| psxtests/psxfenv01 | FAIL | FAIL | FAIL | FAIL | `TEST STATE: EXPECTED_FAIL` (microblaze `tst-xfail-psxfenv01`) |
| sptests/spcpucounter01 | FAIL | FAIL | FAIL | FAIL | `init.c:153 tick < rtems_clock_get_ticks_since_boot()`; fails with all three toolchains |
| sptests/spfatal26 | FAIL | FAIL | FAIL | FAIL | `init.c:45 0`; fails with all three toolchains |
| sptests/spnsext01 | FAIL | PASS | PASS | old tools: PASS | timing flake |

So with the patch: 470 pass, 2 expected fails, and the same 2 real fails
as the old tools (spcpucounter01, spfatal26). No test regresses against
either baseline; cdtest and dl05 go from hang to pass. cdtest and dl05 were
also checked with the other QEMU setup (`work/install/bin/qemu-system-microblazeel`
with the rtems-tools `petalogix_s3adsp1800.ini` options, via
`../binutils-microblaze-eh-relax/repro/runq.sh`): END OF TEST with the
patch, none in the relaxed build.

Against the earlier runs (sptests + samples, 235 programs; `results/earlier-*.txt`):

| run | pass | fail | timeout |
|---|---|---|---|
| earlier RTEMS 7 tools (`bsp-base`, 2026-11-12, high load) | 220 | 7 | 8 |
| earlier RSB relaxed (`rsb-base`, 2026-11-13) | 231 | 2 | 2 (cdtest, spfatal12) |
| this patch, same 235 | **233** | 2 | 0 |

## Not done / skipped

- next and edge RSB sets: not built (each RSB build is ~2.75 h here; task
  marked it optional). Skipped.
- rtems-test (rtems-tools tester) not used; the hand harness above was used
  so the numbers compare with the earlier runs. fstests, mptests, smptests,
  validation tests not built.
- kcu105/kcu105_qemu built but not run; big-endian not tested.
- rtems-libbsd and other applications through pkg-config: not tested, only
  checked that ABI_FLAGS are what goes into the .pc file.

## Open questions

- BSP or GCC? The same workaround could be in GCC's
  `gcc/config/microblaze/rtems.h` LINK_SPEC (drop `-relax`) or as an RSB GCC
  patch, which would also cover programs not built with the BSP flags. The
  BSP spec is easier to revert and does not need a toolchain rebuild, which
  is why this patch does it there. RTEMS maintainers may prefer one or the
  other.
- Alternatively the RSB could carry the binutils fix (#47 A-F, about 13
  patches with provisional relocation numbers) instead of this workaround.
- The commit message links the fix in progress to the public
  microblaze-testsuite repo on GitHub; RTEMS may prefer a binutils
  mailing-list or Bugzilla link once one exists.
- `abi.yml` keeps its 2021 OAR copyright line; reviewers may want a
  copyright line added for the change.
