include config.make

# Build version string, taking into account that 'VER_REV' may not be set
VERSION     := $(strip $(shell cat src/Cocoa/oolite-version.xcconfig | cut -d '=' -f 2))
VER_MAJ     := $(shell echo "${VERSION}" | cut -d '.' -f 1)
VER_MIN     := $(shell echo "${VERSION}" | cut -d '.' -f 2)
VER_REV     := $(shell echo "${VERSION}" | cut -d '.' -f 3)
VER_REV     := $(if ${VER_REV},${VER_REV},0)
VER_DATE	:= $(shell date +%y%m%d)
# VER_GITREV: Make sure git is in the command path
# VER_GITREV is the count of commits since the establishment of the repository on github. Used
# as replacement for SVN incremental revision number, since we require the version number to be
# of format X.X.X.X.
# VER_GITHASH are the first ten digits of the actual hash of the commit being built.
VER_GITREV	:= $(shell git rev-list --count HEAD)
VER_GITHASH	:= $(shell git rev-parse --short=10 HEAD)
VER         := $(shell echo "${VER_MAJ}.${VER_MIN}.${VER_REV}.${VER_GITREV}-${VER_DATE}")
BUILDTIME   := $(shell date "+%Y.%m.%d %H:%M")
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

ifeq ($(GNUSTEP_HOST_OS),mingw32)
    ifeq ($(GNUSTEP_HOST_CPU),x86_64)
        LIBJS                        = deps/Windows-deps/x86_64/DLLs/js32ECMAv5.dll
        LIBJS_DBG                    = deps/Windows-deps/x86_64/DLLs/js32ECMAv5.dll
	else
        LIBJS                        = deps/Windows-deps/x86/DLLs/js32ECMAv5.dll
        LIBJS_DBG                    = deps/Windows-deps/x86/DLLs/js32ECMAv5.dll
	endif
    DEPS                         = $(LIBJS)
    DEPS_DBG                     = $(LIBJS_DBG)
else
    # define autopackage .apspec file according to the CPU architecture
    HOST_ARCH                    := $(shell echo $(GNUSTEP_HOST_CPU) | sed -e s/i.86/x86/ -e s/amd64/x86_64/ )
    ifeq ($(HOST_ARCH),x86_64)
       APSPEC_FILE               = installers/autopackage/default.x86_64.apspec
    else
        APSPEC_FILE              = installers/autopackage/default.x86.apspec
    endif

    DEPS                         = LIBJS
    DEPS_DBG                     = LIBJS_DBG
endif


# Here are our default targets
#
.PHONY: debug
debug: $(DEPS_DBG)
	$(MAKE) -f GNUmakefile debug=yes
	mkdir -p AddOns && rm -rf AddOns/Basic-debug.oxp && cp -rf DebugOXP/Debug.oxp AddOns/Basic-debug.oxp

.PHONY: release
release: $(DEPS)
	$(MAKE) -f GNUmakefile debug=no
	mkdir -p AddOns && rm -rf AddOns/Basic-debug.oxp && cp -rf DebugOXP/Debug.oxp AddOns/Basic-debug.oxp

.PHONY: release-deployment
release-deployment: $(DEPS)
	$(MAKE) -f GNUmakefile DEPLOYMENT_RELEASE_CONFIGURATION=yes debug=no

.PHONY: release-snapshot
release-snapshot: $(DEPS)
	$(MAKE) -f GNUmakefile SNAPSHOT_BUILD=yes VERSION_STRING=$(VER) debug=no
	mkdir -p AddOns && rm -rf AddOns/Basic-debug.oxp && cp -rf DebugOXP/Debug.oxp AddOns/Basic-debug.oxp

# Here are targets using the provided dependencies
.PHONY: deps-debug
deps-debug: $(DEPS_DBG)
	$(MAKE) -f GNUmakefile debug=yes use_deps=yes
	mkdir -p AddOns && rm -rf AddOns/Basic-debug.oxp && cp -rf DebugOXP/Debug.oxp AddOns/Basic-debug.oxp

