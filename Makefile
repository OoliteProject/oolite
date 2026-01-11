include config.make

.PHONY: help
help:
	@echo "This is a helper-Makefile to make compiling Oolite easier."
	@echo "Below you will find a list of available build targets."
	@echo "Syntax: make -f Makefile [build target]"
	@echo "Usage example: make -f Makefile release"
	@echo
	@echo "Development Targets:"
	@echo "  release                  - builds a test release executable in oolite.app/oolite"
	@echo "  release-deployment       - builds a release executable in oolite.app/oolite"
	@echo "  release-snapshot         - builds a snapshot release in oolite.app/oolite"
	@echo "  debug                    - builds a debug executable in oolite.app/oolite.dbg"
	@echo "  all                      - builds the above targets"
	@echo "  clean                    - removes all generated files"
	@echo
	@echo "Packaging Targets:"
	@echo
	@echo " Linux AppImage:"
	@echo "  pkg-appimage            - builds a test-release appimage"
	@echo "  pkg-appimage-deployment - builds a release appimage"
	@echo "  pkg-appimage-snapshot   - builds a snapshot appimage"
	@echo
	@echo " Windows NSIS Installer:"
	@echo "  pkg-win                 - builds a test-release version"
	@echo "  pkg-win-deployment      - builds a release version"
	@echo "  pkg-win-snapshot        - builds a snapshot version"


# Here are our default targets
#
.PHONY: release
release:
	$(MAKE) -f GNUmakefile debug=no strip=yes lto=yes
	mkdir -p AddOns && rm -rf AddOns/Basic-debug.oxp && cp -rf DebugOXP/Debug.oxp AddOns/Basic-debug.oxp

.PHONY: release-deployment
release-deployment:
	$(MAKE) -f GNUmakefile DEPLOYMENT_RELEASE_CONFIGURATION=yes debug=no strip=yes lto=yes

.PHONY: release-snapshot
release-snapshot:
	$(MAKE) -f GNUmakefile SNAPSHOT_BUILD=yes VERSION_STRING=$(VER) debug=no
	mkdir -p AddOns && rm -rf AddOns/Basic-debug.oxp && cp -rf DebugOXP/Debug.oxp AddOns/Basic-debug.oxp

.PHONY: debug
debug:
	$(MAKE) -f GNUmakefile debug=yes strip=no
	mkdir -p AddOns && rm -rf AddOns/Basic-debug.oxp && cp -rf DebugOXP/Debug.oxp AddOns/Basic-debug.oxp

.PHONY: clean
clean:
	$(MAKE) -f GNUmakefile clean
	$(RM) -rf oolite.app
	$(RM) -rf AddOns 

.PHONY: all
all: release release-deployment release-snapshot debug

.PHONY: remake
remake: clean all

# Here are our AppImage targets
#
.PHONY: pkg-appimage
pkg-appimage: release
	installers/appimage/create_appimage.sh "test"

.PHONY: pkg-appimage-deployment
pkg-appimage-deployment: release-deployment
	installers/appimage/create_appimage.sh

.PHONY: pkg-appimage-snapshot
pkg-appimage-snapshot: release-snapshot
	installers/appimage/create_appimage.sh "dev"

# And here are our NSIS targets
#
.PHONY: pkg-win
pkg-win: release
	installers/win32/create_nsis.sh "test"

.PHONY: pkg-win-deployment
pkg-win-deployment: release-deployment
	installers/win32/create_nsis.sh

.PHONY: pkg-win-snapshot
pkg-win-snapshot: release-snapshot
	installers/win32/create_nsis.sh "dev"
