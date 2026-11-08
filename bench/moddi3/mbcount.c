/* QEMU TCG plugin: count the MicroBlaze instructions executed in an address
   range, by class, and the taken branches out of it.

     -plugin ./libmbcount.so,lo=0x...,hi=0x...

   bench/moddi3/run.sh links the routine under test and the libgcc helpers
   it calls at the end of .text and passes their extent, so the counts
   cover __moddi3 and everything it calls, and nothing of the harness.

   A taken branch is counted when the next instruction executed is not the
   one after the last in the range, which also catches the delay-slot
   forms (the slot runs, then control moves) and the return to the
   caller.

   It also estimates clock cycles for two MicroBlaze pipelines, from the
   per-instruction latencies in UG984 (v2026.1, "MicroBlaze Instruction
   Set Architecture"): cyc5 for the five-stage pipeline
   (C_AREA_OPTIMIZED=0) and cyc3 for the three-stage one
   (C_AREA_OPTIMIZED=1).

			   cyc5	cyc3
     idiv, idivu		34	35
     mul, mulh*, muli		 1	 3
     barrel shifts		 1	 2
     loads and stores		 1	 2
     branch not taken		 1	 1
     taken, delay slot		 2	 2	plus the slot's own cycles
     taken, no delay slot	 3	 3
     everything else		 1	 1

   rtsd and the other returns always have a delay slot.  The estimate
   assumes single-cycle local memory, no branch target cache, and no
   stalls for data hazards, which UG984 does not quantify; and idiv by
   zero, which takes 1 cycle, is costed as a full divide.  It is an
   estimate, not a measurement.  max5 and max3 are the most cycles any
   one call took.  */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <glib.h>
#include <qemu-plugin.h>

QEMU_PLUGIN_EXPORT int qemu_plugin_version = QEMU_PLUGIN_VERSION;

enum cls { C_DIV, C_MUL, C_BSHIFT, C_CLZ, C_IMM, C_LOAD, C_STORE,
	   C_BRANCH, C_OTHER, C_N };
static const char *const cls_name[C_N] = {
  "idiv", "mul", "barrel", "clz", "imm", "load", "store", "branch", "other"
};

static uint64_t lo, hi;
static uint64_t count[C_N], taken;
static uint64_t prev;		/* last instruction executed in range, or 0 */

/* Cycles by class for the five- and three-stage pipelines; branches are
   costed when it is known whether they were taken.  */
static const unsigned cyc5_of[C_N] = { 34, 1, 1, 1, 1, 1, 1, 0, 1 };
static const unsigned cyc3_of[C_N] = { 35, 3, 2, 1, 1, 2, 2, 0, 1 };
static uint64_t cyc5, cyc3;

/* The most cycles one call took: each stretch of execution inside the
   range is one call, since the harness runs outside it.  */
static uint64_t call5, call3, max5, max3;

/* The branch whose outcome is still to be seen: its address, whether it
   has a delay slot, and how many more instructions until the one that
   shows whether it was taken.  */
static uint64_t br_pc;
static bool br_delay;
static int br_wait;

/* Per instruction, packed into the callback's udata: the class in bits
   0-3, bit 4 for a branch with a delay slot, the address above bit 8.  */
#define U_DELAY 16

static bool little_endian;

/* By major opcode, the top six bits, as target/microblaze/insns.decode
   has them.  Not by disassembly: QEMU's MicroBlaze disassembler has no
   entry for clz, the swaps or bsefi/bsifi.  */
static enum cls
classify (uint32_t w)
{
  switch (w >> 26)
    {
    case 0x12:			/* idiv, idivu */
      return C_DIV;
    case 0x10: case 0x18:	/* mul, mulh, mulhu, mulhsu; muli */
      return C_MUL;
    case 0x11: case 0x19:	/* bsll, bsra...; bslli, bsrai, bsefi, bsifi */
      return C_BSHIFT;
    case 0x24:			/* sra, src, srl, sext, clz, swap... */
      return (w & 0xffff) == 0x00e0 ? C_CLZ : C_OTHER;
    case 0x2c:
      return C_IMM;
    case 0x30: case 0x31: case 0x32: case 0x38: case 0x39: case 0x3a:
      return C_LOAD;
    case 0x34: case 0x35: case 0x36: case 0x3c: case 0x3d: case 0x3e:
      return C_STORE;
    case 0x26: case 0x27: case 0x2d: case 0x2e: case 0x2f:
      return C_BRANCH;		/* br, bcc, rtsd/rtid..., bri, bcci */
    default:
      return C_OTHER;
    }
}

