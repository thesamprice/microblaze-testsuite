/* QEMU TCG plugin: count the MicroBlaze instructions executed in an address
   range, by class, and the taken branches out of it.

     -plugin ./libmbcount.so,lo=0x...,hi=0x...

   bench/moddi3/run.sh links the routine under test and the libgcc helpers
   it calls at the end of .text and passes their extent, so the counts
   cover __moddi3 and everything it calls, and nothing of the harness.

   "taken" counts every change of control flow: the next instruction
   executed is not the one after the last in the range, which also
   catches the delay-slot forms (the slot runs, then control moves) and
   the return to the caller.

   It also estimates clock cycles for two MicroBlaze pipelines, from the
   per-instruction latencies in UG984 (v2026.2, "MicroBlaze Instruction
   Set Architecture" and "Pipeline Architecture"): cyc5 for the five-stage
   pipeline (C_AREA_OPTIMIZED=0) and cyc3 for the three-stage one
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

   rtsd and the other returns always have a delay slot.  cyc5 and cyc3
   assume single-cycle local memory, no branch target cache and no
   data-hazard stalls; idiv by zero, which takes 1 cycle, is costed as a
   full divide.  They are estimates, not measurements.  max5 and max3 are
   the most cycles any one call took.

   Whether a branch was taken comes from its condition and target, not
   only from where execution went next, so that a taken branch to the
   instruction after it (or after its delay slot) is costed as taken.
   A conditional branch whose target is that instruction and whose
   outcome cannot be decoded (rA other than r0) is costed as not taken
   and counted in "amb"; run.sh's numbers need amb=0.

   Two further figures bound what UG984 says the five-stage pipeline
   adds or saves:

   cyc5btc is cyc5 with a perfect branch target cache ("Branch Target
   Cache": a correctly predicted immediate branch or return incurs no
   overhead).  Immediate branches (bri, bcci) and returns cost 1 cycle
   whether taken or not; register branches (br, bcc) keep their cost.
   The cache is optional and exists only with C_AREA_OPTIMIZED=0 or 2,
   and a real one mispredicts, so the truth lies between cyc5btc and
   cyc5.  max5btc is the most cycles any one call took on that basis.

   haz5lo and haz5hi bound the data-hazard stalls ("Five Stage
   Pipeline"): an instruction that needs the result of a load, barrel
   shift, multiply or divide still in EX stalls 1-2 cycles (counted as 1
   in haz5lo and 2 in haz5hi, except barrel shifts, 1 in both); one that
   needs the result of a load or multiply in MEM, two instructions back,
   stalls 1 cycle.  Add them to cyc5 or cyc5btc.  The three-stage
   pipeline has no data hazards.  Stalls are not tracked across the
   return to the harness, and a taken branch between producer and
   consumer is not taken into account.  */

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
static uint64_t cyc5, cyc3, cyc5btc;

/* Branch outcomes: taken with and without a delay slot, not taken, and
   not-taken outcomes that could not be decoded.  */
static uint64_t tk_d, tk_nd, ntk, amb;

/* Data-hazard stall bounds for the five-stage pipeline.  */
static uint64_t haz5lo, haz5hi;

/* The most cycles one call took: each stretch of execution inside the
   range is one call, since the harness runs outside it.  */
static uint64_t call5, call3, call5btc, max5, max3, max5btc;

/* What the plugin needs to know about one instruction, decoded when it
   is translated.  */
enum how { B_NONE, B_ALWAYS, B_COND };
enum prod { P_NONE, P_LOAD, P_MUL, P_BSHIFT, P_DIV };
struct insn
{
  uint64_t pc;
  enum cls cls;
  bool delay;			/* a branch with a delay slot */
  bool predicted;		/* an immediate branch or return, for the BTC */
  enum how how;			/* unconditional or conditional branch */
  bool target_known;		/* target is known at translation time */
  uint64_t target;
  int cond_r0;			/* conditional on r0: 1 taken, 0 not, -1 unknown */
  uint32_t reads;		/* registers read, as a mask; r0 excluded */
  int writes;			/* register written, or 0 */
  enum prod prod;		/* what kind of result it produces */
};

