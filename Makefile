include config.make

VERSION_SCRIPT := ShellScripts/common/get_version.sh

-include build/version.mk

build/version.mk: $(VERSION_SCRIPT)
	./$(VERSION_SCRIPT)

DEB_BUILDTIME   := $(shell date "+%a, %d %b %Y %H:%M:%S %z")
ifeq (${VER_REV},0)
DEB_VER     := $(shell echo "${VER_MAJ}.${VER_MIN}")
else
DEB_VER     := $(shell echo "${VER_MAJ}.${VER_MIN}.${VER_REV}")
endif
DEB_REV     := $(shell cat debian/revision)
# Ubuntu versions are: <upstream version>-<deb ver>ubuntu<build ver>
# eg: oolite1.74.4-130706-0ubuntu1
# Oolite versions are: MAJ.min.rev-date (yymmdd)
# eg. 1.74.0-130706
# Our .deb versions are: MAJ.min.rev-datestring-<pkg rev>[~<type>]
# eg. 1.74.0.3275-0, 1.74.0-130706-0~test
pkg-debtest: DEB_REV             := $(shell echo "0~test${DEB_REV}")
pkg-debsnapshot: DEB_REV         := $(shell echo "0~trunk${DEB_REV}")

	DEPS                         =
	DEPS_DBG                     =
ifneq ($(GNUSTEP_HOST_OS),mingw32) 
    APSPEC_FILE                  = installers/autopackage/default.x86_64.apspec
# Uncomment the following two variables, if you want to build JS from source. Ensure the relevant changes are performed in GNUmakefile too
#     DEPS                         = LIBJS
#     DEPS_DBG                     = LIBJS_DBG
endif

# ifeq ($(GNUSTEP_HOST_OS),mingw32)
# #     LIBJS                    = deps/Windows-deps/x86_64/DLLs/js32ECMAv5.dll
# #     LIBJS_DBG                = deps/Windows-deps/x86_64/DLLs/js32ECMAv5.dll
# #     DEPS                         = $(LIBJS)
# #     DEPS_DBG                     = $(LIBJS_DBG)
#     DEPS                         = 
#     DEPS_DBG                     = 
# else
#     APSPEC_FILE                  = installers/autopackage/default.x86_64.apspec
# #     DEPS                         = LIBJS
# #     DEPS_DBG                     = LIBJS_DBG
#     DEPS                         = 
#     DEPS_DBG                     = 
# endif


.PHONY: help
help:
	@echo "This is a helper-Makefile to make compiling Oolite easier."
	@echo "Below you will find a list of available build targets."
	@echo "Syntax: make -f Makefile [build target]"
	@echo "Usage example: make -f Makefile release"
	@echo
	@echo "NOTE (Linux only!): To build linking to the precompiled dependency libraries,"
	@echo "            delivered with Oolite source, use 'deps-' prefix with debug,"
	@echo "            release, release-snapshot and release-deployment build targets."
	@echo "            Usage example: make -f Makefile deps-release"
	@echo
	@echo "Development Targets:"
	@echo "  release             - builds a test release executable in oolite.app/oolite"
	@echo "  release-deployment  - builds a release executable in oolite.app/oolite"
	@echo "  release-snapshot    - builds a snapshot release in oolite.app/oolite"
	@echo "  debug               - builds a debug executable in oolite.app/oolite.dbg"
	@echo "  all                 - builds the above targets"
	@echo "  clean               - removes all generated files"
	@echo
	@echo "Packaging Targets:"
#	@echo " Linux (debian):"
#	@echo "  pkg-deb             - builds a release Debian package"
#	@echo "  pkg-debtest         - builds a test release Debian package"
#	@echo "  pkg-debsnapshot     - builds a snapshot release Debian package"
#	@echo "  pkg-debclean        - cleans up after a Debian package build"
	@echo
#	@echo " POSIX Installer (e.g. Linux, FreeBSD etc.):"
	@echo " Linux Installer:"
#	@echo "  pkg-autopackage     - builds an autopackage (http://autopackage.org) package"
	@echo
	@echo "  pkg-appimage-test   - builds a test-release version"
	@echo "  pkg-appimage        - builds a release version"
	@echo
	@echo "  pkg-posix           - builds a release self-extracting package"
	@echo "  pkg-posix-test      - builds a test release self-extracting package"
	@echo "  pkg-posix-snapshot  - builds a snapshot release self-extracting package"
	@echo "  pkg-posix-nightly   - builds a snapshot release self-extracting package for "
	@echo "                        the nightly build"
	@echo
	@echo " Windows Installer:"
	@echo "  pkg-win             - builds a test-release version"
	@echo "  pkg-win-deployment  - builds a release version"
	@echo "  pkg-win-snapshot    - builds a snapshot version"


