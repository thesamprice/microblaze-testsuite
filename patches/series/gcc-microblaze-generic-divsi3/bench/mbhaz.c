/* Count 5-stage data-hazard stalls per UG984 "Five Stage Pipeline":
   consumer in OF needs result of EX-stage producer (load, barrel, mul, div) => 1-2 cycles;
   needs result of MEM-stage producer (load, mul) i.e. 2 back => 1 cycle.  */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <glib.h>
#include <qemu-plugin.h>
QEMU_PLUGIN_EXPORT int qemu_plugin_version = QEMU_PLUGIN_VERSION;
static uint64_t lo, hi, n_ex1, n_ex2, n_mem, n_bs1, n_div0, insns;
struct ii { uint32_t reads; int wr; int kind; uint32_t w; }; /* kind 0 none,1 load,2 mul,3 bs,4 div */
static int p1_wr = 0, p1_kind = 0, p2_wr = 0, p2_kind = 0;
static struct ii *decode(uint32_t w) {
  struct ii *d = g_new0(struct ii, 1);
  unsigned op = w >> 26, rd = (w >> 21) & 31, ra = (w >> 16) & 31, rb = (w >> 11) & 31;
  bool tb = op & 8; d->w = w;
  uint32_t r = 0; int wr = rd;
  switch (op) {
  case 0x2c: wr = 0; break;                       /* imm */
  case 0x2d: r = 1u << ra; wr = 0; break;          /* rtsd */
  case 0x26: r = 1u << rb; wr = ((w >> 18) & 1) ? rd : 0; break;
  case 0x2e: wr = ((w >> 18) & 1) ? rd : 0; break;
  case 0x27: r = 1u << ra | 1u << rb; wr = 0; break;
  case 0x2f: r = 1u << ra; wr = 0; break;
  case 0x24: r = 1u << ra; break;
  case 0x34: case 0x35: case 0x36: case 0x3c: case 0x3d: case 0x3e:
    r = 1u << ra | 1u << rd | (tb ? 0 : 1u << rb); wr = 0; break;
  default: r = 1u << ra | (tb ? 0 : 1u << rb); break;
  }
  r &= ~1u; d->reads = r; d->wr = wr;
  switch (op) {
  case 0x30: case 0x31: case 0x32: case 0x38: case 0x39: case 0x3a: d->kind = 1; break;
  case 0x10: case 0x18: d->kind = 2; break;
  case 0x11: case 0x19: d->kind = 3; break;
  case 0x12: d->kind = 4; break;
  }
  return d;
}
static void ex_in(unsigned int cpu, void *u) {
  struct ii *d = u; insns++;
  bool s1 = p1_wr && (d->reads >> p1_wr & 1) && p1_kind;
  if (s1) { if (p1_kind == 3) n_bs1++; else if (p1_kind == 4) n_ex1++; else n_ex2++; }
  else if (p2_wr && (d->reads >> p2_wr & 1) && (p2_kind == 1 || p2_kind == 2)) n_mem++;
  p2_wr = p1_wr; p2_kind = p1_kind; p1_wr = d->wr; p1_kind = d->kind;
}
static void ex_out(unsigned int cpu, void *u) { p1_wr = p2_wr = 0; }
static void tb_trans(qemu_plugin_id_t id, struct qemu_plugin_tb *tb) {
  size_t n = qemu_plugin_tb_n_insns(tb);
  for (size_t i = 0; i < n; i++) {
    struct qemu_plugin_insn *insn = qemu_plugin_tb_get_insn(tb, i);
    uint64_t pc = qemu_plugin_insn_vaddr(insn);
    if (pc >= lo && pc < hi) {
      uint8_t b[4]; qemu_plugin_insn_data(insn, b, 4);
      uint32_t w = (uint32_t)b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3];
      qemu_plugin_register_vcpu_insn_exec_cb(insn, ex_in, QEMU_PLUGIN_CB_NO_REGS, decode(w));
    } else qemu_plugin_register_vcpu_insn_exec_cb(insn, ex_out, QEMU_PLUGIN_CB_NO_REGS, NULL);
  }
}
static void at_exit(qemu_plugin_id_t id, void *p) {
  char s[256];
  snprintf(s, sizeof s, "MBHAZ insns=%llu ex1_loadmul=%llu ex1_bs=%llu ex1_div=%llu mem2=%llu lo=%llu hi=%llu\n",
    (unsigned long long)insns, (unsigned long long)n_ex2, (unsigned long long)n_bs1, (unsigned long long)n_ex1,
    (unsigned long long)n_mem, (unsigned long long)(n_ex2 + n_bs1 + n_ex1 + n_mem),
    (unsigned long long)(2 * n_ex2 + n_bs1 + 2 * n_ex1 + n_mem));
  qemu_plugin_outs(s);
}
QEMU_PLUGIN_EXPORT int qemu_plugin_install(qemu_plugin_id_t id, const qemu_info_t *info, int argc, char **argv) {
  for (int i = 0; i < argc; i++) {
    if (!strncmp(argv[i], "lo=", 3)) lo = strtoull(argv[i] + 3, NULL, 0);
    else if (!strncmp(argv[i], "hi=", 3)) hi = strtoull(argv[i] + 3, NULL, 0);
  }
  qemu_plugin_register_vcpu_tb_trans_cb(id, tb_trans);
  qemu_plugin_register_atexit_cb(id, at_exit, NULL);
  return 0;
}
