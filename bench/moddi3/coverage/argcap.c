/* QEMU TCG plugin: log the operands of every call to the routines at the
   given entry addresses.

     -plugin ./libargcap.so,out=FILE,fn=0xADDR:NAME[,fn=...]

   At each entry it reads r5 to r8, the two 64-bit arguments as register
   pairs, and appends "NAME r5 r6 r7 r8" in hex to FILE.  The values are as
   QEMU's register interface returns them, in the guest's byte order; the
   reader puts the pairs back together.  Single vCPU only.  */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <glib.h>
#include <qemu-plugin.h>

QEMU_PLUGIN_EXPORT int qemu_plugin_version = QEMU_PLUGIN_VERSION;

#define MAXFN 8
static struct { uint64_t addr; char name[32]; } fns[MAXFN];
static int nfns;
static FILE *out;
static struct qemu_plugin_register *reg[4];	/* r5..r8 */
static GByteArray *buf;

static void
vcpu_init (qemu_plugin_id_t id, unsigned int cpu)
{
  GArray *regs = qemu_plugin_get_registers ();
  for (guint i = 0; i < regs->len; i++)
    {
      qemu_plugin_reg_descriptor *r
	= &g_array_index (regs, qemu_plugin_reg_descriptor, i);
      for (int k = 0; k < 4; k++)
	{
	  char want[8];
	  snprintf (want, sizeof want, "r%d", 5 + k);
	  if (!strcmp (r->name, want))
	    reg[k] = r->handle;
	}
    }
  g_array_free (regs, TRUE);
  buf = g_byte_array_new ();
}

static void
entry (unsigned int cpu, void *udata)
{
  int f = (int) (uintptr_t) udata;
  fprintf (out, "%s", fns[f].name);
  for (int k = 0; k < 4; k++)
    {
      g_byte_array_set_size (buf, 0);
      int n = reg[k] ? qemu_plugin_read_register (reg[k], buf) : 0;
      fprintf (out, " ");
      for (int b = 0; b < n; b++)
	fprintf (out, "%02x", buf->data[b]);
    }
  fprintf (out, "\n");
}

static void
tb_trans (qemu_plugin_id_t id, struct qemu_plugin_tb *tb)
{
  size_t n = qemu_plugin_tb_n_insns (tb);
  for (size_t i = 0; i < n; i++)
    {
      struct qemu_plugin_insn *insn = qemu_plugin_tb_get_insn (tb, i);
      uint64_t pc = qemu_plugin_insn_vaddr (insn);
      for (int f = 0; f < nfns; f++)
	if (pc == fns[f].addr)
	  qemu_plugin_register_vcpu_insn_exec_cb (insn, entry,
						  QEMU_PLUGIN_CB_R_REGS,
						  (void *) (uintptr_t) f);
    }
}

static void
at_exit (qemu_plugin_id_t id, void *p)
{
  if (out)
    fclose (out);
}

QEMU_PLUGIN_EXPORT int
qemu_plugin_install (qemu_plugin_id_t id, const qemu_info_t *info,
		     int argc, char **argv)
{
  const char *path = NULL;
  for (int i = 0; i < argc; i++)
    {
      if (!strncmp (argv[i], "out=", 4))
	path = argv[i] + 4;
      else if (!strncmp (argv[i], "fn=", 3) && nfns < MAXFN)
	{
	  char *colon = strchr (argv[i] + 3, ':');
	  if (!colon)
	    return -1;
	  fns[nfns].addr = strtoull (argv[i] + 3, NULL, 0);
	  snprintf (fns[nfns].name, sizeof fns[nfns].name, "%s", colon + 1);
	  nfns++;
	}
    }
  if (!path || !nfns || !(out = fopen (path, "w")))
    {
      fprintf (stderr, "argcap: need out= and fn=ADDR:NAME\n");
      return -1;
    }
  setvbuf (out, NULL, _IOLBF, 0);
  qemu_plugin_register_vcpu_init_cb (id, vcpu_init);
  qemu_plugin_register_vcpu_tb_trans_cb (id, tb_trans);
  qemu_plugin_register_atexit_cb (id, at_exit, NULL);
  return 0;
}
