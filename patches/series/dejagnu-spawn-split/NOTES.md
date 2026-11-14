# dejagnu-spawn-split

Issue: thesamprice/rtems-microblaze-linker-relaxation-bug#72.

Base: DejaGnu master `6ea0ff7` (2026-11-06). For dejagnu@gnu.org.

`daaf156` ("Fix quoting on Tcl catch(n) usage", merged to master in
`a2d3d52`) made `local_exec` and `remote_spawn` in `lib/remote.exp` pass the
whole command line to `spawn` as one word. Every local command with
arguments then fails with "spawn failed". In this runner, gcc gave no
results at all, and binutils, gas and ld gave 23, 5 and 652 FAIL. The
patch splits the command line with `eval`, as the old string scripts did
and as the same commit does for `spawn adb`.

Tested: with it, `make check` on DejaGnu master gives the zero-failure
results in the top-level README, the same as with DejaGnu `04e4201` from
before the merge.

`patches/dejagnu/0002` is this patch without its ChangeLog entry, which
would conflict as soon as upstream adds one, as with `0001`.
