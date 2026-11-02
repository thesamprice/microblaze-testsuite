# Build a MicroBlaze cross toolchain and QEMU from upstream sources and run
# the binutils and GCC DejaGnu testsuites against them, with the GCC execute
# tests running under QEMU system emulation.
#
#   make                  fetch and build everything
#   make check            run every testsuite
#   make check-gcc-smoke  eight execute tests, a few minutes
#   make summary          print the summaries of the last run
#
# Every component can be replaced by your own; see "Using your own trees"
# in README.md.  Every variable below can be set on the command line.

TARGET       ?= microblaze-elf
WORK         ?= $(CURDIR)/work
PREFIX       ?= $(WORK)/install
JOBS         ?= $(shell getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)

BINUTILS_GIT ?= https://sourceware.org/git/binutils-gdb.git
BINUTILS_REF ?= master
GCC_GIT      ?= https://gcc.gnu.org/git/gcc.git
GCC_REF      ?= master
NEWLIB_GIT   ?= https://sourceware.org/git/newlib-cygwin.git
NEWLIB_REF   ?= main
DEJAGNU_GIT  ?= https://git.savannah.gnu.org/git/dejagnu.git
DEJAGNU_REF  ?= master
QEMU_VERSION ?= 10.2.4
QEMU_URL     ?= https://download.qemu.org/qemu-$(QEMU_VERSION).tar.xz

# The DejaGnu board, and what the GCC run covers.  RUNTESTFLAGS is passed
# through to every testsuite, e.g. RUNTESTFLAGS=-v.
BOARD        ?= microblaze-qemu
GCC_TESTS    ?= execute.exp
GCC_SMOKE    ?= execute.exp='20010221-1.c loop-2b.c memcpy-1.c 990208-1.c printf-1.c arith-rand-ll.c pr50865.c pr28982b.c'
RUNTESTFLAGS ?=

# Current binutils mis-places __wrap_* symbols when relaxing, which breaks
# the status wrapper the board depends on; see README.md.  Set it empty to
# test a linker that carries the fix.
MB_NO_RELAX  ?= -Wl,--no-relax
MB_TIMEOUT   ?= 90

# Where each testsuite's .sum and .log are copied after a run.
RESULTS      ?= $(WORK)/results

SRC   := $(WORK)/src
BUILD := $(WORK)/build
STAMP := $(WORK)/stamps
LOGS  := $(WORK)/logs

# --- your own trees -----------------------------------------------------
#
# Set any of these to use an existing tree instead of the one this Makefile
# would fetch or build.  A *_SRC is configured and built here; a *_BUILD is
# an already-configured build tree, tested in place and not rebuilt; QEMU
# is a qemu-system-microblaze[el] binary.  Whatever is not set is built.

# own VAR: "yes" when VAR was set by the user rather than defaulted here.
own = $(if $(filter command line environment,$(origin $(1))),yes)

OWN_BINUTILS_SRC   := $(call own,BINUTILS_SRC)
OWN_BINUTILS_BUILD := $(call own,BINUTILS_BUILD)
OWN_GCC_SRC        := $(call own,GCC_SRC)
OWN_GCC_BUILD      := $(call own,GCC_BUILD)
OWN_NEWLIB_SRC     := $(call own,NEWLIB_SRC)
OWN_DEJAGNU_SRC    := $(call own,DEJAGNU_SRC)
OWN_QEMU           := $(call own,QEMU)

BINUTILS_SRC   ?= $(SRC)/binutils
BINUTILS_BUILD ?= $(BUILD)/binutils
GCC_SRC        ?= $(SRC)/gcc
GCC_BUILD      ?= $(BUILD)/gcc
NEWLIB_SRC     ?= $(SRC)/newlib
DEJAGNU_SRC    ?= $(SRC)/dejagnu
QEMU           ?= $(PREFIX)/bin/qemu-system-microblaze

# Where $(TARGET)-gcc and friends are.  With a GCC_BUILD of your own, point
# this at the bin directory that build was installed to.
TOOLBIN        ?= $(PREFIX)/bin
TARGET_CC      := $(TOOLBIN)/$(TARGET)-gcc
TARGET_AR      := $(TOOLBIN)/$(TARGET)-ar

# GCC's host libraries.  On macOS they come from Homebrew, and the zlib GCC
# bundles does not compile against the current SDK, hence --with-system-zlib.
BREW := $(shell brew --prefix 2>/dev/null)
HOST_LIBS := --with-system-zlib --with-isl=no \
	$(if $(BREW),--with-gmp=$(BREW) --with-mpfr=$(BREW) --with-mpc=$(BREW))

RUNTEST := $(DEJAGNU_SRC)/runtest

