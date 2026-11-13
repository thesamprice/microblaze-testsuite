# linux-6.18-stable-signal-backports

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#65 (kernel side of #7 and #8).

Base: stable `linux-6.18.y` at `1cdda838e847` ("Linux 6.18.63", committed 2026-11-10),
fetched from git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git.

## Status: four of the five are already in 6.18.63

The issue was written on 2026-11-09 against 6.18.62.  Sasha Levin queued the four
`Cc: stable` commits and they shipped in v6.18.63 (2026-11-10).  `git patch-id --stable`
of each stable commit equals that of its mainline original, so they went in unmodified:

| mainline | subject | 6.18.y commit | patch-id |
|---|---|---|---|
| `c5947d28c209` | microblaze: reserve the ABI argument-home area in the signal frame | `ba4121a804ad` | `0574ceb08751` both |
| `da6829138a39` | microblaze: don't clobber r3/r4 restored by rt_sigreturn | `87f78edf4b3d` | `3d1d02903335` both |
| `c35d40a3efd2` | microblaze: restore the ABI argument home area below pt_regs (PTO) | `8237cd3e2fc2` | `bfb58423b29e` both |
| `ca35dd21a5f8` | microblaze: preserve the MSR carry flags across signals | `1f8722a7053f` | `372b117eb9d5` both |

The entry.S commit `c35d40a3efd2` did not need the hand adjustment the issue expected; it
was applied as is.

The fifth, `730e01d93249` ("microblaze: wire up sigaltstack"), has no `Cc: stable` tag and is
not in 6.18.63.  It is the only patch in this series.

## The patch

`0001-microblaze-wire-up-sigaltstack.patch`: `git cherry-pick -x 730e01d93249` onto
6.18.63.  It applied with no conflict (a one-line change to
`arch/microblaze/kernel/syscalls/syscall.tbl`, syscall 186 `sys_ni_syscall` to
`sys_sigaltstack`).  The `(cherry picked from commit ...)` line from `-x` is kept, and the
`commit <sha1> upstream.` line that stable-kernel-rules.rst Option 3 asks for was added
above the body.  The message is otherwise the upstream one, with the original
Signed-off-by chain (Ramin Moussavi, Michal Simek), Tested-by and Link.  The submitter
adds their own Signed-off-by when sending (stable requires it for Option 3).

## How to submit (Documentation/process/stable-kernel-rules.rst)

The commit is in mainline (v7.4-rc1) and cherry-picks cleanly, so **Option 2** is enough
and is the least work for the stable team: an email to `stable@vger.kernel.org` with

- the subject: `microblaze: wire up sigaltstack`
- the commit ID: `730e01d932496f7bd536fc185d3aab6646dea0f4`
- why: sigaltstack(2) returns ENOSYS on microblaze, the only architecture where it does,
  although the signal code (`get_sigframe()`, `__save_altstack()`,
  `restore_altstack()`) already supports alternate stacks.  Anything that installs a
  SIGSEGV handler on an alternate stack to catch stack overflow fails.  The upstream
  message records the uClibc-ng NPTL tests that fail without it (tst-cancel20/21,
  tst-cancelx20/21, tst-signal6).
- versions: 6.18.y (and older LTS trees if wanted; I did not check 6.12.y or 6.6.y).

**Option 3** (send the patch itself) is the file in this directory: subject
`[PATCH 6.18.y] microblaze: wire up sigaltstack`, first body line
`commit 730e01d932496f7bd536fc185d3aab6646dea0f4 upstream.`, To: stable@vger.kernel.org,
Cc: Michal Simek and the author.

Whether it qualifies is the open question: the rules want "a real bug that bothers
people".  The case for it is that a syscall every other architecture implements returns
ENOSYS, which breaks real programs and libc test suites; the case against is that wiring
up a syscall looks like a feature, and upstream did not tag it for stable.  The stable
team decides; an Option 2 request with the reason above is the honest way to ask.

## linux-xlnx

Checked with the GitHub API on 2026-11-13 (`commits?sha=<branch>&path=arch/microblaze`):
none of the five commits is on `xlnx_rebase_v6.18`, `xlnx_rebase_v6.18_LTS` (6.18.40,
last arch/microblaze change is the v6.18.40 merge of 2026-08-10),
`xlnx_rebase_v6.18_LTS_2026.1_update` (6.18.40), or `master` (6.18.0).  Their most recent
arch/microblaze commits are Michal Simek's 4 downstream commits (see #63) and
`dd1978d4ec7c`.  Merging v6.18.63 into the LTS branch brings in the four stable commits;
`730e01d93249` would need a cherry-pick (it applies cleanly to 6.18.63, and should to
6.18.40 as well, since syscall.tbl did not change in between; I did not try it on 6.18.40).

## Testing

- Build: microblaze `defconfig` of 6.18.63 + this patch, gcc 15.3.0 (kernel.org crosstool
  `arm64-gcc-15.3.0-nolibc-microblaze-linux`) in a Debian trixie container.  Result: see
  "Build results" below.
- Not run: no boot or runtime test of the 6.18 kernel.  The upstream message's test
  (uClibc-ng NPTL on QEMU) was done by the author on mainline, not by me on 6.18.

## Build results

- `make defconfig` (microblaze, mmu_defconfig) + `make -j4` of `41ff908345b3` (6.18.63 +
  this patch): make rc=0, 0 lines matching `warning:`; vmlinux text 7449620, data 2174876,
  bss 362984.  Log: work/build/linux-new/v6.18-sigaltstack/.
