# rsb-microblaze-default-toolchain

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#15 (uses the
audit of #14). For: devel@rtems.org / GitLab MR against
rtems/tools/rtems-source-builder.

Base: RSB `origin/main` 74fffa09a3df68b7e6cacabbde243ea7828edb34
(fetched 2026-11-12). Branch `rsb-new-mb-default` (worktree
`work/src/rtems-new-rsb`). One patch:
`7, edge, next: Use mainline tools for microblaze`.

## What it does

- `rtems/config/{7,next,edge}/rtems-microblaze.bset`: drop the
  `rtems-xilinx-binutils-2.36` pin (use each set's default: 2.47 for 7 and
  next, the `rtems-binutils-head` pin 8de9be5a for edge) and the stale
  "not upstream" comment; GCC from a new per-set config.
- `rtems/config/tools/rtems-microblaze-gcc-{15.2,15.3,head}-newlib-head.cfg`:
  `%include` the set's default GCC config and `%patch add`:
  - `__USE_INIT_FINI__` (RTEMS ticket attachment already used by the Xilinx
    cfg; upstream on GCC master as 271186ef4643, Joel, 2026-09-04)
  - crti.S `_init`/`_fini` (RTEMS attachment, not upstream)
  - `__ELF__` (RTEMS attachment, not upstream; needed by rtems-libbsd per RSB
    commit 54a0428)
  - moddi3.S fix: 15.2/15.3 use GCC gitweb patch of 382046ec124a
    (releases/gcc-15 backport), head uses 3a721dc02388 (master). Neither is in
    15.3.0 (checked: 15.3.0 moddi3.S has no `__MICROBLAZEEL__`).
  - 15.2 only: 84e2023455a0 (PR target/118280, atomic CAS side effects and
    result + atomic_test_and_set). 15.3.0, releases/gcc-15, master and the
    edge pin d440550c already contain it (checked `UNSPECV_CAS_BOOL` in
    sync.md); 15.2.0 does not. This covers Xilinx 0008/0009 from upstream.
- Xilinx GCC 0001-0007 (testsuite), 0010 (-msmall-divides crash), 0011/0012
  (optimizations) and 0013 (replaced by the upstream moddi3 fix) are dropped.
  No Xilinx code is copied; only upstream GCC commits and the existing RTEMS
  attachments are referenced.
- The rtems-xilinx-*.cfg files are left in place, now unused (a follow-up
  could delete them).

Hashes: base64 sha512 of the files RSB downloaded (gitweb `a=patch` output
was byte-identical across fetches). The gitweb URLs work in RSB (the
dl.rtems.org cache 404s first, then RSB falls back to the URL). Reviewers may
prefer the four GCC patches uploaded to gitlab.rtems.org like other RSB
patches, in case gitweb output changes.

## Testing (exact)

**7/rtems-microblaze built** natively on arm64 macOS (Homebrew python 3.14 on
PATH for gdb), `sb-set-builder --prefix=work/build/rtems-new/rsb/install`,
under caffeinate: 2 h 44 min on a host at load 50-220. Result: GCC 15.2.0,
binutils 2.47, gdb 17.2, newlib 7d4336cf. All five GCC patches applied (log:
rtems.h x2, crti.S, moddi3.S, the five files of 84e2023455a0). Checked:
`__USE_INIT_FINI__`, `__ELF__`, `__rtems__` predefined; `crti.o` defines
`_init` and `_fini`.

**The BSP built with it**: RTEMS origin/main 53d56d9494, petalogix_s3adsp1800,
BUILD_SPTESTS + BUILD_SAMPLES, 0 warnings. QEMU (upstream
petalogix-s3adsp1800, qemu-system-microblazeel), 235 programs:

| tools | pass | fail | timeout |
|---|---|---|---|
| RTEMS 7 (GCC 12.4.1, Xilinx 2.36), same tree | 220 | 7 | 8 |
| this patch (GCC 15.2, binutils 2.47) | 231 | 2 | 2 |
| this patch + CFI series (probe: no CFI with 2.47) | 230 | 4 | 1 |

The RTEMS 7 row was run at higher host load (more timing timeouts).
Non-passing with this patch: spcpucounter01, spfatal26 (also fail with the
old tools), spfatal12 (passes on rerun), **cdtest (reproducible hang)**.

**Regression: samples/cdtest hangs** after the first caught C++ exception
(old tools: passes). Rebuilt the samples with `-Wl,--no-relax` in ABI_FLAGS:
cdtest passes. So linker relaxation breaks C++ exception unwinding with
binutils 2.47 (GCC's rtems.h LINK_SPEC passes `-relax`). The same hang also
appeared with GCC 12.4.1 + binutils master with the patches/binutils series
as `-B` as/ld, so it is not simply fixed by that series either; root cause
not investigated. This should be resolved (or the bset carry a binutils fix)
before the patch is merged; spatomic01, spcxx01, iostream pass.


`--dry-run` of `next/rtems-microblaze` and `edge/rtems-microblaze` parses and
resolves packages (gcc-15.3.0 + binutils-2.47; gcc-d440550c +
binutils-8de9be5a). They were **not built**. Patch application to the edge
pin was checked only with `patch --dry-run` against the four affected files
fetched from gitweb at d440550c (rtems.h, crti.S, moddi3.S): all apply.
For 15.3, application was not checked separately (same files as 15.2 except
for the atomic change, which 15.3 already has).

## Not tested / open

- next and edge builds; rtems-libbsd with the new toolchain (the reason for
  `__ELF__`); kcu105 BSPs (need Xilinx QEMU); C++ beyond cdtest.
- The relaxation fix (a639e0adaf2) is not in 2.47; this patch does not carry
  it. Issue #15 notes it could be added as an RSB `%patch` on the binutils
  config; not done.
- Joel Sherrill's view on the GCC move (issue #15 suggests checking with
  him) has not been sought.
- The build was run from the worktree before the commit was made, so the
  tools report `RSB 74fffa09a3df-modified`; the committed configs are
  byte-identical to what was built (only the commit message changed later).
- First build attempt was stopped and restarted after adding 84e2023455a0;
  the numbers above are from the restarted build.
