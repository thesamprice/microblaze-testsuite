# linux-axienet-highmem

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#64.

Base: net-next `main` at `573af8015529` ("Merge git://.../netdev/net", fetched
2026-11-13).  The only axienet change in net-next beyond mainline `7e1392a42ea2` is
`e281e85235cf` (dmaengine_desc_set_callback), which does not touch the code changed here.
Target tree: net-next (`[PATCH net-next]`), not net: see "Is it a bug fix?" below.

## What I found in mainline first

- Legacy TX path (`axienet_start_xmit()`): still `dma_map_single(lp->dev,
  skb_frag_address(frag), ...)` for every fragment.  Not fixed.
- dmaengine TX path (`axienet_start_xmit_dmaengine()`): maps the whole skb with
  `skb_to_sgvec()` + `dma_map_sg()`, which works on page/offset and handles highmem.
  Nothing to fix there.
- **The driver does not set `NETIF_F_HIGHDMA`** (nor does linux-xlnx's, checked on
  `xlnx_rebase_v6.18` and `master`).  So `harmonize_features()` in net/core/dev.c
  clears `NETIF_F_SG` for any skb with a highmem fragment (`illegal_highdma()`), and
  `validate_xmit_skb()` linearises it.  A highmem fragment therefore never reaches the
  driver in mainline, and the `skb_frag_address()` NULL is unreachable.  The cost is a
  copy of every such skb.  My QEMU run of unpatched net-next confirms it: 8 MiB of
  tmpfs pages sent with sendfile(), 0 fragments reached `axienet_start_xmit()`, file
  intact.
- AMD's e040d66052c0 (read only, not copied) converts the legacy path to
  `skb_frag_dma_map()` and adds a per-descriptor field recording the mapping type, but
  does not set `NETIF_F_HIGHDMA` either.  On its own it changes which unmap call runs but
  cannot change what the driver is given.  Whatever AMD observed on MicroBlaze with 1 GB
  must have come through some other route, or from a tree that set the flag; I could not
  reproduce a failure without setting it.

So the useful upstream change is a pair: make the legacy path highmem-safe, then set
`NETIF_F_HIGHDMA` so the core stops linearising.  Patch 2 alone is a crash (shown below),
which is why the order matters.

## Patches

1. `net: axienet: map TX fragments with skb_frag_dma_map()`: fragments are mapped
   with `skb_frag_dma_map()` (the idiom used by most drivers in drivers/net/ethernet,
   120 call sites at the base commit) and unmapped with `dma_unmap_page()`.  A new
   helper `axienet_unmap_tx_bd()` chooses `dma_unmap_single()` vs `dma_unmap_page()` by
   `XAXIDMA_BD_CTRL_TXSOF_MASK`, which only the first descriptor of a packet (the one
   holding `skb->data`) has.  That avoids a new field in `struct axidma_bd`, which is
   64-byte aligned and on 64-bit would have grown to 128 bytes if a field went after the
   `skb` pointer.  `axienet_free_tx_chain()` and `axienet_free_tx_bufs()` use the helper;
   the now unused `phys` local in `axienet_free_tx_chain()` is removed.  No behaviour
   change on its own (dma-direct handles both unmaps the same way, and with the flag
   unset no highmem fragment arrives).
2. `net: axienet: advertise NETIF_F_HIGHDMA`: one line in probe,
   `ndev->features = NETIF_F_SG | NETIF_F_HIGHDMA;`.

Precedent: `skb_frag_dma_map()` / `dma_unmap_page()` for fragments is the common pattern
(e.g. macb's `mapped_as_page`, stmmac's `map_as_page`; both store a flag, I used the SOF
bit instead because axienet already has it).  The mv643xx_eth commit AMD cites
(9e91141, "Fix highmem support in non-TSO egress path") is the same fix in another
driver; I read only its subject.

## Is it a bug fix?

Not in mainline: nothing is broken until patch 2 sets the flag.  I therefore did not add
a `Fixes:` tag or `Cc: stable`, and aimed at net-next.  The gain is avoiding a copy of
highmem skbs on 32-bit HIGHMEM systems.  I did not measure throughput.

## Testing (all numbers from my runs)

Toolchain: kernel.org crosstool gcc 15.3.0 microblaze-linux (arm64 host build), in a
Debian trixie container (Docker Desktop, arm64).  The macOS volume is case-insensitive,
so builds use `git archive` of the commit into a case-sensitive Docker volume.

Builds:
- microblaze, runtime config (below: defconfig + little endian + HIGHMEM +
  `XILINX_AXI_EMAC=y` + 8250 console + IP_PNP + DMA_API_DEBUG) of the series with a
  debug counter: make rc=0, no warnings or errors.
