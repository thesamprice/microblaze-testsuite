/* Local demonstration, not for submission. */
#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <rtems.h>
#include <rtems/backtrace.h>
#include <rtems/bspIo.h>
#include <tmacros.h>

const char rtems_test_name[] = "BTDEMO";

static volatile int spin = 1;
static void *addrs[ 32 ];

static void report( const char *where )
{
  int n = rtems_backtrace( addrs, 32 );
  int i;
  printk( "backtrace from %s: %d frames\n", where, n );
  for ( i = 0; i < n; ++i ) {
    printk( "#%i 0x%08x\n", i, (unsigned) (uintptr_t) addrs[ i ] );
  }
}

static void fatal_ext( rtems_fatal_source s, bool always, rtems_fatal_code c )
{
  (void) always; (void) c;
  if ( s == RTEMS_FATAL_SOURCE_EXCEPTION ) {
    report( "fatal extension" );
    printk( "*** END OF TEST BTDEMO ***\n" );
  }
}

#if BTDEMO == 3
static rtems_id timer;
static void tsr( rtems_id id, void *arg )
{
  (void) id; (void) arg;
  report( "timer service routine" );
  spin = 0;
}
#endif

static RTEMS_NO_INLINE void g2( void )
{
#if BTDEMO == 1
  __asm__ volatile ( "brki r17, 0x8\n\tnop" ::: "r17", "memory" );
#elif BTDEMO == 2
  __asm__ volatile ( "brki r16, 0x18\n\tnop" ::: "r16", "memory" );
#else
  while ( spin ) {
    __asm__ volatile ( "" ::: "memory" );
  }
#endif
  RTEMS_COMPILER_MEMORY_BARRIER();
}

static RTEMS_NO_INLINE void g1( void )
{
  g2();
  RTEMS_COMPILER_MEMORY_BARRIER();
}

static rtems_task Init( rtems_task_argument arg )
{
  (void) arg;
  TEST_BEGIN();
#if BTDEMO == 3
  rtems_status_code sc;
  sc = rtems_timer_create( rtems_build_name( 'T', 'M', 'R', ' ' ), &timer );
  rtems_test_assert( sc == RTEMS_SUCCESSFUL );
  sc = rtems_timer_fire_after( timer, 2, tsr, NULL );
  rtems_test_assert( sc == RTEMS_SUCCESSFUL );
#endif
  g1();
  TEST_END();
  rtems_test_exit( 0 );
}

#define CONFIGURE_APPLICATION_NEEDS_SIMPLE_CONSOLE_DRIVER
#define CONFIGURE_APPLICATION_NEEDS_CLOCK_DRIVER
#define CONFIGURE_MAXIMUM_TASKS 1
#define CONFIGURE_MAXIMUM_TIMERS 1
#define CONFIGURE_INITIAL_EXTENSIONS \
  { .fatal = fatal_ext }, RTEMS_TEST_INITIAL_EXTENSION
#define CONFIGURE_RTEMS_INIT_TASKS_TABLE
#define CONFIGURE_INIT
#include <rtems/confdefs.h>
