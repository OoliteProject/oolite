#
# This makefile is used to build the Javascript dependency for Oolite
#
# It can be used to make both a release Javascript library and a
# debug library.
include config.make

LIBJS_SRC_DIR                    = deps/Cross-platform-deps/mozilla/js/src
LIBJS_CONFIG_FLAGS               = --disable-shared-js
LIBJS_CONFIG_FLAGS               += --enable-threadsafe
LIBJS_CONFIG_FLAGS               += --with-system-nspr
ifeq ($(OO_JAVASCRIPT_TRACE),yes)
    LIBJS_CONFIG_FLAGS           += --enable-trace-jscalls
endif
ifeq ($(debug),yes)
    LIBJS_BUILD_DIR=$(LIBJS_SRC_DIR)/build-debug
    LIBJS_CONFIG_FLAGS           += --enable-debug
    LIBJS_CONFIG_FLAGS           += --disable-optimize
    LIBJS_BUILD_FLAGS            =
else
    LIBJS_BUILD_DIR              = $(LIBJS_SRC_DIR)/build-release
    LIBJS_BUILD_FLAGS            =
endif
LIBJS                            = $(LIBJS_BUILD_DIR)/libjs_static.a

$(LIBJS): LIBJS_SRC
	@echo
	@echo "Building Javascript library..."
	@echo
	cd $(LIBJS_BUILD_DIR) && ../configure $(LIBJS_CONFIG_FLAGS)
	make -C $(LIBJS_BUILD_DIR) $(LIBJS_BUILD_FLAGS)

.PHONY: LIBJS_SRC
LIBJS_SRC:
	echo "Updating Javascript sources..."
	cd deps/Cocoa-deps/scripts && ./update-mozilla.sh
	mkdir -p $(LIBJS_BUILD_DIR)

.PHONY: clean
clean:
	-make -C $(LIBJS_BUILD_DIR) clean
