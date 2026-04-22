include $(GNUSTEP_MAKEFILES)/common.make
include config.make

vpath %.m src/SDL:src/Core:src/Core/Entities:src/Core/Materials:src/Core/Scripting:src/Core/OXPVerifier:src/Core/Debug
vpath %.h src/SDL:src/Core:src/Core/Entities:src/Core/Materials:src/Core/Scripting:src/Core/OXPVerifier:src/Core/Debug:src/Core/MiniZip
vpath %.c src/SDL:src/Core:src/BSDCompat:src/Core/Debug:src/Core/MiniZip:src/SDL/EXRSnapshotSupport
vpath %.cpp src/SDL/EXRSnapshotSupport
GNUSTEP_INSTALLATION_DIR         = $(GNUSTEP_USER_ROOT)
ifeq ($(GNUSTEP_HOST_OS),mingw32)
    GNUSTEP_OBJ_DIR_NAME         := $(GNUSTEP_OBJ_DIR_NAME).win
endif
GNUSTEP_OBJ_DIR_BASENAME         := $(GNUSTEP_OBJ_DIR_NAME)

COMPILER_TYPE                    := $(shell $(CC) -dM -E - < /dev/null | grep -q "__clang__" && echo "clang" || echo "gcc")
ifeq ($(COMPILER_TYPE),gcc)
    $(info Detected: GCC build)
else
    $(info Detected: Clang build)
endif

ifeq ($(GNUSTEP_HOST_OS),mingw32)
	vpath %.rc src/SDL/OOResourcesWin

    WIN_DEPS_DIR                 = deps/Windows-deps/x86_64
    JS_INC_DIR                   = $(WIN_DEPS_DIR)/JS32ECMAv5/include
    JS_LIB_DIR                   = $(WIN_DEPS_DIR)/JS32ECMAv5/lib
    ifeq ($(debug),yes)
        JS_IMPORT_LIBRARY            = js32ECMAv5dbg.dll  # to use jsdbg, gcc builds need ADDITIONAL_CFLAGS, ADDITIONAL_OBJCFLAGS: -DSTATIC_JS_API
    else
        JS_IMPORT_LIBRARY            = js
    endif

    SPEECH_LIBRARY_NAME          = espeak-ng
    OPENAL_LIBRARY_NAME          = openal
    LIBPNG_LIBRARY_NAME          = png

    ADDITIONAL_INCLUDE_DIRS      += -Isrc/SDL -Isrc/Core -Isrc/BSDCompat -Isrc/Core/Scripting -Isrc/Core/Materials -Isrc/Core/Entities -Isrc/Core/OXPVerifier -Isrc/Core/Debug -Isrc/Core/Tables -Isrc/Core/MiniZip -Isrc/SDL/EXRSnapshotSupport
    ADDITIONAL_OBJC_LIBS         += -lglu32 -lopengl32 -l$(OPENAL_LIBRARY_NAME).dll -l$(LIBPNG_LIBRARY_NAME).dll -lmingw32 -lSDLmain -lSDL -lvorbisfile.dll -lvorbis.dll -lz -lgnustep-base -l$(JS_IMPORT_LIBRARY) -lnspr4 -lshlwapi -ldwmapi -lwinmm -mwindows
    ADDITIONAL_CFLAGS            += -DWIN32 -DNEED_STRLCPY `sdl-config --cflags` -mtune=generic -DWINVER=0x0A00 -D_WIN32_WINNT=0x0A00 -DNTDDI_VERSION=0x0A00000F
# note the vpath stuff above isn't working for me, so adding src/SDL and src/Core explicitly
    ADDITIONAL_OBJCFLAGS         += -DLOADSAVEGUI -DWIN32 -DXP_WIN -Wno-import -std=gnu99 `sdl-config --cflags` -mtune=generic -DWINVER=0x0A00 -D_WIN32_WINNT=0x0A00 -DNTDDI_VERSION=0x0A00000F
#     oolite_LIB_DIRS              += -L$(GNUSTEP_LOCAL_ROOT)/lib -L$(WIN_DEPS_DIR)/lib -L$(JS_LIB_DIR)

    ifeq ($(ESPEAK),yes)
        ADDITIONAL_OBJC_LIBS     += -l$(SPEECH_LIBRARY_NAME).dll
        ADDITIONAL_OBJCFLAGS     +=-DHAVE_LIBESPEAK=1
        GNUSTEP_OBJ_DIR_NAME     := $(GNUSTEP_OBJ_DIR_NAME).spk
    endif