# Here are our default targets
#
.PHONY: release
release: $(DEPS)
	$(MAKE) -f GNUmakefile debug=no strip=yes lto=yes
	mkdir -p AddOns && rm -rf AddOns/Basic-debug.oxp && cp -rf DebugOXP/Debug.oxp AddOns/Basic-debug.oxp

.PHONY: release-deployment
release-deployment: $(DEPS)
	$(MAKE) -f GNUmakefile DEPLOYMENT_RELEASE_CONFIGURATION=yes debug=no strip=yes lto=yes

.PHONY: release-snapshot
release-snapshot: $(DEPS)
	$(MAKE) -f GNUmakefile SNAPSHOT_BUILD=yes VERSION_STRING=$(VER) debug=no
	mkdir -p AddOns && rm -rf AddOns/Basic-debug.oxp && cp -rf DebugOXP/Debug.oxp AddOns/Basic-debug.oxp

.PHONY: debug
debug: $(DEPS_DBG)
	$(MAKE) -f GNUmakefile debug=yes strip=no
	mkdir -p AddOns && rm -rf AddOns/Basic-debug.oxp && cp -rf DebugOXP/Debug.oxp AddOns/Basic-debug.oxp

# Here are targets using the provided dependencies
.PHONY: deps-release
deps-release: $(DEPS)
	cd deps/Linux-deps/x86_64/lib_linker && ./make_so_links.sh && cd ../../../..
	$(MAKE) -f GNUmakefile debug=no use_deps=yes strip=yes lto=yes
	mkdir -p AddOns && rm -rf AddOns/Basic-debug.oxp && cp -rf DebugOXP/Debug.oxp AddOns/Basic-debug.oxp

.PHONY: deps-release-deployment
deps-release-deployment: $(DEPS)
	cd deps/Linux-deps/x86_64/lib_linker && ./make_so_links.sh && cd ../../../..
	$(MAKE) -f GNUmakefile DEPLOYMENT_RELEASE_CONFIGURATION=yes debug=no use_deps=yes strip=yes lto=yes

.PHONY: deps-release-snapshot
deps-release-snapshot: $(DEPS)
	cd deps/Linux-deps/x86_64/lib_linker && ./make_so_links.sh && cd ../../../..
	$(MAKE) -f GNUmakefile SNAPSHOT_BUILD=yes VERSION_STRING=$(VER) debug=no use_deps=yes
	mkdir -p AddOns && rm -rf AddOns/Basic-debug.oxp && cp -rf DebugOXP/Debug.oxp AddOns/Basic-debug.oxp

.PHONY: deps-debug
deps-debug: $(DEPS_DBG)
	cd deps/Linux-deps/x86_64/lib_linker && ./make_so_links.sh && cd ../../../..
	$(MAKE) -f GNUmakefile debug=yes use_deps=yes strip=no
	mkdir -p AddOns && rm -rf AddOns/Basic-debug.oxp && cp -rf DebugOXP/Debug.oxp AddOns/Basic-debug.oxp

.PHONY: LIBJS_DBG
LIBJS_DBG:
ifeq ($(GNUSTEP_HOST_OS),mingw32)
	@echo "ERROR - this Makefile can't (yet) build the Javascript DLL"
	@echo "        Please build it yourself and copy it to $(LIBJS_DBG)."
	false
endif
	$(MAKE) -f libjs.make debug=yes

# .PHONY: LIBJS
# LIBJS:
# ifeq ($(GNUSTEP_HOST_OS),mingw32)
# 	@echo "ERROR - this Makefile can't (yet) build the Javascript DLL"
# 	@echo "        Please build it yourself and copy it to $(LIBJS)."
# 	false
# endif
# 	$(MAKE) -f libjs.make debug=no

.PHONY: clean
clean:
	$(MAKE) -f GNUmakefile clean
	$(RM) -rf oolite.app
	$(RM) -rf AddOns 

.PHONY: distclean
distclean: clean
ifneq ($(GNUSTEP_HOST_OS),mingw32)
	$(MAKE) -f libjs.make distclean debug=yes
	$(MAKE) -f libjs.make distclean debug=no
endif

.PHONY: all
all: release release-deployment release-snapshot debug

