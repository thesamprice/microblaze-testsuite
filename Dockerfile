# Everything the Makefile needs on the host, so that a run is the same on
# any machine with Docker.  Used by `make docker-<target>`; see README.md.

FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential git curl ca-certificates xz-utils file \
      bison flex texinfo \
      libgmp-dev libmpfr-dev libmpc-dev zlib1g-dev \
      expect tcl \
      python3 python3-venv ninja-build pkg-config \
      libglib2.0-dev libpixman-1-dev \
    && rm -rf /var/lib/apt/lists/*

# Shallow clones of upstream need no identity, but `git apply --index` on
# a fresh clone wants to know where it is.
RUN git config --system safe.directory '*'

WORKDIR /repo