.PHONY: deps-release
deps-release: $(DEPS)
	$(MAKE) -f GNUmakefile debug=no use_deps=yes
	mkdir -p AddOns && rm -rf AddOns/Basic-debug.oxp && cp -rf DebugOXP/Debug.oxp AddOns/Basic-debug.oxp


.PHONY: deps-release-deployment
deps-release-deployment: $(DEPS)
	$(MAKE) -f GNUmakefile DEPLOYMENT_RELEASE_CONFIGURATION=yes debug=no use_deps=yes

.PHONY: deps-release-snapshot
deps-release-snapshot: $(DEPS)
	$(MAKE) -f GNUmakefile SNAPSHOT_BUILD=yes VERSION_STRING=$(VER) debug=no use_deps=yes
	mkdir -p AddOns && rm -rf AddOns/Basic-debug.oxp && cp -rf DebugOXP/Debug.oxp AddOns/Basic-debug.oxp

.PHONY: LIBJS_DBG
LIBJS_DBG:
ifeq ($(GNUSTEP_HOST_OS),mingw32)
	@echo "ERROR - this Makefile can't (yet) build the Javascript DLL"
	@echo "        Please build it yourself and copy it to $(LIBJS_DBG)."
	false
endif
	$(MAKE) -f libjs.make debug=yes

.PHONY: LIBJS
LIBJS:
ifeq ($(GNUSTEP_HOST_OS),mingw32)
	@echo "ERROR - this Makefile can't (yet) build the Javascript DLL"
	@echo "        Please build it yourself and copy it to $(LIBJS)."
	false
endif
	$(MAKE) -f libjs.make debug=no

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
#	        installers/posix/make_installer.sh $(HOST_ARCH) $(VER) "debug"
#
pkg-posix:
	installers/posix/make_installer.sh $(HOST_ARCH) $(VER) "release-deployment" ""

pkg-posix-test:
	installers/posix/make_installer.sh $(HOST_ARCH) $(VER) "release" ""

pkg-posix-snapshot:
	installers/posix/make_installer.sh $(HOST_ARCH) $(VER) "release-snapshot" ""

pkg-posix-nightly:
	installers/posix/make_installer.sh $(HOST_ARCH) $(VER) "release-snapshot" "nightly"

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

# And here are our Windows packager targets
#
NSIS=/nsis/makensis.exe
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

.PHONY: help
help:
	@echo "This is a helper-Makefile to make compiling Oolite easier."
	@echo
	@echo "NOTE (Linux): To build with the dependency libraries provided with Oolite"
	@echo "              source, use 'deps-' prefix with debug, release, release-snapshot"
	@echo "              and release-deployment build options."
	@echo
	@echo "Development Targets:"
	@echo "  debug               - builds a debug executable in oolite.app/oolite.dbg"
	@echo "  release             - builds a release executable in oolite.app/oolite"
	@echo "  release-deployment  - builds a release executable in oolite.app/oolite"
	@echo "  release-snapshot    - builds a snapshot release in oolite.app/oolite"
	@echo "  all                 - builds the above targets"
	@echo "  clean               - removes all generated files"
	@echo
	@echo "Packaging Targets:"
	@echo " Linux (debian):"
	@echo "  pkg-deb             - builds a release Debian package"
	@echo "  pkg-debtest         - builds a test release Debian package"
	@echo "  pkg-debsnapshot     - builds a snapshot release Debian package"
	@echo "  pkg-debclean        - cleans up after a Debian package build"
	@echo
	@echo " POSIX (e.g. FreeBSD, Linux etc.):"
	@echo "  pkg-autopackage     - builds an autopackage (http://autopackage.org) package"
	@echo
	@echo "  pkg-posix           - builds a release self-extracting package"
	@echo "  pkg-posix-test      - builds a test release self-extracting package"
	@echo "  pkg-posix-snapshot  - builds a snapshot release self-extracting package"
	@echo "  pkg-posix-nightly   - builds a snapshot release self-extracting package for the nightly build"
	@echo
	@echo " Windows Installer:"
	@echo "  pkg-win             - builds a test-release version"
	@echo "  pkg-win-deployment  - builds a release version"
	@echo "  pkg-win-snapshot    - builds a snapshot version"