/* The branch whose outcome is still to be seen, and how many more
   instructions until the one that shows it.  */
static const struct insn *br;
static int br_wait;

/* The last two instructions executed in range, for the hazard model.  */
static const struct insn *p1, *p2;

static bool little_endian;

/* Words seen at translation time, by address, so that a branch can find
   an imm prefix before it.  */
static GHashTable *words;

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
    case 0x2e:			/* bri...; mbar has bit 1 of rA set */
      return (w >> 16) & 3 ? C_OTHER : C_BRANCH;
    case 0x26: case 0x27: case 0x2d: case 0x2f:
      return C_BRANCH;		/* br, bcc, rtsd/rtid..., bcci */
    default:
      return C_OTHER;
    }
}

/* Whether a branch has a delay slot, from its encoding.  */
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

/* The outcome of conditional branch W when it tests r0, which is 0:
   eq, le and ge are taken, ne, lt and gt are not.  */
static int
cond_on_r0 (uint32_t w)
{
  if (((w >> 16) & 31) != 0)
    return -1;
  switch ((w >> 21) & 7)	/* the condition, in the low bits of rD */
    {
    case 0: case 3: case 5:	/* eq, le, ge */
      return 1;
    default:			/* ne, lt, gt */
      return 0;
    }
}

static struct insn *
decode (uint64_t pc, uint32_t w)
{
  struct insn *d = g_new0 (struct insn, 1);
  unsigned op = w >> 26, rd = (w >> 21) & 31, ra = (w >> 16) & 31;
  unsigned rb = (w >> 11) & 31;
  bool type_b = op & 8;		/* immediate form */
  uint32_t r = 0;
  int wr = rd;

  d->pc = pc;
  d->cls = classify (w);
  if (d->cls == C_BRANCH)
    {
      d->delay = has_delay_slot (w);
      d->predicted = op == 0x2e || op == 0x2f || op == 0x2d;
      d->how = (op == 0x27 || op == 0x2f) ? B_COND : B_ALWAYS;
      d->cond_r0 = d->how == B_COND ? cond_on_r0 (w) : -1;
      if (op == 0x2e || op == 0x2f)
	{
	  /* The target: imm prefix and low half, relative unless bri has
	     its A bit.  */
	  uint32_t low = w & 0xffff;
	  gpointer pw = g_hash_table_lookup (words,
					     GSIZE_TO_POINTER (pc - 4));
	  uint32_t prevw = GPOINTER_TO_SIZE (pw);
	  uint32_t off = (pw && (prevw >> 26) == 0x2c)
	    ? (prevw & 0xffff) << 16 | low
	    : (uint32_t) (int32_t) (int16_t) low;
	  bool absolute = op == 0x2e && ((w >> 19) & 1);
	  d->target_known = true;
	  d->target = absolute ? off : (uint32_t) (pc + off);
	}
    }

  /* Registers read and written, for the hazard model.  */
  switch (op)
    {
    case 0x2c: wr = 0; break;				/* imm */
    case 0x2d: r = 1u << ra; wr = 0; break;		/* rtsd... */
    case 0x26: r = 1u << rb; wr = ((w >> 18) & 1) ? rd : 0; break;
    case 0x2e: wr = ((w >> 18) & 1) ? rd : 0; break;
    case 0x27: r = 1u << ra | 1u << rb; wr = 0; break;
    case 0x2f: r = 1u << ra; wr = 0; break;
    case 0x24: r = 1u << ra; break;
    case 0x34: case 0x35: case 0x36: case 0x3c: case 0x3d: case 0x3e:
      r = 1u << ra | 1u << rd | (type_b ? 0 : 1u << rb); wr = 0; break;
    default: r = 1u << ra | (type_b ? 0 : 1u << rb); break;
    }
  d->reads = r & ~1u;
  d->writes = wr;
  switch (d->cls)
    {
    case C_LOAD: d->prod = P_LOAD; break;
    case C_MUL: d->prod = P_MUL; break;
    case C_BSHIFT: d->prod = P_BSHIFT; break;
    case C_DIV: d->prod = P_DIV; break;
    default: d->prod = P_NONE; break;
    }
  return d;
}

