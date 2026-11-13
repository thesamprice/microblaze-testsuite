# Michal Simek's 2020 arch/microblaze patches (built-in initramfs > 32 MB)

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#63.

## What is here

The mboxes are the LKML postings, fetched from lore.kernel.org with
`https://lore.kernel.org/all/<msgid>/t.mbox.gz` on 2026-11-13.  The `raw/` directory has
the thread mboxes as downloaded; the files at top level are the patch mails split out
with `git mailsplit`.

| linux-xlnx | file | posted | Message-Id |
|---|---|---|---|
| `088a03b5633e` | `088a03b5-microblaze-Swap-location-of-bss-and-INIT_RAM_FS.mbox` | 2020-11-25 | `60bfb194e0b9c2f80b21cf5e4b9548039c0c6eec.1606304684.git.michal.simek@xilinx.com` |
| `1a92198efa5a` | `1a92198e-microblaze-Change-TLB-mapping-and-free-space-allocation.mbox` | 2020-11-25 | `af2fd524563dc374d3ecc7ac75af1b23f64cb739.1606304612.git.michal.simek@xilinx.com` |
| `4ff53559c33b` | `4ff53559-microblaze-Fix-message-about-compiled-in-FDT-location.mbox` | 2020-01-08 | `1a11e5cd73f6eb999f78981953d39773eb154040.1578492778.git.michal.simek@xilinx.com` |

All three are `From: Michal Simek <michal.simek@xilinx.com>` with his
`Signed-off-by: Michal Simek <michal.simek@xilinx.com>`.  The two November 2020 patches have
no replies on lore.  The FDT-message patch has one reply, from Michal himself on
2020-02-04: "Applied." (`4ff53559-reply-Applied-2020-02-04.eml`).  It is not in mainline
anyway: `arch/microblaze/kernel/setup.c` at `7e1392a42ea2` still prints
`"Compiled-in FDT at %p\n"`, and no mainline commit has the subject.  It was presumably
applied to his microblaze branch and dropped before a pull request.

**Order.** The two November patches were sent as separate mails, not as a numbered
series, and the TLB patch has the earlier timestamp.  They must still be applied Swap
first: the TLB patch's context contains `extern char __initramfs_end[];`, which the Swap
patch adds, and the Swap message says "The follow up patch will explain reasons behind
it."  linux-xlnx carries them in that order too (4ff53559, 088a03b5, 1a92198e).

## Do they still apply to mainline?

Base: mainline `7e1392a42ea2` (v7.4-rc2-470, "Merge tag 'net-7.4-rc3'", 2026-11-12).
None of the three is in mainline (searched `git log --grep` on arch/microblaze by subject).

- `4ff53559` FDT message: `git apply --check` passes.  Applies unchanged.
- `088a03b5` Swap bss/INIT_RAM_FS: does **not** apply.  Two hunks fail on context only:
  - `asm/sections.h`: the trailing `# endif /* !__ASSEMBLY__ */` is now
    `/* !__ASSEMBLER__ */` (mainline `438f7cd41765`, 2025).
  - `mm/init.c` `mmu_init()`: the `if (!memblock.reserved.cnt)` check that followed the
    variable declarations is gone; the function now starts with the
    "Memory must be greater than 4MB" check.
  The `vmlinux.lds.S` hunks and the second `init.c` hunk apply.
  `git am -3` cannot fall back to a 3-way merge here: the 2020 preimage blobs
  (`a9311ad84a67`, `7129a20881ea`) are not reachable in my partial clone, and git
  reports "sha1 information is lacking or useless".
