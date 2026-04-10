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
    LIBJS_DIR                    = deps/Linux-deps/x86_64/mozilla
    LIBJS_INC_DIR                = deps/Linux-deps/x86_64/mozilla/include
    ifeq ($(debug),yes)
        LIBJS                    = jsdbg_static
# By default we don't share the debug version of JS library
# If you want to debug into JS, ensure a libjsdbg_static.a exists into $(LIBJS_DIR)
    else
        LIBJS                    = js_static
    endif

    ADDITIONAL_INCLUDE_DIRS      += -I$(LIBJS_INC_DIR) -Isrc/SDL -Isrc/Core -Isrc/BSDCompat -Isrc/Core/Scripting -Isrc/Core/Materials -Isrc/Core/Entities -Isrc/Core/OXPVerifier -Isrc/Core/Debug -Isrc/Core/Tables -Isrc/Core/MiniZip
    ADDITIONAL_OBJC_LIBS         += -lGLU -lGL -lX11 -lSDL -lgnustep-base -L$(LIBJS_DIR) -l$(LIBJS) -lopenal -lz -lvorbisfile -lpng `nspr-config --libs` -lstdc++
    ADDITIONAL_OBJCFLAGS         += -DLINUX -DXP_UNIX `sdl-config --cflags`
    ADDITIONAL_CFLAGS            += -DLINUX `sdl-config --cflags`
    ADDITIONAL_LDFLAGS           += -fuse-ld=bfd  # Force use of ld (ldd and gold don't work. mold also works)

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