#   Clang can generate .pdb files compatible with native Windows debug tools
    ifeq ($(COMPILER_TYPE),clang)
        ifeq ($(pdb),yes)
            ADDITIONAL_CFLAGS    += -g -gcodeview
            ADDITIONAL_OBJCFLAGS += -g -gcodeview
            ADDITIONAL_CCFLAGS   += -g -gcodeview
            ADDITIONAL_LDFLAGS   += -Wl,-pdb= 
        endif
    endif

else

    ifeq ($(debug),yes)
        LIBJS = jsdbg_static
    else
        LIBJS = js_static
    endif

    # 2. Define the search roots (highest priority first)
    SEARCH_ROOTS = \
        build/mozilla_js \
        $(HOME)/.local \
        /usr/local \
        /app

    # 3. Find the first path that contains the SPECIFIC library we need (js_static vs jsdbg_static)
    # We check both 'lib' and 'lib64' inside each root to handle Fedora vs Kubuntu/Arch
    FOUND_LIB_DIR := $(firstword $(foreach root,$(SEARCH_ROOTS), \
        $(if $(wildcard $(root)/lib/lib$(LIBJS).a),$(root)/lib,) \
        $(if $(wildcard $(root)/lib64/lib$(LIBJS).a),$(root)/lib64,) \
    ))

    # 4. If a valid library directory is found, sync the include folder
    ifneq ($(FOUND_LIB_DIR),)
        # abspath cleans up the path (e.g., build/mozilla_js/lib/../include becomes build/mozilla_js/include)
        FOUND_INC_DIR := $(abspath $(FOUND_LIB_DIR)/../include)

        ADDITIONAL_INCLUDE_DIRS  += -I$(FOUND_INC_DIR)
        ADDITIONAL_OBJC_LIBS     += -L$(FOUND_LIB_DIR)
    endif

    ADDITIONAL_INCLUDE_DIRS      += -Isrc/SDL -Isrc/Core -Isrc/BSDCompat -Isrc/Core/Scripting -Isrc/Core/Materials -Isrc/Core/Entities -Isrc/Core/OXPVerifier -Isrc/Core/Debug -Isrc/Core/Tables -Isrc/Core/MiniZip
    ADDITIONAL_OBJC_LIBS         += -lGLU -lGL -lX11 -lSDL3 -lgnustep-base -l$(LIBJS) -lopenal -lz -lvorbisfile -lpng `nspr-config --libs` -lstdc++
    ADDITIONAL_OBJCFLAGS         += -DLINUX -DXP_UNIX `sdl-config --cflags`
    ADDITIONAL_CFLAGS            += -DLINUX `sdl-config --cflags`
    ADDITIONAL_LDFLAGS           += -Wl,-rpath,'$$ORIGIN'

    ifeq ($(ESPEAK),yes)
        ADDITIONAL_OBJC_LIBS     += -lespeak-ng
        ADDITIONAL_OBJCFLAGS     += -DHAVE_LIBESPEAK=1
        GNUSTEP_OBJ_DIR_NAME     := $(GNUSTEP_OBJ_DIR_NAME).spk
    endif

    ifeq ($(OO_JAVASCRIPT_TRACE),yes)
        ADDITIONAL_OBJCFLAGS     += -DMOZ_TRACE_JSCALLS=1
    endif

    ifeq ($(COMPILER_TYPE),gcc)
        ADDITIONAL_OBJCFLAGS     += -std=gnu99 -Wall -Wno-import `nspr-config --cflags` -DLOADSAVEGUI
        ADDITIONAL_CFLAGS        += -Wall `nspr-config --cflags` -DNEED_STRLCPY
        ADDITIONAL_LDFLAGS       += -fuse-ld=bfd
    else
        ADDITIONAL_LDFLAGS       += -fuse-ld=lld
    endif
endif

VER_FULL := $(shell ./ShellScripts/common/get_version.sh)
ADDITIONAL_CFLAGS        += -DOO_VERSION_FULL=\"$(VER_FULL)\"
ADDITIONAL_OBJCFLAGS     += -DOO_VERSION_FULL=\"$(VER_FULL)\"
#   link time optimizations
ifeq ($(lto),yes)
    ADDITIONAL_CFLAGS        += -flto
    ADDITIONAL_OBJCFLAGS     += -flto
    ADDITIONAL_CCFLAGS       += -flto
    ADDITIONAL_LDFLAGS       += -flto
endif

OBJC_PROGRAM_NAME = oolite

include flags.make
include files.make


include $(GNUSTEP_MAKEFILES)/objc.make
include GNUmakefile.postamble