.PHONY: remake
remake: clean all

.PHONY: deps-all
deps-all: deps-release deps-release-deployment deps-release-snapshot deps-debug

.PHONY: deps-remake
deps-remake: clean deps-all

# Here are our linux autopackager targets
#
pkg-autopackage:
	makepackage -c -m $(APSPEC_FILE)

# Here are our POSIX (e.g. FreeBSD, Linux etc.) self-extracted packager targets
#
# TODO: For debug package the "oolite" startup script should point to "oolite.app/oolite.dbg" binary, 
#       the "uninstall" script should remove the "oolite.dbg" binary and 
#       either not distribute the "oolite-update" scripts or create an Oolite debug repository and 
#       update the "oolite.app/oolite-update" script to synchronize accordingly
#       
#       pkg-posix-debug:
#	        installers/posix/make_installer.sh x86_64 $(VER) "debug"
#
pkg-posix:
	installers/posix/make_installer.sh x86_64 $(VER) "release-deployment" ""

pkg-posix-test:
	installers/posix/make_installer.sh x86_64 $(VER) "release" ""

pkg-posix-snapshot:
	installers/posix/make_installer.sh x86_64 $(VER) "release-snapshot" ""

pkg-posix-nightly:
	installers/posix/make_installer.sh x86_64 $(VER) "release-snapshot" "nightly"

# Here are our Debian packager targets
#
.PHONY: debian/changelog
debian/changelog:
	cat debian/changelog.in | sed -e "s/@@VERSION@@/${VER}/g" -e "s/@@REVISION@@/${DEB_REV}/g" -e "s/@@TIMESTAMP@@/${DEB_BUILDTIME}/g" > debian/changelog

.PHONY: pkg-deb pkg-debtest pkg-debsnapshot
pkg-deb: debian/changelog
	debuild binary

pkg-debtest: debian/changelog
	debuild binary

pkg-debsnapshot: debian/changelog
	debuild -e SNAPSHOT_BUILD=yes -e VERSION_STRING=$(VER) binary

.PHONY: pkg-debclean
pkg-debclean:
	debuild clean


# Here are our AppImage targets
#
.PHONY: pkg-appimage
pkg-appimage: release
	installers/appimage/create_appimage.sh "$(VER)" "test"

.PHONY: pkg-appimage-deployment
pkg-appimage-deployment: release-deployment
	installers/appimage/create_appimage.sh "$(VER)"

.PHONY: pkg-appimage-snapshot
pkg-appimage-snapshot: release-snapshot
	installers/appimage/create_appimage.sh "$(VER)" "dev"

# And here are our Windows packager targets
#
ifneq '' '$(MINGW_PREFIX)'
NSIS=$(MINGW_PREFIX)/bin/makensis -DOUTDIR="../../build"
else
NSIS=/nsis/makensis.exe
endif
NSISVERSIONS=installers/win32/OoliteVersions.nsh

# Passing arguments cause problems with some versions of NSIS.
# Because of this, we generate them into a separate file and include them.
.PHONY: ${NSISVERSIONS}
${NSISVERSIONS}:
	@echo "; Version Definitions for Oolite" > $@
	@echo "; NOTE - This file is auto-generated by the Makefile, any manual edits will be overwritten" >> $@
	@echo "!define VER_MAJ ${VER_MAJ}" >> $@
	@echo "!define VER_MIN ${VER_MIN}" >> $@
	@echo "!define VER_REV ${VER_REV}" >> $@
	@echo "!define VER_GITREV ${VER_GITREV}" >> $@
	@echo "!define VER_GITHASH ${VER_GITHASH}" >> $@
	@echo "!define VERSION ${VER}" >> $@
	@echo "!define BUILDTIME \"${BUILDTIME}\"" >> $@
	@echo "!define BUILDHOST_IS64BIT 1" >> $@

.PHONY: pkg-win
pkg-win: release ${NSISVERSIONS}
	$(NSIS) installers/win32/OOlite.nsi

.PHONY: pkg-win-deployment
pkg-win-deployment: release-deployment ${NSISVERSIONS}
	@echo "!define DEPLOYMENT 1" >> ${NSISVERSIONS}
	$(NSIS) installers/win32/OOlite.nsi

.PHONY: pkg-win-snapshot
pkg-win-snapshot: release-snapshot ${NSISVERSIONS}
	@echo "!define SNAPSHOT 1" >> ${NSISVERSIONS}
	$(NSIS) installers/win32/OOlite.nsi