- `1a92198e` TLB mapping: does not apply alone (needs the Swap patch's context); applies
  cleanly, with line offsets only, on top of the rebased Swap patch.

## Rebased series

`patches/series/linux-simek-2020-rebased/`: the three patches on `7e1392a42ea2`, in the
order Swap, TLB, FDT (the FDT patch is independent of the other two).

The rebase changed only context.  I applied each mbox with `git am --reject`, re-added
the two rejected one-line additions by hand at the same places in today's code
(`extern char __initramfs_end[];` after `__ivt_end[]`, and
`phys_addr_t __maybe_unused size;` after `unsigned int kstart, ksize;`), and continued the
`git am`.  Author, author date, subject, body and `Signed-off-by` are Michal's, unchanged.
I added no tags.  If the human re-posts these, the kernel convention for a rebase by
someone else is a bracketed note above their own Signed-off-by, e.g.
`[sam: rebased onto v7.4-rc2, context only]`.

Cross-check: `git patch-id --stable` of each rebased patch equals that of the
corresponding linux-xlnx commit (fetched read-only from GitHub as `.patch`):

| linux-xlnx | patch-id | rebased commit | patch-id |
|---|---|---|---|
| `088a03b5633e` | `afe58ac69b30` | `edf8dbd18ec2` | `afe58ac69b30` |
| `1a92198efa5a` | `43ae7b77fe69` | `1a1950e84658` | `43ae7b77fe69` |
| `4ff53559c33b` | `e658c19bb37c` | `488383d26bdd` | `e658c19bb37c` |

So AMD's rebase onto 6.18 made the same context changes and no others.

## Testing

See the "Results" section below.

## Results

Toolchain: kernel.org crosstool gcc 15.3.0 microblaze-linux, binutils 2.47, in a Debian
trixie container.

**Build test, microblaze `defconfig`** (big-endian mmu_defconfig):

| tree | result |
|---|---|
| mainline `7e1392a42ea2` | make rc=0, 0 warnings; vmlinux text 7786506, data 2345108, bss 367180 |
| + rebased series (`488383d26bdd`) | make rc=0, 0 warnings; vmlinux text 7786506, data 2345140, bss 367180 |

**Boot test of the >32 MB case**, QEMU 10.2.4 `qemu-system-microblazeel -M petalogix-ml605
-m 256`, little-endian kernel at `CONFIG_KERNEL_BASE_ADDR=0x50000000`, HIGHMEM with
`CONFIG_LOWMEM_SIZE=0x08000000`, built-in uncompressed initramfs
(`CONFIG_INITRAMFS_SOURCE`, `INITRAMFS_COMPRESSION_NONE`) holding a 2 KB static /init
and a 40 MiB random file:

- mainline `7e1392a42ea2`: linux.bin 52395612 bytes, `__bss_start` = `0xc31f8000`.
  No console output at all.  The first exception in `-d int` is
  `INT: MMU at pc=c071bd78 ... ear=c31f8000`: the bss clear in early boot faults on
  the first bss page, which lies beyond the two 16 MB TLB entries head.S sets up
  (0xc0000000-0xc2000000).  The CPU then runs off into unmapped memory.  This is the
  failure the patches describe.
- with the rebased series (`488383d26bdd`): linux.bin 53750788 bytes (1355176 larger,
  the bss hole plus the 1 MB pad, as Michal's message says).  Boots to
  "Run /init as init process" and the init's "TEST: init start"; `Memory: 191464K/262144K
  available ... 53756K reserved ... 131072K highmem`.

The FDT-message patch is not exercised by these runs (QEMU passes a DTB, so the kernel
prints "FDT at 0x53344c04", not the compiled-in message).  checkpatch.pl --strict on the
rebased patches: 0/0/0 for 1/3 and 2/3; 3/3 has one warning, "Prefer 'unsigned int' to
bare use of 'unsigned'" on the `(unsigned)&_fdt_start` cast, unchanged from the 2020
posting.

Logs: work/build/linux-new/{mainline-defconfig,simek-on-mainline,irfs-mainline,irfs-simek}/.

## Not tested / open

- No real hardware.  Big-endian boot not tried (only the build).
- The issue body expects review to ask for the `0x100000` pad to be computed from
  `CONFIG_LOWMEM_SIZE`; the rebased patch keeps Michal's constant.  With the default
  768 MB lowmem, the PTE pages need 0xc0000, so 1 MB leaves 256 KB of slack.
- `defconfig` change `dd1978d4ec7c` (LL_TEMAC removal) is not included; the issue says
  only that half is left and it is not one of the three requested.
- Suggested reply to Michal (not sent): a Tested-by on the two Nov 2020 threads with the
  QEMU result above, noting they need the context rebase in
  patches/series/linux-simek-2020-rebased/, and that the FDT patch he marked "Applied"
  on 2020-02-04 never reached mainline.
