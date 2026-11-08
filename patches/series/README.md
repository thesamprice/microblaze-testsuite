# Patch series for upstream

Each directory here is a patch series as it will be mailed upstream: a
`0000-cover-letter.txt` and the `git format-patch` output. The Makefile
does not apply them. A series the build should use is also copied into
`patches/<component>/`.

| series | for | status |
|---|---|---|
| `binutils-microblaze-opcodes` | binutils@sourceware.org | seven patches against binutils master `1b10c36dfd4`, not yet sent. Fixes the `bslli`/`bsrai`/`bsrli` decoding, `wdc.ext.clear`, the `mbar` pseudo-instruction aliases and the zero word, comments the `mbar` forms that enter a sleep mode, removes the undocumented `pcmpbc`, and adds a test of every instruction whose expected encodings were checked against QEMU and UG984. Issues #40 to #44 in thesamprice/rtems-microblaze-linker-relaxation-bug |

Add `Signed-off-by:` before sending.
