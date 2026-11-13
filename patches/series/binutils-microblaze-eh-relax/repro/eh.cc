/* Issue #71 reproducer: C++ exception through a function whose code
   shrinks under MicroBlaze linker relaxation.  Every call to an external
   function in another section is "imm hi; brlid r15, lo"; ld -relax
   deletes the imm when the
   target is in range.  The LSDA call-site table holds offsets from the
   function start that gas computes at assembly time, so they go stale.  */
#include <rtems.h>
#include <stdio.h>
#include <stdlib.h>

extern "C" void sink(int);
__attribute__((noipa, section(".text.sink"))) void sink(int) {}

static void __attribute__((noipa)) thrower(int v)
{
  throw v;
}

#define C4 sink(1); sink(2); sink(3); sink(4);
#define C16 C4 C4 C4 C4

static int __attribute__((noipa)) test(int v)
{
  C16 C16                 /* 32 calls outside the try: 32 imm deleted */
  try {
    thrower(v);
  } catch (int e) {
    return e;
  }
  return -1;
}

extern "C" rtems_task Init(rtems_task_argument)
{
  printf("\n*** BEGIN eh-relax ***\n");
  int r = test(42);
  printf("caught %d\n*** END eh-relax ***\n", r);
  exit(r == 42 ? 0 : 1);
}

#define CONFIGURE_APPLICATION_NEEDS_CLOCK_DRIVER
#define CONFIGURE_APPLICATION_NEEDS_CONSOLE_DRIVER
#define CONFIGURE_MAXIMUM_TASKS 1
#define CONFIGURE_RTEMS_INIT_TASKS_TABLE
#define CONFIGURE_INIT_TASK_STACK_SIZE (16 * 1024)
#define CONFIGURE_INIT
#include <rtems/confdefs.h>
