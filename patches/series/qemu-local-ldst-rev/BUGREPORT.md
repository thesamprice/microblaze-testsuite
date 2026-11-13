# Bug report draft for qemu-devel (for a human to review and send)

Written with AI assistance from a debugging session; it contains no
patch.  Check it, edit it into your own words if you like, and send it
yourself.  Suggested recipients (from `scripts/get_maintainer.pl -f
target/microblaze/translate.c`):

    To: qemu-devel@nongnu.org
    Cc: "Edgar E. Iglesias" <edgar.iglesias@gmail.com>,
        Richard Henderson <richard.henderson@linaro.org>,
        Luc Michel <luc.michel@amd.com>
    Subject: target/microblaze: lbur/lhur/sbr/shr modify their base register since v10.1

---

Hi,

Since commit 36a9529e60 ("target/microblaze: Simplify
compute_ldst_addr_type{a,b}"), first in v10.1.0, the reversed sub-word
loads and stores lbur, lhur, sbr and shr modify the guest's base
register when the other address operand is r0.  It is still present in
v10.2.4 and in master as of 9d7d057a55.

do_load() and do_store() in target/microblaze/translate.c swizzle the
address in place for a reversed access:

    if (size < MO_32) {
        tcg_gen_xori_i32(addr, addr, 3 - size);
    }

Since 36a9529e60, compute_ldst_addr_typea() returns cpu_R[ra] or
cpu_R[rb] itself when the other operand is r0, and a TCG constant when
both are, so that XOR now lands in the guest register.

Reproducer (bare metal, petalogix-s3adsp1800, big endian; the same
happens on qemu-system-microblazeel):

    _start: addik r5, r0, 0x90001000
            lbur  r3, r5, r0
            # r5 is now 0x90001003

With r5 = 0x90001000 before the instruction, r5 afterwards is:

    lbur r3, r5, r0    0x90001003
    lbur r3, r0, r5    0x90001003
    lhur r3, r5, r0    0x90001002
    sbr  r3, r5, r0    0x90001003
    shr  r3, r0, r5    0x90001002
    lwr  r3, r5, r0    0x90001000  (word accesses are not swizzled)

Before 36a9529e60, compute_ldst_addr_typea() always returned a new
temporary, so the XOR was harmless.

I understand Luc Michel already has a fix for this in AMD's tree
(github.com/Xilinx/qemu commit 6f493e0ede, "target/microblaze/translate:
fix reversed load/store translation", with his Signed-off-by).  Luc,
would you be able to post it?  I am happy to test it and reply with a
Tested-by.

Thanks,
<name>
