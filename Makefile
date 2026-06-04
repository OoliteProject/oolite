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


NATIVE_FILE ?= clang.ini

# Arguments: 1 = extra meson setup options, 2 = build directory suffix
define meson_build
	meson setup build/meson_$(2) $(1) --native-file $(NATIVE_FILE)
	meson compile -C build/meson_$(2)
	meson install -C build/meson_$(2)
endef

# Here are our default targets
#
.PHONY: release
release:
	$(call meson_build,-Ddebug=false -Dstrip_bin=true -Db_lto=true,release)
	mkdir -p build/meson_release/oolite.app/AddOns && \
	rm -rf build/meson_release/oolite.app/AddOns/Basic-debug.oxp && \
	cp -rf DebugOXP/Debug.oxp build/meson_release/oolite.app/AddOns/Basic-debug.oxp

.PHONY: release-deployment
release-deployment:
	$(call meson_build,-Ddeployment_release_configuration=true -Ddebug=false -Dstrip_bin=true -Db_lto=true,deployment)

.PHONY: release-snapshot
release-snapshot:
	$(call meson_build,-Dsnapshot_build=true -Ddebug=false -Dstrip_bin=false,snapshot)
	mkdir -p build/meson_snapshot/oolite.app/AddOns && \
	rm -rf build/meson_snapshot/oolite.app/AddOns/Basic-debug.oxp && \
	cp -rf DebugOXP/Debug.oxp build/meson_snapshot/oolite.app/AddOns/Basic-debug.oxp

.PHONY: debug
debug:
	$(call meson_build,-Ddebug=true -Dstrip_bin=false,debug)
	mkdir -p build/meson_debug/oolite.app/AddOns && \
	rm -rf build/meson_debug/oolite.app/AddOns/Basic-debug.oxp && \
	cp -rf DebugOXP/Debug.oxp build/meson_debug/oolite.app/AddOns/Basic-debug.oxp

.PHONY: test
test: release-snapshot
	tests/run_test.sh

.PHONY: clean
clean:
	$(RM) -rf build/meson_*

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