/* Whether a branch with a delay slot has one, from its encoding.  */
static bool
has_delay_slot (uint32_t w)
{
  switch (w >> 26)
    {
    case 0x26: case 0x2e:	/* br, bri: D is bit 4 of the rA field */
      return (w >> 20) & 1;
    case 0x27: case 0x2f:	/* bcc, bcci: D is bit 4 of the rD field */
      return (w >> 25) & 1;
    case 0x2d:			/* rtsd, rtid, rtbd, rted */
      return true;
    default:
      return false;
    }
}

static void
resolve_branch (bool was_taken)
{
  unsigned c = !was_taken ? 1 : br_delay ? 2 : 3;
  cyc5 += c;
  cyc3 += c;
  br_wait = 0;
}

static void
exec_in (unsigned int cpu, void *udata)
{
  uintptr_t u = (uintptr_t) udata;
  uint64_t pc = u >> 8;
  enum cls c = u & 15;
  if (prev && pc != prev + 4)
    taken++;
  if (br_wait && --br_wait == 0)
    resolve_branch (pc != br_pc + (br_delay ? 8 : 4));
  count[c]++;
  cyc5 += cyc5_of[c];
  cyc3 += cyc3_of[c];
  if (c == C_BRANCH)
    {
      br_pc = pc;
      br_delay = (u & U_DELAY) != 0;
      br_wait = br_delay ? 2 : 1;
    }
  prev = pc;
}

static void
exec_out (unsigned int cpu, void *udata)
{
  if (prev)
    taken++;		/* the return to the harness */
  if (br_wait)
    resolve_branch (true);
  if (prev)
    {
      if (cyc5 - call5 > max5)
	max5 = cyc5 - call5;
      if (cyc3 - call3 > max3)
	max3 = cyc3 - call3;
    }
  call5 = cyc5;
  call3 = cyc3;
  prev = 0;
}

static void
tb_trans (qemu_plugin_id_t id, struct qemu_plugin_tb *tb)
{
  size_t n = qemu_plugin_tb_n_insns (tb);
  for (size_t i = 0; i < n; i++)
    {
      struct qemu_plugin_insn *insn = qemu_plugin_tb_get_insn (tb, i);
      uint64_t pc = qemu_plugin_insn_vaddr (insn);
      if (pc >= lo && pc < hi)
	{
	  uint8_t b[4] = { 0 };
	  qemu_plugin_insn_data (insn, b, sizeof b);
	  uint32_t w = little_endian
	    ? (uint32_t) b[3] << 24 | b[2] << 16 | b[1] << 8 | b[0]
	    : (uint32_t) b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3];
	  uintptr_t u = ((uintptr_t) pc << 8) | classify (w);
	  if (classify (w) == C_BRANCH && has_delay_slot (w))
	    u |= U_DELAY;
	  qemu_plugin_register_vcpu_insn_exec_cb (insn, exec_in,
						  QEMU_PLUGIN_CB_NO_REGS,
						  (void *) u);
	}
      else
	qemu_plugin_register_vcpu_insn_exec_cb (insn, exec_out,
						QEMU_PLUGIN_CB_NO_REGS, NULL);
    }
}

static void
at_exit (qemu_plugin_id_t id, void *p)
{
  GString *s = g_string_new ("MBCOUNT");
  uint64_t total = 0;
  for (int c = 0; c < C_N; c++)
    {
      g_string_append_printf (s, " %s=%" PRIu64, cls_name[c], count[c]);
      total += count[c];
    }
  g_string_append_printf (s, " taken=%" PRIu64 " total=%" PRIu64
			  " cyc5=%" PRIu64 " cyc3=%" PRIu64
			  " max5=%" PRIu64 " max3=%" PRIu64 "\n",
			  taken, total, cyc5, cyc3, max5, max3);
  qemu_plugin_outs (s->str);
  g_string_free (s, TRUE);
}

QEMU_PLUGIN_EXPORT int
qemu_plugin_install (qemu_plugin_id_t id, const qemu_info_t *info,
		     int argc, char **argv)
{
  for (int i = 0; i < argc; i++)
    {
      if (!strncmp (argv[i], "lo=", 3))
	lo = strtoull (argv[i] + 3, NULL, 0);
      else if (!strncmp (argv[i], "hi=", 3))
	hi = strtoull (argv[i] + 3, NULL, 0);
    }
  little_endian = !strcmp (info->target_name, "microblazeel");
  if (!lo || hi <= lo)
    {
      fprintf (stderr, "mbcount: need lo= and hi=\n");
      return -1;
    }
  qemu_plugin_register_vcpu_tb_trans_cb (id, tb_trans);
  qemu_plugin_register_atexit_cb (id, at_exit, NULL);
  return 0;
}
