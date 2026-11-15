/* Start-up and semihosting for bench.c on QEMU's micro:bit.  Compile with
   -fno-tree-loop-distribute-patterns, or gcc turns memcpy and memset
   below into calls to themselves.  */

extern int main (void);
extern char __bss_start[], __bss_end[];

void
sh_exit (int code)
{
  /* SYS_EXIT_EXTENDED, so the status reaches QEMU's exit code.  */
  static unsigned int blk[2];
  blk[0] = 0x20026;		/* ADP_Stopped_ApplicationExit */
  blk[1] = code;
  register unsigned int r0 __asm__ ("r0") = 0x20;
  register void *r1 __asm__ ("r1") = blk;
  __asm__ volatile ("bkpt 0xab" : : "r" (r0), "r" (r1) : "memory");
  for (;;)
    ;
}

void
sh_write0 (const char *s)
{
  register unsigned int r0 __asm__ ("r0") = 0x04;	/* SYS_WRITE0 */
  register const char *r1 __asm__ ("r1") = s;
  __asm__ volatile ("bkpt 0xab" : "+r" (r0) : "r" (r1) : "memory");
}

/* call_divmod (a, b, fn, rem): a in r0:r1, b in r2:r3, fn and rem on the
   stack.  Calls fn, stores the AEABI remainder r2:r3 in *rem, and
   returns the quotient in r0:r1.  Outside the counted range.  */
__asm__ (".text\n"
	 ".global call_divmod\n"
	 ".thumb_func\n"
	 "call_divmod:\n"
	 "	push	{r4, r5, lr}\n"
	 "	ldr	r4, [sp, #12]\n"
	 "	ldr	r5, [sp, #16]\n"
	 "	blx	r4\n"
	 "	str	r2, [r5]\n"
	 "	str	r3, [r5, #4]\n"
	 "	pop	{r4, r5, pc}\n");

/* libgcc builds its divide routines with -fexceptions, so they name the
   ARM personality routines; these keep the unwinder out of the link.
   Nothing here throws, so they are never called.  */
void __aeabi_unwind_cpp_pr0 (void) { sh_exit (98); }
void __aeabi_unwind_cpp_pr1 (void) { sh_exit (98); }
void __aeabi_unwind_cpp_pr2 (void) { sh_exit (98); }
void abort (void) { sh_exit (134); }

void *
memcpy (void *d, const void *s, unsigned int n)
{
  char *a = d;
  const char *b = s;
  while (n--)
    *a++ = *b++;
  return d;
}

void *
memset (void *d, int c, unsigned int n)
{
  char *a = d;
  while (n--)
    *a++ = c;
  return d;
}

void
Reset_Handler (void)
{
  for (char *p = __bss_start; p < __bss_end; p++)
    *p = 0;
  sh_exit (main ());
}

static void
hang (void)
{
  sh_exit (99);
}

__attribute__ ((section (".vectors"), used))
static void (*const vectors[16]) (void) = {
  (void (*) (void)) 0x20004000, Reset_Handler, hang, hang, hang, hang,
  hang, hang, hang, hang, hang, hang, hang, hang, hang, hang
};
