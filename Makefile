# Use bash as the explicit shell and enable strict error handling for safety
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

NATIVE_FILE ?= clang.ini

# Modern, self-documenting help target. 
# It parses the '##' comments next to targets automatically.
.PHONY: help
help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}'

# Macro for Meson workflow
define meson_build
	meson setup build/meson_$(2) $(1) --native-file $(NATIVE_FILE) --reconfigure 2>/dev/null || meson setup build/meson_$(2) $(1) --native-file $(NATIVE_FILE)
	meson compile -C build/meson_$(2)
endef
#	meson install -C build/meson_$(2)

# Helper macro for syncing OXP files cleanly
define sync_debug_oxp
	mkdir -p build/meson_$(1)/oolite.app/AddOns
	rm -rf build/meson_$(1)/oolite.app/AddOns/Basic-debug.oxp
	cp -rf DebugOXP/Debug.oxp build/meson_$(1)/oolite.app/AddOns/Basic-debug.oxp
endef

##
## Development Targets
##

.PHONY: release
release: ## Build a test release executable
	$(call meson_build,-Ddebug=false -Dstrip_bin=true -Db_lto=true,release)
	$(call sync_debug_oxp,release)

.PHONY: release-deployment
release-deployment: ## Build a release deployment executable
	$(call meson_build,-Ddeployment_release_configuration=true -Ddebug=false -Dstrip_bin=true -Db_lto=true,deployment)

.PHONY: release-snapshot
release-snapshot: ## Build a snapshot release executable
	$(call meson_build,-Dsnapshot_build=true -Ddebug=false -Dstrip_bin=false,snapshot)
	$(call sync_debug_oxp,snapshot)

.PHONY: debug
debug: ## Build a debug executable
	$(call meson_build,-Ddebug=true -Dstrip_bin=false,debug)
	$(call sync_debug_oxp,debug)

.PHONY: test
test: release-snapshot ## Run test suite
	tests/run_test.sh

.PHONY: clean
clean: ## Remove all generated build artifacts
	$(RM) -rf build/meson_*

.PHONY: all
all: release release-deployment release-snapshot debug ## Build all standard development targets

.PHONY: remake
remake: clean all

##
## Packaging Targets
##

.PHONY: pkg-flatpak
pkg-flatpak: ## Package a Flatpak application
	./installers/flatpak/create_flatpak.sh

.PHONY: pkg-appimage
pkg-appimage: release ## Package a test release AppImage
	installers/appimage/create_appimage.sh meson_release/oolite.app "test"

.PHONY: pkg-appimage-deployment
pkg-appimage-deployment: release-deployment ## Package a deployment AppImage
	installers/appimage/create_appimage.sh meson_deployment/oolite.app

.PHONY: pkg-appimage-snapshot
pkg-appimage-snapshot: release-snapshot ## Package a snapshot AppImage
	installers/appimage/create_appimage.sh meson_snapshot/oolite.app "dev"

.PHONY: pkg-win
pkg-win: release ## Package a Windows NSIS test release installer
	installers/win32/create_nsis.sh meson_release/oolite.app "test"

.PHONY: pkg-win-deployment
pkg-win-deployment: release-deployment ## Package a Windows NSIS deployment installer
	installers/win32/create_nsis.sh meson_deployment/oolite.app

.PHONY: pkg-win-snapshot
pkg-win-snapshot: release-snapshot ## Package a Windows NSIS snapshot installer
	installers/win32/create_nsis.sh meson_snapshot/oolite.app "dev"