# DejaGnu's own directory is on PATH because GCC's check-gcc ignores
# RUNTEST and runs whichever runtest it finds there.
export PATH := $(TOOLBIN):$(DEJAGNU_SRC):$(DEJAGNU_SRC)/contrib:$(PATH)
export DEJAGNU := $(WORK)/site.exp
export MB_QEMU := $(QEMU)
export MB_NO_RELAX
export MB_TIMEOUT

# Which stamps stand for work this Makefile does; a tree you supplied needs
# none.
DEP_BINUTILS := $(if $(OWN_BINUTILS_BUILD),,$(STAMP)/binutils)
DEP_GCC      := $(if $(OWN_GCC_BUILD),,$(STAMP)/gcc)
DEP_DEJAGNU  := $(STAMP)/dejagnu
DEP_QEMU     := $(if $(OWN_QEMU),,$(STAMP)/qemu)

.PHONY: all sources toolchain binutils gcc dejagnu libxil qemu \
	check check-start check-binutils check-gas check-ld check-gcc \
	check-gcc-smoke summary env clean distclean

all: toolchain dejagnu libxil qemu

toolchain: binutils gcc
binutils: $(DEP_BINUTILS)
gcc: $(DEP_GCC)
dejagnu: $(DEP_DEJAGNU)
libxil: $(STAMP)/libxil
qemu: $(DEP_QEMU)

sources: $(if $(OWN_BINUTILS_SRC),,$(STAMP)/src-binutils) \
	$(if $(OWN_GCC_SRC),,$(STAMP)/src-gcc) \
	$(if $(OWN_NEWLIB_SRC),,$(STAMP)/src-newlib) \
	$(if $(OWN_DEJAGNU_SRC),,$(STAMP)/src-dejagnu)

# --- sources ------------------------------------------------------------

