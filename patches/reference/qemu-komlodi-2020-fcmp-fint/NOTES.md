# Joe Komlodi's 2020 fcmp/fint fixes: what could be fetched

Issue #60 (thesamprice/rtems-microblaze-linker-relaxation-bug).

## Requested

The qemu-devel posting with Message-Id
`<1590119023-38722-2-git-send-email-komlodi@xilinx.com>` (and its
thread), as an mbox.

## Result: no public posting found

I could not find that message in any public qemu-devel archive.

| source | result (2026-11-12) |
|---|---|
| lore.kernel.org `/qemu-devel/<id>/t.mbox.gz`, ids -0 to -3 | HTTP 404 with curl's default user agent; with a browser user agent lore served its anti-bot page, and later answered 403 to everything (rate limit). Not conclusive. |
| patchew.org `/QEMU/<id>/` | 404, but patchew also gave 404 for Komlodi's 1589219346 posting, which *is* on the list, so this proves nothing. |
| lists.gnu.org mbox archive, qemu-devel 2020-05 (8682 messages) and 2020-06 (10234 messages) | **no** message with `1590119023` in any header, and no "fcmp_le" or "Fix fint" anywhere. |

The May 2020 archive does hold Komlodi's other target/microblaze
postings, including two sent 19 minutes later on the same evening:

- `<1589216751-106038-*>` [PATCH v1 0/4] target/microblaze: Add dynamic GDB XML ...
- `<1589219346-106769-*>` [PATCH v1 0/1] target/microblaze: Fix FPU2 instruction check
- `<1589393329-223076-*>` [PATCH V2 0/4] target/microblaze: Add GDB XML ...
- `<1590120134-39470-*>` [PATCH v1 0/1] target/microblaze: Add GDB XML files (Thu, 21 May 2020 21:02 -0700)

The fcmp/fint commits are dated 20:43:42/43 -0700 the same evening, so
their absence is not a gap in the archive's date range.  The
Message-Ids come from the Xilinx QEMU commits themselves, which carry
`Reviewed-by` and `Signed-off-by: Edgar E. Iglesias <edgar.iglesias@xilinx.com>`
plus a `Message-Id:` trailer, as `git am` from a mail would leave.  My
reading: the series was mailed to Edgar (or an internal Xilinx list)
and applied to Xilinx's tree, but never reached qemu-devel.  I have not
confirmed that with anyone.

**This contradicts the premise in issue #60** that "the DCO is already
on the list, so Edgar can apply the 2020 posting".  If the posting is
not public, the route is: ask AMD (Edgar, Luc Michel, or Komlodi if
still reachable) to post the two commits to qemu-devel.  Anyone can
point at the public Xilinx commits, which carry Komlodi's Signed-off-by.

## What is here

- `xilinx-ac8e7d0b77-fcmp.patch`: github.com/Xilinx/qemu commit
  ac8e7d0b77b2, "target/microblaze: Fix fcmp_le and fcmp_ge", as
  served by the GitHub API (`Accept: application/vnd.github.patch`).
  Message-Id trailer `<1590119023-38722-2-...>`.
- `xilinx-82a2b73d73-fint.patch`: commit 82a2b73d7348, "target/microblaze:
  Fix fint so it rounds towards zero", Message-Id `<1590119023-38722-3-...>`.

Both apply cleanly (`git apply --check`, with offsets) to
target/microblaze/op_helper.c of upstream master 9d7d057a55.

## A difference worth raising with AMD

Komlodi's fcmp.ge is `!float32_lt(fb, fa)`, which returns 1 when either
operand is a NaN.  UG984 Table 104 gives 0 for unordered operands, for
fcmp.ge as for fcmp.le.  I built it (test-only branch
`test-komlodi-ge` in work/src/qemu-new) and ran
`patches/series/qemu-local-fpu/test/run.sh`: check 9 (`fcmp.ge` with
rB = NaN) fails, exit status 9 for big and little endian, and the C
test fails at check 5 (`ge(NaN, 1.0)`).  Our local fix uses
`float32_le(fa, fb)`, which passes.  Not verified on hardware.
