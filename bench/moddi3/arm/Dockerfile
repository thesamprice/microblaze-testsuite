# Debian's arm-none-eabi-gcc 14.2, the compiler the Cortex-M0 figures in
# REPORT.md and the gcc-microblaze-generic-moddi3 cover letter were taken
# with.  Build with:  docker build -t mb-armgcc142 bench/moddi3/arm
FROM debian:trixie
RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc-arm-none-eabi make python3 && rm -rf /var/lib/apt/lists/*
