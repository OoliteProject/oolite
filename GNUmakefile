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

ifeq ($(GNUSTEP_HOST_OS),mingw32)
	vpath %.rc src/SDL/OOResourcesWin
    oolite_WINDRES_FILES = \
	    OOResourcesWin.rc
	
    WIN_DEPS_DIR                 = deps/Windows-deps/x86_64
    JS_INC_DIR                   = $(WIN_DEPS_DIR)/JS32ECMAv5/include
#     JS_LIB_DIR                   = $(WIN_DEPS_DIR)/JS32ECMAv5/lib
    ifeq ($(debug),yes)
        JS_IMPORT_LIBRARY        = js32ECMAv5dbg
    else
        JS_IMPORT_LIBRARY        = js32ECMAv5
    endif

    ADDITIONAL_INCLUDE_DIRS      = -I$(WIN_DEPS_DIR)/include -I$(JS_INC_DIR) -Isrc/SDL -Isrc/Core -Isrc/BSDCompat -Isrc/Core/Scripting -Isrc/Core/Materials -Isrc/Core/Entities -Isrc/Core/OXPVerifier -Isrc/Core/Debug -Isrc/Core/Tables -Isrc/Core/MiniZip -Isrc/SDL/EXRSnapshotSupport
    ADDITIONAL_OBJC_LIBS         = -L$(WIN_DEPS_DIR)/lib -lglu32 -lopengl32 -lopenal32.dll -lpng14.dll -lmingw32 -lSDLmain -lSDL -lvorbisfile.dll -lvorbis.dll -lz -lgnustep-base -l$(JS_IMPORT_LIBRARY) -lshlwapi -ldwmapi -lwinmm -mwindows
    ADDITIONAL_CFLAGS            = -DWIN32 -DNEED_STRLCPY `sdl-config --cflags` -mtune=generic -DWINVER=0x0601 -D_WIN32_WINNT=0x0601
# note the vpath stuff above isn't working for me, so adding src/SDL and src/Core explicitly
    ADDITIONAL_OBJCFLAGS         = -DLOADSAVEGUI -DWIN32 -DXP_WIN -Wno-import -std=gnu99 `sdl-config --cflags` -mtune=generic -DWINVER=0x0601 -D_WIN32_WINNT=0x0601
#     oolite_LIB_DIRS              += -L$(GNUSTEP_LOCAL_ROOT)/lib -L$(WIN_DEPS_DIR)/lib -L$(JS_LIB_DIR)

    ifeq ($(ESPEAK),yes)
        ADDITIONAL_OBJC_LIBS     += -lespeak.dll
        ADDITIONAL_OBJCFLAGS     +=-DHAVE_LIBESPEAK=1
        GNUSTEP_OBJ_DIR_NAME     := $(GNUSTEP_OBJ_DIR_NAME).spk
    endif
else
    LIBJS_DIR                    = deps/Linux-deps/x86_64/mozilla
    LIBJS_INC_DIR                = deps/Linux-deps/x86_64/mozilla/include
# Uncomment the following lines if you want to build JS from source. Ensure the relevant changes are performed in Makefile too
#     ifeq ($(debug),yes)
#         LIBJS_DIR                    = deps/mozilla/js/src/build-debug
#     else
#         LIBJS_DIR                    = deps/mozilla/js/src/build-release
#     endif
#     LIBJS_INC_DIR                = $(LIBJS_DIR)/dist/include
    ifeq ($(debug),yes)
        LIBJS                    = jsdbg_static 
# By default we don't share the debug version of JS library
# If you want to debug into JS, ensure a libjsdbg_static.a exists into $(LIBJS_DIR) 
    else
        LIBJS                    = js_static
    endif

    ifeq ($(use_deps),yes)
        OOLITE_SHARED_LIBS       = -Ldeps/Linux-deps/x86_64/lib_linker
    endif

    ADDITIONAL_INCLUDE_DIRS      = -I$(LIBJS_INC_DIR) -Isrc/SDL -Isrc/Core -Isrc/BSDCompat -Isrc/Core/Scripting -Isrc/Core/Materials -Isrc/Core/Entities -Isrc/Core/OXPVerifier -Isrc/Core/Debug -Isrc/Core/Tables -Isrc/Core/MiniZip -Ideps/Linux-deps/include 
    ADDITIONAL_OBJC_LIBS         = $(OOLITE_SHARED_LIBS) -lGLU -lGL -lX11 -lSDL -lgnustep-base -L$(LIBJS_DIR) -l$(LIBJS) -lopenal -lz -lvorbisfile -lpng `nspr-config --libs` -lstdc++ 
    ADDITIONAL_OBJCFLAGS         = -Wall -std=gnu99 -DLOADSAVEGUI -DLINUX -DXP_UNIX -Wno-import `sdl-config --cflags` `nspr-config --cflags`
    ADDITIONAL_CFLAGS            = -Wall -DLINUX -DNEED_STRLCPY `sdl-config --cflags` `nspr-config --cflags`

    ifeq ($(ESPEAK),yes)
        ADDITIONAL_OBJC_LIBS     += -lespeak
        ADDITIONAL_OBJCFLAGS     += -DHAVE_LIBESPEAK=1
        GNUSTEP_OBJ_DIR_NAME     := $(GNUSTEP_OBJ_DIR_NAME).spk
    endif
#     oolite_LIB_DIRS              += -L$(LIBJS_LIB_DIR) -L/usr/X11R6/lib/

    ifeq ($(OO_JAVASCRIPT_TRACE),yes)
        ADDITIONAL_OBJCFLAGS     += -DMOZ_TRACE_JSCALLS=1
    endif
endif

# Add flag if building with GNUStep and Clang
ifneq '' '$(GNUSTEP_HOST_OS)'
    ifneq '' '$(findstring clang++,$(CXX))'
        ADDITIONAL_OBJCFLAGS += -fobjc-runtime=gnustep-1.9
    endif
endif

ifeq ($(FEATURE_REQUEST_5496),yes)
	ADDITIONAL_CFLAGS            += -DFEATURE_REQUEST_5496=1
	ADDITIONAL_OBJCFLAGS         += -DFEATURE_REQUEST_5496=1
endif

OBJC_PROGRAM_NAME = oolite

include flags.make
include files.make
ifeq ($(GNUSTEP_HOST_OS),mingw32)
    oolite_C_FILES += \
	miniz.c
endif


include $(GNUSTEP_MAKEFILES)/objc.make
include GNUmakefile.postamble

