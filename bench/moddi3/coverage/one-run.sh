#!/bin/sh
# one-run.sh RUN.cov LCOVDIR: one tcgcov artifact, and the ELF beside it,
# to a per-run LCOV file in LCOVDIR.  run.sh calls this, with GCC_SRC and
# TCGCOV in the environment and the target toolchain on PATH.
set -e
c=$1
e=${c%.cov}.elf
r=$2/$(basename "$c" .cov)
t () { PYTHONPATH=$TCGCOV python3 -m tcgcov "$@" 2>/dev/null; }
p="--toolchain-prefix microblaze-elf- --source-root $GCC_SRC"
t symbolize --cov "$c" --elf "$e" $p --out "$r.covered.jsonl"
t coverable --elf "$e" $p --out "$r.coverable.jsonl"
t branches --cov "$c" --elf "$e" $p --out "$r.branches.jsonl"
t lcov "$r.covered.jsonl" --coverable "$r.coverable.jsonl" \
  --branches "$r.branches.jsonl" --out "$r.info"