# apply NAME DIR: any patches/NAME/*.patch, in order.
define apply
	set -e; for p in $(sort $(wildcard $(CURDIR)/patches/$(1)/*.patch)); do \
	  echo "applying $$p"; git -C $(2) apply --index "$$p"; done
endef

# clone NAME URL REF: a shallow clone into $(SRC)/NAME, then its patches.
define clone
	rm -rf $(SRC)/$(1)
	mkdir -p $(SRC) $(STAMP)
	git clone --depth 1 --branch $(3) $(2) $(SRC)/$(1)
	$(call apply,$(1),$(SRC)/$(1))
	git -C $(SRC)/$(1) log -1 --format='$(1) %H %cd' --date=short > $(SRC)/$(1).rev
endef

$(STAMP)/src-binutils:
	$(call clone,binutils,$(BINUTILS_GIT),$(BINUTILS_REF))
	touch $@

$(STAMP)/src-gcc:
	$(call clone,gcc,$(GCC_GIT),$(GCC_REF))
	touch $@

# Only newlib/ and libgloss/ are needed.
$(STAMP)/src-newlib:
	rm -rf $(SRC)/newlib
	mkdir -p $(SRC) $(STAMP)
	git clone --depth 1 --branch $(NEWLIB_REF) --filter=blob:none --sparse \
	  $(NEWLIB_GIT) $(SRC)/newlib
	git -C $(SRC)/newlib sparse-checkout set newlib libgloss
	$(call apply,newlib,$(SRC)/newlib)
	git -C $(SRC)/newlib log -1 --format='newlib %H %cd' --date=short > $(SRC)/newlib.rev
	touch $@

$(STAMP)/src-dejagnu:
	$(call clone,dejagnu,$(DEJAGNU_GIT),$(DEJAGNU_REF))
	touch $@

# DejaGnu runs from its source tree, nothing installed.  The site file is
# what lets runtest find the board.  A DEJAGNU_SRC of your own must already
# carry the board patch.
$(STAMP)/dejagnu: $(if $(OWN_DEJAGNU_SRC),,$(STAMP)/src-dejagnu)
	@test -f $(DEJAGNU_SRC)/baseboards/$(BOARD).exp || \
	  { echo "$(DEJAGNU_SRC) has no baseboards/$(BOARD).exp"; exit 1; }
	mkdir -p $(STAMP)
	echo 'lappend boards_dir "$(DEJAGNU_SRC)/baseboards"' > $(WORK)/site.exp
	touch $@

# --- toolchain ----------------------------------------------------------

$(STAMP)/binutils: $(if $(OWN_BINUTILS_SRC),,$(STAMP)/src-binutils)
	rm -rf $(BINUTILS_BUILD) && mkdir -p $(BINUTILS_BUILD) $(LOGS)
	cd $(BINUTILS_BUILD) && $(BINUTILS_SRC)/configure \
	  --target=$(TARGET) --prefix=$(PREFIX) \
	  --disable-gdb --disable-gdbserver --disable-sim \
	  --disable-nls --disable-werror --with-system-zlib \
	  > $(LOGS)/binutils-configure.log 2>&1
	$(MAKE) -C $(BINUTILS_BUILD) -j$(JOBS) > $(LOGS)/binutils-build.log 2>&1
	$(MAKE) -C $(BINUTILS_BUILD) install > $(LOGS)/binutils-install.log 2>&1
	touch $@

# newlib and libgloss are symlinked into the GCC source tree so that GCC
# builds them: the combined tree DejaGnu's *-sim boards assume.
# --disable-multilib: t-microblaze otherwise builds ten copies of newlib and
# the board uses one.
$(STAMP)/gcc: $(DEP_BINUTILS) $(if $(OWN_GCC_SRC),,$(STAMP)/src-gcc) \
		$(if $(OWN_NEWLIB_SRC),,$(STAMP)/src-newlib)
	ln -sfn $(NEWLIB_SRC)/newlib $(GCC_SRC)/newlib
	ln -sfn $(NEWLIB_SRC)/libgloss $(GCC_SRC)/libgloss
	rm -rf $(GCC_BUILD) && mkdir -p $(GCC_BUILD) $(LOGS)
	cd $(GCC_BUILD) && $(GCC_SRC)/configure \
	  --target=$(TARGET) --prefix=$(PREFIX) \
	  --with-newlib --disable-multilib --disable-threads --disable-shared \
	  --enable-languages=c \
	  --disable-libssp --disable-libquadmath --disable-libgomp \
	  --disable-libatomic --disable-nls --disable-werror \
	  $(HOST_LIBS) \
	  > $(LOGS)/gcc-configure.log 2>&1
	$(MAKE) -C $(GCC_BUILD) -j$(JOBS) > $(LOGS)/gcc-build.log 2>&1
	$(MAKE) -C $(GCC_BUILD) install > $(LOGS)/gcc-install.log 2>&1
	touch $@

# GCC's MicroBlaze LIB_SPEC links -lxil, the board's own library, which
# nothing upstream builds.  It goes where the compiler finds it unprompted,
# beside libc.a: ld's testsuite probes the compiler before the board's
# ldflags apply, and fails the probe if -lxil needs a -L.
$(STAMP)/libxil: $(DEP_GCC) $(DEP_DEJAGNU)
	mkdir -p $(BUILD)
	$(TARGET_CC) -O2 -ffreestanding -c $(DEJAGNU_SRC)/microblaze-qemu-libxil.c \
	  -o $(BUILD)/libxil.o
	set -e; lib=$$(dirname $$($(TARGET_CC) -print-file-name=libc.a)); \
	  rm -f $$lib/libxil.a; $(TARGET_AR) rc $$lib/libxil.a $(BUILD)/libxil.o; \
	  echo "installed $$lib/libxil.a"
	touch $@

# Stock upstream QEMU: petalogix-s3adsp1800 is an upstream machine and the
# board asks nothing of it but a UART.
$(STAMP)/qemu:
	mkdir -p $(SRC) $(LOGS) $(STAMP)
	rm -rf $(SRC)/qemu-$(QEMU_VERSION)
	cd $(SRC) && curl -fLO $(QEMU_URL) && tar xf qemu-$(QEMU_VERSION).tar.xz
	rm -rf $(BUILD)/qemu && mkdir -p $(BUILD)/qemu
	cd $(BUILD)/qemu && $(SRC)/qemu-$(QEMU_VERSION)/configure \
	  --prefix=$(PREFIX) \
	  --target-list=microblaze-softmmu,microblazeel-softmmu \
	  --disable-docs --disable-tools --disable-guest-agent \
	  > $(LOGS)/qemu-configure.log 2>&1
	$(MAKE) -C $(BUILD)/qemu -j$(JOBS) > $(LOGS)/qemu-build.log 2>&1
	$(MAKE) -C $(BUILD)/qemu install > $(LOGS)/qemu-install.log 2>&1
	echo "qemu $(QEMU_VERSION)" > $(SRC)/qemu.rev
	touch $@

# --- testsuites ---------------------------------------------------------

# collect DIR NAME...: copy NAME.sum and NAME.log from this run to
# $(RESULTS).
define collect
	mkdir -p $(RESULTS)
	for n in $(2); do \
	  f=$$(find $(1) -name $$n.sum -newer $(STAMP)/check-start | head -1); \
	  if [ -n "$$f" ]; then cp "$$f" "$${f%.sum}.log" $(RESULTS)/; \
	  else echo "no $$n.sum from this run"; fi; done
endef

check: check-binutils check-gcc

check-start:
	@mkdir -p $(STAMP) && touch $(STAMP)/check-start

BINUTILS_CHECK = $(MAKE) -C $(BINUTILS_BUILD) -k RUNTEST=$(RUNTEST) \
	CC_FOR_TARGET=$(TARGET_CC) \
	RUNTESTFLAGS="--target_board=$(BOARD) $(RUNTESTFLAGS)"

# gas never runs target code, and ld's run tests cannot use the board (see
# README.md), so the board changes nothing here; it is set for uniformity.
check-binutils: all check-start
	-$(BINUTILS_CHECK) check-binutils check-gas check-ld
	@$(call collect,$(BINUTILS_BUILD),binutils gas ld)

check-gas: all check-start
	-$(BINUTILS_CHECK) check-gas
	@$(call collect,$(BINUTILS_BUILD),gas)

check-ld: all check-start
	-$(BINUTILS_CHECK) check-ld
	@$(call collect,$(BINUTILS_BUILD),ld)

check-gcc: all check-start
	-$(MAKE) -C $(GCC_BUILD) -k check-gcc RUNTEST=$(RUNTEST) \
	  RUNTESTFLAGS="--target_board=$(BOARD) $(RUNTESTFLAGS) $(GCC_TESTS)"
	@$(call collect,$(GCC_BUILD),gcc)

check-gcc-smoke: GCC_TESTS = $(GCC_SMOKE)
check-gcc-smoke: check-gcc

summary:
	@for f in $(RESULTS)/*.sum; do \
	  [ -f "$$f" ] || { echo "no results yet"; break; }; \
	  sed -n '/=== .* Summary ===/,$$p' "$$f"; echo; done
	@cat $(SRC)/*.rev 2>/dev/null || true

# The environment the testsuites run in, to reproduce a run by hand.
env:
	@echo "export PATH=$(TOOLBIN):$(DEJAGNU_SRC):$(DEJAGNU_SRC)/contrib:\$$PATH"
	@echo "export DEJAGNU=$(DEJAGNU)"
	@echo "export MB_QEMU=$(MB_QEMU)"
	@echo "export MB_NO_RELAX=$(MB_NO_RELAX)"
	@echo "export MB_TIMEOUT=$(MB_TIMEOUT)"
	@echo "# runtest: $(RUNTEST)"
	@echo "# binutils build: $(BINUTILS_BUILD)"
	@echo "# gcc build:      $(GCC_BUILD)"

clean:
	rm -rf $(BUILD) $(PREFIX) $(RESULTS) $(LOGS)
	rm -f $(STAMP)/binutils $(STAMP)/gcc $(STAMP)/libxil $(STAMP)/qemu

distclean:
	rm -rf $(WORK)

# --- docker -------------------------------------------------------------
#
# make docker-<target> runs `make <target>` in the image the Dockerfile
# describes, e.g. `make docker-all docker-check-gcc-smoke`.  The work tree
# lives in a Docker volume, not a bind mount: GCC and newlib are not safe
# to build on the case-insensitive filesystem macOS shares into containers.
# Results come back to ./results.

DOCKER        ?= docker
DOCKER_IMAGE  ?= microblaze-testsuite
DOCKER_VOLUME ?= microblaze-testsuite-work
DOCKER_RUN     = $(DOCKER) run --rm -v $(CURDIR):/repo:ro \
	-v $(DOCKER_VOLUME):/work -v $(CURDIR)/results:/results

# Variables given on this command line that matter inside the container.
DOCKER_VARS = $(foreach v,JOBS BINUTILS_REF GCC_REF NEWLIB_REF DEJAGNU_REF \
	QEMU_VERSION BOARD GCC_TESTS RUNTESTFLAGS MB_NO_RELAX MB_TIMEOUT,\
	$(if $(filter command line,$(origin $(v))),'$(v)=$($(v))'))

.PHONY: docker-image docker-shell docker-clean

docker-image:
	$(DOCKER) build -t $(DOCKER_IMAGE) $(CURDIR)

docker-%: docker-image
	mkdir -p $(CURDIR)/results
	$(DOCKER_RUN) $(DOCKER_IMAGE) \
	  make -C /repo WORK=/work RESULTS=/results $(DOCKER_VARS) $*
	$(DOCKER_RUN) $(DOCKER_IMAGE) chown -R $$(id -u):$$(id -g) /results

docker-shell: docker-image
	mkdir -p $(CURDIR)/results
	$(DOCKER_RUN) -it $(DOCKER_IMAGE) bash

docker-clean:
	-$(DOCKER) volume rm $(DOCKER_VOLUME)
