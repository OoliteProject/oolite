LIBJS_SRC_DIR=deps/Cross-platform-deps/SpiderMonkey/js/src

ifeq ($(GNUSTEP_HOST_OS),mingw32)
LIBJS=deps/Windows-x86-deps/DLLs/js32.dll
endif
ifeq ($(GNUSTEP_HOST_OS),linux-gnu)
# Set up GNU make environment
GNUSTEP_MAKEFILES=/usr/share/GNUstep/Makefiles
# These are the paths for our custom-built Javascript library
LIBJS_INC_DIR=$(LIBJS_SRC_DIR)
LIBJS_BIN_DIR=$(LIBJS_SRC_DIR)/Linux_All_OPT.OBJ
LIBJS=$(LIBJS_BIN_DIR)/libjs.a
endif

DEPS=$(LIBJS)

# Here are our default targets
#
release: $(DEPS)
	make -f GNUmakefile debug=no

debug: $(DEPS)
	make -f GNUmakefile debug=yes

$(LIBJS):
ifeq ($(GNUSTEP_HOST_OS),mingw32)
	@echo "ERROR - this Makefile can't (yet) build the Javascript DLL"
	@echo "        Please build it yourself and copy it to $(LIBJS)."
	false
endif
	make -C $(LIBJS_SRC_DIR) -f Makefile.ref BUILD_OPT=1

clean:
ifneq ($(GNUSTEP_HOST_OS),mingw32)
	make -C $(LIBJS_SRC_DIR)/editline -f Makefile.ref clobber
	make -C $(LIBJS_SRC_DIR) -f Makefile.ref clobber
	find $(LIBJS_SRC_DIR) -name "Linux_All_*.OBJ" | xargs rm -Rf
endif
	make -f GNUmakefile clean
	rm -Rf obj obj.dbg oolite.app

all: release debug

remake: clean all

# Here are our Debian packager targets
#
pkg-deb:
	debuild binary

pkg-debclean:
	debuild clean

# And here are our Windows packager targets
#
NSIS="C:\Program Files\NSIS\makensis.exe"
# The args seem to cause failure with some versions of NSIS.
# Because of this, we set the version string on the installer script itself.
# NSIS_ARGS=-V1 -DVER=1.73-dev
pkg-win: release
	$(NSIS) installers/win32/OOlite.nsi

help:
	@echo "Use this Makefile to build Oolite:"
	@echo "  release - builds a release executable in oolite.app/oolite"
	@echo "  debug   - builds a debug executable in oolite.app/oolite.dbg"
	@echo "  all     - builds the above two targets"
	@echo "  clean   - removes all generated files"
	@echo
	@echo "  pkg-deb - builds a Debian package"
	@echo "  pkg-debclean - cleans up after a Debian package build"
	@echo
	@echo "  pkg-win - builds a Windows NSIS installer package"

.PHONY: all release debug clean remake pkg-deb pkg-debclean pkg-win help