- arm64 `allmodconfig` (COMPILE_TEST=y, `XILINX_AXI_EMAC=m`), native gcc 14.2.0,
  `make W=1 drivers/net/ethernet/xilinx/` on `6bfa6b3b9e84` (the series head): rc=0,
  0 warnings.  Log: work/build/linux-new/arm64-axienet/.
- microblaze plain `defconfig` already has `XILINX_AXI_EMAC=y` at this base (mainline
  `6b125c73aaa0`); the HIGHMEM build above covers it with HIGHMEM on.
- `scripts/checkpatch.pl --strict --codespell`: no code findings.  It reports only the
  missing Signed-off-by (by design, the human adds it) and "Non-standard signature:
  Assisted-by:" (this checkpatch does not know the tag).

Runtime, QEMU 10.2.4 `qemu-system-microblazeel -M petalogix-ml605 -m 256` (legacy
axistream DMA path):
- Kernel: `CONFIG_KERNEL_BASE_ADDR=0x50000000`, `CONFIG_LOWMEM_SIZE=0x08000000`, so
  `HighMem [mem 0x58000000-0x5fffffff]`, 131072 kB highmem.  `CONFIG_CMDLINE_FORCE` off.
- Device tree: QEMU's pc-bios/dtb/petalogix-ml605.dts with `xlnx,txcsum = <0x01>`
  (partial TX checksum, which QEMU's axienet model implements).  With txcsum 0 the
  device has no checksum feature and the core drops NETIF_F_SG, so no fragments at all.
- Userspace: a 2 KB static /init (no libc; work/build/linux-new/rt/init.c) writes an
  8 MiB pseudo-random file to the tmpfs root (HighFree 131000 kB -> 122800 kB), connects
  to 10.0.2.2:47123 through `-nic user` and sendfile()s it; a host script compares it
  with the expected bytes.
- A test-only counter in `axienet_start_xmit()` (not in the series) printed how many
  fragments arrived and how many were in highmem pages.

| kernel | result |
|---|---|
| net-next base | 8388608 bytes, 0 mismatching 4K blocks, sha256 match; 0 fragments reached the driver |
| patch 2 only (HIGHDMA without the mapping fix) | `axienet-test: frags 1 highmem 1`, then `DMA-API: xilinx_axienet 82780000.axi-ethernet: device driver maps memory from invalid area [addr=00000000] [len=1460]`, `Oops: Exception in kernel mode, sig: 11` in `axienet_start_xmit+0x234`, panic |
| patches 1+2 | 8388608 bytes, 0 mismatching blocks, sha256 match; counter reached `frags 7000 highmem 7000` (5769 TX packets, mostly 1 or 2 fragments each); no DMA-API reports |

Logs: work/build/linux-new/rt-{base,p2only,both}/console.log.

## Not tested

- Real hardware, and the dmaengine TX path (patch 2 turns highmem on for it too; it
  relies on `skb_to_sgvec()`/`dma_map_sg()`, which I did not exercise).
- 64-bit DMA (`XAE_FEATURE_DMA_64BIT`) configurations.
- Patch 1 alone at runtime (expected to behave like the base: no fragments arrive).
- Throughput.

## Open questions

- Reviewers may prefer an explicit per-descriptor flag (as macb/stmmac and AMD's patch
  do) over keying the unmap on TXSOF.  TXSOF is set only by `axienet_start_xmit()` on the
  descriptor holding `skb->data` and the hardware does not write `cntrl`, so I think
  it is sound, but it couples the unmap choice to a hardware bit.
- `dma_unmap_single()` and `dma_unmap_page()` are the same function in dma-direct today,
  and dma-debug records both as type "phy", so a reviewer may ask whether the
  distinction is worth a helper at all.  I kept it because the DMA API documentation
  pairs map and unmap calls.
- Patch 1's subject is 54 characters; with the `net-next` prefix the generated
  Subject header folds onto two lines (RFC 5322 folding, harmless to `git am`).
- Trailer form: this repo's rule is `Assisted-by: Claude <noreply@anthropic.com>`.
  Documentation/process/coding-assistants.rst at this base says AI agents must not
  add Signed-off-by and must disclose, but gives no tag syntax; the five microblaze
  signal patches merged for v7.4-rc1 used `Assisted-by: Claude:claude-opus-5`.
  The human should pick one before sending.
- Recipients (scripts/get_maintainer.pl): Radhey Shyam Pandey (maintainer), Andrew
  Lunn, David S. Miller, Eric Dumazet, Jakub Kicinski, Paolo Abeni, Michal Simek,
  netdev@vger.kernel.org, linux-arm-kernel, linux-kernel.  Cc Ravikanth Tuniki and
  Appana Durga Kedareswara Rao, authors of e040d66052c0, since this overlaps their patch.