static void
resolve_branch (bool was_taken)
{
  unsigned c = !was_taken ? 1 : br->delay ? 2 : 3;
  cyc5 += c;
  cyc3 += c;
  cyc5btc += br->predicted ? 1 : c;
  if (!was_taken)
    ntk++;
  else if (br->delay)
    tk_d++;
  else
    tk_nd++;
  br_wait = 0;
}

/* Whether the pending branch was taken, now that the instruction at PC
   follows it.  */
static bool
branch_taken (uint64_t pc)
{
  uint64_t next = br->pc + (br->delay ? 8 : 4);
  if (pc != next || br->how == B_ALWAYS)
    return true;
  /* A conditional branch went on to the next instruction: not taken,
     unless that is also its target.  */
  if (br->cond_r0 >= 0)
    return br->cond_r0;
  if (br->target_known && br->target != next)
    return false;
  amb++;
  return false;
}

static void
hazard (const struct insn *d)
{
  if (p1 && p1->writes && (d->reads >> p1->writes & 1) && p1->prod)
    {
      haz5lo += 1;
      haz5hi += p1->prod == P_BSHIFT ? 1 : 2;
    }
  else if (p2 && p2->writes && (d->reads >> p2->writes & 1)
	   && (p2->prod == P_LOAD || p2->prod == P_MUL))
    {
      haz5lo += 1;
      haz5hi += 1;
    }
  p2 = p1;
  p1 = d;
}

static void
exec_in (unsigned int cpu, void *udata)
{
  const struct insn *d = udata;
  uint64_t pc = d->pc;
  if (prev && pc != prev + 4)
    taken++;
  if (br_wait && --br_wait == 0)
    resolve_branch (branch_taken (pc));
  count[d->cls]++;
  cyc5 += cyc5_of[d->cls];
  cyc3 += cyc3_of[d->cls];
  cyc5btc += cyc5_of[d->cls];
  hazard (d);
  if (d->cls == C_BRANCH)
    {
      br = d;
      br_wait = d->delay ? 2 : 1;
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
      if (cyc5btc - call5btc > max5btc)
	max5btc = cyc5btc - call5btc;
    }
  call5 = cyc5;
  call3 = cyc3;
  call5btc = cyc5btc;
  prev = 0;
  p1 = p2 = NULL;
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
	  g_hash_table_insert (words, GSIZE_TO_POINTER (pc),
			       GSIZE_TO_POINTER (w));
	  qemu_plugin_register_vcpu_insn_exec_cb (insn, exec_in,
						  QEMU_PLUGIN_CB_NO_REGS,
						  decode (pc, w));
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
			  " max5=%" PRIu64 " max3=%" PRIu64
			  " tk_d=%" PRIu64 " tk_nd=%" PRIu64
			  " ntk=%" PRIu64 " amb=%" PRIu64
			  " cyc5btc=%" PRIu64 " max5btc=%" PRIu64
			  " haz5lo=%" PRIu64 " haz5hi=%" PRIu64 "\n",
			  taken, total, cyc5, cyc3, max5, max3,
			  tk_d, tk_nd, ntk, amb, cyc5btc, max5btc,
			  haz5lo, haz5hi);
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
  words = g_hash_table_new (g_direct_hash, g_direct_equal);
  qemu_plugin_register_vcpu_tb_trans_cb (id, tb_trans);
  qemu_plugin_register_atexit_cb (id, at_exit, NULL);
  return 0;
}
