/* QEMU TCG plugin: count, per call, the instructions executed in one
   address range, for the Cortex-M0 bench in this directory.

     -plugin ./libarmcount.so,lo=0x...,hi=0x...,out=FILE

   A call starts when an instruction in [lo, hi) runs after one outside
   it, and ends at the next instruction outside.  Calls between routines
   inside the range (__aeabi_ldivmod to __gnu_ldivmod_helper to __divdi3,
   say) stay inside it, so they count as part of the outer call.  FILE
   gets one count per call, in order; bench.c makes exactly one call per
   vector, and summary.py pairs the counts with the vectors' classes.

   At exit the plugin prints the number of calls and the total, so the
   counts can be checked against the sum of FILE.  Single vCPU only.  */

#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <qemu-plugin.h>

QEMU_PLUGIN_EXPORT int qemu_plugin_version = QEMU_PLUGIN_VERSION;

static uint64_t lo, hi, calls, total, cur;
static int inside;
static FILE *out;

static void
exec_in (unsigned int vcpu, void *udata)
{
  if (!inside)
    {
      inside = 1;
      cur = 0;
    }
  cur++;
  total++;
}

static void
exec_out (unsigned int vcpu, void *udata)
{
  if (inside)
    {
      inside = 0;
      calls++;
      fprintf (out, "%" PRIu64 "\n", cur);
    }
}

static void
tb_trans (qemu_plugin_id_t id, struct qemu_plugin_tb *tb)
{
  size_t n = qemu_plugin_tb_n_insns (tb);
  for (size_t i = 0; i < n; i++)
    {
      struct qemu_plugin_insn *insn = qemu_plugin_tb_get_insn (tb, i);
      uint64_t pc = qemu_plugin_insn_vaddr (insn);
      qemu_plugin_register_vcpu_insn_exec_cb (insn,
					      pc >= lo && pc < hi
					      ? exec_in : exec_out,
					      QEMU_PLUGIN_CB_NO_REGS, NULL);
    }
}

static void
at_exit (qemu_plugin_id_t id, void *p)
{
  char buf[128];
  if (inside)
    exec_out (0, NULL);
  fclose (out);
  snprintf (buf, sizeof buf, "ARMCOUNT calls=%" PRIu64 " total=%" PRIu64 "\n",
	    calls, total);
  qemu_plugin_outs (buf);
}

QEMU_PLUGIN_EXPORT int
qemu_plugin_install (qemu_plugin_id_t id, const qemu_info_t *info,
		     int argc, char **argv)
{
  const char *file = NULL;
  for (int i = 0; i < argc; i++)
    if (!strncmp (argv[i], "lo=", 3))
      lo = strtoull (argv[i] + 3, NULL, 0);
    else if (!strncmp (argv[i], "hi=", 3))
      hi = strtoull (argv[i] + 3, NULL, 0);
    else if (!strncmp (argv[i], "out=", 4))
      file = argv[i] + 4;
  if (!lo || !hi || !file || !(out = fopen (file, "w")))
    {
      fprintf (stderr, "armcount: need lo=, hi= and a writable out=\n");
      return -1;
    }
  qemu_plugin_register_vcpu_tb_trans_cb (id, tb_trans);
  qemu_plugin_register_atexit_cb (id, at_exit, NULL);
  return 0;
}
