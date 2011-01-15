include $(GNUSTEP_MAKEFILES)/common.make
VERBOSE = yes
CP = cp

# Setting the build parameters independently. We need everything set as below for the full test release configuration.
BUILD_WITH_DEBUG_FUNCTIONALITY = yes
NO_SHADERS = no
DOCKING_CLEARANCE = yes
PROCEDURAL_PLANETS = yes
WORMHOLE_SCANNER = yes
TARGET_INCOMING_MISSILES = yes
ESPEAK = yes
OO_CHECK_GL_HEAVY = no
OO_EXCLUDE_DEBUG_SUPPORT = no
OO_OXP_VERIFIER_ENABLED = yes
OO_LOCALIZATION_TOOLS = yes
DEBUG_GRAPHVIZ = yes
JS_ECMAv5 = yes
# use_deps = no

vpath %.m src/SDL:src/Core:src/Core/Entities:src/Core/Materials:src/Core/Scripting:src/Core/OXPVerifier:src/Core/Debug
vpath %.h src/SDL:src/Core:src/Core/Entities:src/Core/Materials:src/Core/Scripting:src/Core/OXPVerifier:src/Core/Debug
vpath %.c src/SDL:src/Core:src/BSDCompat:src/Core/Debug
GNUSTEP_INSTALLATION_DIR = $(GNUSTEP_USER_ROOT)
GNUSTEP_OBJ_DIR_BASENAME := $(GNUSTEP_OBJ_DIR_NAME)
HOST_ARCH := $(shell echo $(GNUSTEP_HOST_CPU) | sed -e s/i.86/x86/ -e s/amd64/x86_64/ )
ifeq ($(GNUSTEP_HOST_OS),mingw32)
	ifeq ($(JS_ECMAv5),yes)
		JS_INCLUDE_DIR = deps/Windows-x86-deps/JS32ECMAv5/include
		JS_LIB_DIR = deps/Windows-x86-deps/JS32ECMAv5/lib
		ifeq ($(debug),yes)
			JS_IMPORT_LIBRARY = js32ECMAv5dbg
		else
			JS_IMPORT_LIBRARY = js32ECMAv5
		endif
	else
		JS_INCLUDE_DIR = deps/Cross-platform-deps/SpiderMonkey/js/src
		JS_LIB_DIR =
		JS_IMPORT_LIBRARY = js32
	endif
	ADDITIONAL_INCLUDE_DIRS = -Ideps/Windows-x86-deps/include -I$(JS_INCLUDE_DIR) -Isrc/SDL -Isrc/Core -Isrc/BSDCompat -Isrc/Core/Scripting -Isrc/Core/Materials -Isrc/Core/Entities -Isrc/Core/OXPVerifier -Isrc/Core/Debug -Isrc/Core/Tables
	ADDITIONAL_OBJC_LIBS = -lglu32 -lopengl32 -lpng14.dll -lmingw32 -lSDLmain -lSDL -lSDL_mixer -lgnustep-base -l$(JS_IMPORT_LIBRARY) -lwinmm -mwindows
	ADDITIONAL_CFLAGS = -DWIN32 -DNEED_STRLCPY `sdl-config --cflags`
# note the vpath stuff above isn't working for me, so adding src/SDL and src/Core explicitly
	ADDITIONAL_OBJCFLAGS = -DLOADSAVEGUI -DWIN32 -DXP_WIN -Wno-import `sdl-config --cflags`
	oolite_LIB_DIRS += -L/usr/local/lib -L$(GNUSTEP_LOCAL_ROOT)/lib -Ldeps/Windows-x86-deps/lib -L$(JS_LIB_DIR)
	ifeq ($(ESPEAK),yes)
		ADDITIONAL_OBJC_LIBS += -lespeak.dll
		ADDITIONAL_OBJCFLAGS+=-DHAVE_LIBESPEAK=1
		GNUSTEP_OBJ_DIR_NAME := $(GNUSTEP_OBJ_DIR_NAME).spk
	endif
	ifeq ($(JS_ECMAv5),yes)
		ADDITIONAL_OBJCFLAGS+=-DOO_NEW_JS=1
	endif
else
	ifeq ($(use_newjs),yes)
		LIBJS_SRC_DIR = deps/Linux-deps/JS32ECMAv5/$(HOST_ARCH)/include
		LIBJS_BIN_DIR = deps/Linux-deps/JS32ECMAv5/$(HOST_ARCH)/lib/
		ifeq ($(debug),no)
			JS_IMPORT_LIBRARY = libjs_static.a # this is the release optimized version of libmozjs
		else
			JS_IMPORT_LIBRARY = libmozjs.so # this is for the debug version of libmozjs (not yet used)
		endif
	else
		LIBJS_SRC_DIR = deps/Cross-platform-deps/SpiderMonkey/js/src
		ifeq ($(JS_OPT),no)
			LIBJS_BIN_DIR=$(LIBJS_SRC_DIR)/Linux_All_DBG.OBJ
		else
			LIBJS_BIN_DIR=$(LIBJS_SRC_DIR)/Linux_All_OPT.OBJ
		endif
		JS_IMPORT_LIBRARY = libjs.a
	endif
	ADDITIONAL_INCLUDE_DIRS = -I$(LIBJS_SRC_DIR)  -I$(LIBJS_BIN_DIR) -Isrc/SDL -Isrc/Core -Isrc/BSDCompat -Isrc/Core/Scripting -Isrc/Core/Materials -Isrc/Core/Entities -Isrc/Core/OXPVerifier -Isrc/Core/Debug
	ADDITIONAL_OBJC_LIBS = $(LIBJS_BIN_DIR)/$(JS_IMPORT_LIBRARY) -lGLU -lGL -lX11
	ADDITIONAL_CFLAGS = -Wall -DLINUX -DNEED_STRLCPY `sdl-config --cflags`
	ADDITIONAL_OBJCFLAGS = -Wall -std=c99 -DLOADSAVEGUI -DLINUX -DXP_UNIX -Wno-import `sdl-config --cflags`
	oolite_LIB_DIRS += -L/usr/X11R6/lib/

	ifeq ($(use_deps),yes)
		oolite_LIB_DIRS += -Ldeps/Linux-deps/$(HOST_ARCH)/lib_linker
		ADDITIONAL_OBJC_LIBS += -lpng14 -lSDL_mixer -lSDL -lgnustep-base
		ADDITIONAL_INCLUDE_DIRS += -Ideps/Linux-deps/include
		ifeq ($(ESPEAK),yes)
			ADDITIONAL_OBJC_LIBS += -lespeak
			ADDITIONAL_OBJCFLAGS+=-DHAVE_LIBESPEAK=1
			GNUSTEP_OBJ_DIR_NAME := $(GNUSTEP_OBJ_DIR_NAME).spk
		endif
	else
		ADDITIONAL_OBJC_LIBS += -lpng -lSDL -lSDL_mixer -lgnustep-base
		ifeq ($(ESPEAK),yes)
			ADDITIONAL_OBJC_LIBS += -lespeak
			ADDITIONAL_OBJCFLAGS+=-DHAVE_LIBESPEAK=1
			GNUSTEP_OBJ_DIR_NAME := $(GNUSTEP_OBJ_DIR_NAME).spk
		endif
	endif

	ifeq ($(use_newjs),yes)
		ADDITIONAL_OBJCFLAGS+=-DOO_NEW_JS=1
	endif
endif

ifeq ($(profile),yes)
	ADDITIONAL_CFLAGS += -g -pg
	ADDITIONAL_OBJCFLAGS += -g -pg
endif
ifeq ($(debug),yes)
	ADDITIONAL_CFLAGS += -g -O0
	ADDITIONAL_OBJCFLAGS += -g -O0
	GNUSTEP_OBJ_DIR_NAME := $(GNUSTEP_OBJ_DIR_NAME).dbg
	ADDITIONAL_CFLAGS += -DDEBUG -DOO_DEBUG
	ADDITIONAL_OBJCFLAGS += -DDEBUG -DOO_DEBUG
endif

# these are common settings for both test and deployment release configurations
ifeq ($(NO_SHADERS),yes)
	ADDITIONAL_CFLAGS += -DNO_SHADERS=1
	ADDITIONAL_OBJCFLAGS += -DNO_SHADERS=1
endif
ifeq ($(PROCEDURAL_PLANETS),yes)
	ADDITIONAL_CFLAGS += -DALLOW_PROCEDURAL_PLANETS=1
	ADDITIONAL_OBJCFLAGS += -DALLOW_PROCEDURAL_PLANETS=1
endif
ifeq ($(DOCKING_CLEARANCE),yes)
	ADDITIONAL_CFLAGS += -DDOCKING_CLEARANCE_ENABLED=1
	ADDITIONAL_OBJCFLAGS += -DDOCKING_CLEARANCE_ENABLED=1
endif
ifeq ($(WORMHOLE_SCANNER),yes)
	ADDITIONAL_CFLAGS += -DWORMHOLE_SCANNER=1
	ADDITIONAL_OBJCFLAGS += -DWORMHOLE_SCANNER=1
endif
ifeq ($(TARGET_INCOMING_MISSILES),yes)
	ADDITIONAL_CFLAGS += -DTARGET_INCOMING_MISSILES=1
	ADDITIONAL_OBJCFLAGS += -DTARGET_INCOMING_MISSILES=1
endif

# DEPLOYMENT_RELEASE_CONFIGURATION value is passed from Makefile. Note that the deployment release settings
# are forced, while test release settings are adjustable.
ifeq ($(DEPLOYMENT_RELEASE_CONFIGURATION),yes)
	ADDITIONAL_CFLAGS += -DNDEBUG
	ADDITIONAL_OBJCFLAGS += -DNDEBUG
	ADDITIONAL_CFLAGS += -DOO_CHECK_GL_HEAVY=0
	ADDITIONAL_OBJCFLAGS += -DOO_CHECK_GL_HEAVY=0
	ADDITIONAL_CFLAGS += -DOO_EXCLUDE_DEBUG_SUPPORT=1
	ADDITIONAL_OBJCFLAGS += -DOO_EXCLUDE_DEBUG_SUPPORT=1
	ADDITIONAL_CFLAGS += -DOO_OXP_VERIFIER_ENABLED=0
	ADDITIONAL_OBJCFLAGS += -DOO_OXP_VERIFIER_ENABLED=0
	ADDITIONAL_CFLAGS += -DOO_LOCALIZATION_TOOLS=0
	ADDITIONAL_OBJCFLAGS += -DOO_LOCALIZATION_TOOLS=0
	ADDITIONAL_CFLAGS += -DDEBUG_GRAPHVIZ=0
	ADDITIONAL_OBJCFLAGS += -DDEBUG_GRAPHVIZ=0
else
	ifeq ($(BUILD_WITH_DEBUG_FUNCTIONALITY),no)
		ADDITIONAL_CFLAGS += -DNDEBUG
		ADDITIONAL_OBJCFLAGS += -DNDEBUG
	endif
	ifeq ($(OO_CHECK_GL_HEAVY),yes)
		ADDITIONAL_CFLAGS += -DOO_CHECK_GL_HEAVY=1
		ADDITIONAL_OBJCFLAGS += -DOO_CHECK_GL_HEAVY=1
	endif
	ifeq ($(OO_EXCLUDE_DEBUG_SUPPORT),yes)
		ADDITIONAL_CFLAGS += -DOO_EXCLUDE_DEBUG_SUPPORT=1
		ADDITIONAL_OBJCFLAGS += -DOO_EXCLUDE_DEBUG_SUPPORT=1
	endif
	ifeq ($(OO_OXP_VERIFIER_ENABLED),yes)
		ADDITIONAL_CFLAGS += -DOO_OXP_VERIFIER_ENABLED=1
		ADDITIONAL_OBJCFLAGS += -DOO_OXP_VERIFIER_ENABLED=1
	endif
	ifeq ($(OO_LOCALIZATION_TOOLS),yes)
		ADDITIONAL_CFLAGS += -DOO_LOCALIZATION_TOOLS=1
		ADDITIONAL_OBJCFLAGS += -DOO_LOCALIZATION_TOOLS=1
	endif
	ifeq ($(DEBUG_GRAPHVIZ),yes)
		ADDITIONAL_CFLAGS += -DDEBUG_GRAPHVIZ=1
		ADDITIONAL_OBJCFLAGS += -DDEBUG_GRAPHVIZ=1
	endif
endif

ifeq ($(SNAPSHOT_BUILD), yes)
	ADDITIONAL_CFLAGS += -DSNAPSHOT_BUILD -DOOLITE_SNAPSHOT_VERSION=\"$(VERSION_STRING)\"
	ADDITIONAL_OBJCFLAGS += -DSNAPSHOT_BUILD -DOOLITE_SNAPSHOT_VERSION=\"$(VERSION_STRING)\"
endif

OBJC_PROGRAM_NAME = oolite

oolite_C_FILES = \
	legacy_random.c \
	strlcpy.c \
	OOTCPStreamDecoder.c \
	OOPlanetData.c


OOLITE_DEBUG_FILES = \
	OODebugMonitor.m \
	OODebugSupport.m \
	OODebugTCPConsoleClient.m \
	OOJSConsole.m \
	OOProfilingStopwatch.m \
	OOTCPStreamDecoderAbstractionLayer.m

OOLITE_ENTITY_FILES = \
	DustEntity.m \
	Entity.m \
	OOEntityWithDrawable.m \
	OOSelfDrawingEntity.m \
	ParticleEntity.m \
	PlanetEntity.m \
	PlayerEntity.m \
	PlayerEntityContracts.m \
	PlayerEntityControls.m \
	PlayerEntityLegacyScriptEngine.m \
	PlayerEntityLoadSave.m \
	PlayerEntityScriptMethods.m \
	PlayerEntitySound.m \
	PlayerEntityStickMapper.m \
	ProxyPlayerEntity.m \
	RingEntity.m \
	ShipEntity.m \
	ShipEntityAI.m \
	ShipEntityScriptMethods.m \
	SkyEntity.m \
	StationEntity.m \
	OOSunEntity.m \
	WormholeEntity.m \
	OOLightParticleEntity.m \
	OOFlasherEntity.m \
	OOExhaustPlumeEntity.m \
	OOSparkEntity.m \
	OOECMBlastEntity.m \
	OOPlanetEntity.m \
	OOPlasmaShotEntity.m \
	OOPlasmaBurstEntity.m \
	OOFlashEffectEntity.m \
	ShipEntityLoadRestore.m

OOLITE_GRAPHICS_DRAWABLE_FILES = \
	OODrawable.m \
	OOPlanetDrawable.m \
	OOMesh.m

OOLITE_GRAPHICS_MATERIAL_FILES = \
	OOMaterialSpecifier.m \
	OOBasicMaterial.m \
	OOMaterial.m \
	OONullTexture.m \
	OOPlanetTextureGenerator.m \
	OOPNGTextureLoader.m \
	OOShaderMaterial.m \
	OOShaderProgram.m \
	OOShaderUniform.m \
	OOShaderUniformMethodType.m \
	OOSingleTextureMaterial.m \
	OOTexture.m \
	OOConcreteTexture.m \
	OOTextureGenerator.m \
	OOTextureLoader.m \
	OOPixMap.m \
	OOTextureScaling.m \
	OOPixMapChannelOperations.m \
	OOMultiTextureMaterial.m \
	OOMaterialConvenienceCreators.m \
	OOCombinedEmissionMapGenerator.m \
	OOPixMapTextureLoader.m

OOLITE_GRAPHICS_MISC_FILES = \
	OOCrosshairs.m \
	OODebugGLDrawing.m \
	OOGraphicsResetManager.m \
	OOOpenGL.m \
	OOOpenGLExtensionManager.m \
	OOProbabilisticTextureManager.m \
	OOSkyDrawable.m \
	OpenGLSprite.m \
	OOPolygonSprite.m \
	OOConvertCubeMapToLatLong.m

OOLITE_MATHS_FILES = \
	CollisionRegion.m \
	Geometry.m \
	Octree.m \
	OOFastArithmetic.m \
	OOMatrix.m \
	OOQuaternion.m \
	OOVector.m \
	OOVoxel.m

OOLITE_OXP_VERIFIER_FILES = \
	OOAIStateMachineVerifierStage.m \
	OOCheckDemoShipsPListVerifierStage.m \
	OOCheckEquipmentPListVerifierStage.m \
	OOCheckRequiresPListVerifierStage.m \
	OOCheckShipDataPListVerifierStage.m \
	OOFileScannerVerifierStage.m \
	OOModelVerifierStage.m \
	OOOXPVerifier.m \
	OOOXPVerifierStage.m \
	OOPListSchemaVerifier.m \
	OOTextureVerifierStage.m

OOLITE_RSRC_MGMT_FILES = \
	OldSchoolPropertyListWriting.m \
	OOCache.m \
	OOCacheManager.m \
	OOConvertSystemDescriptions.m \
	OOPListParsing.m \
	ResourceManager.m \
	TextureStore.m

OOLITE_SCRIPTING_FILES = \
	EntityOOJavaScriptExtensions.m \
	OOJavaScriptEngine.m \
	OOJSEngineTimeManagement.m \
	OOJSCall.m \
	OOJSClock.m \
	OOJSEntity.m \
	OOJSEquipmentInfo.m \
	OOJSFunction.m \
	OOJSGlobal.m \
	OOJSManifest.m \
	OOJSMission.m \
	OOJSMissionVariables.m \
	OOJSOolite.m \
	OOJSPlanet.m \
	OOJSPlayer.m \
	OOJSPlayerShip.m \
	OOJSQuaternion.m \
	OOJSScript.m \
	OOJSShip.m \
	OOJSShipGroup.m \
	OOJSSound.m \
	OOJSSoundSource.m \
	OOJSSpecialFunctions.m \
	OOJSStation.m \
	OOJSSun.m \
	OOJSSystem.m \
	OOJSSystemInfo.m \
	OOJSTimer.m \
	OOJSVector.m \
	OOJSWorldScripts.m \
	OOLegacyScriptWhitelist.m \
	OOPListScript.m \
	OOScript.m \
	OOScriptTimer.m \
	OOJSFrameCallbacks.m

OOLITE_SOUND_FILES = \
	OOBasicSoundReferencePoint.m \
	OOMusicController.m \
	OOSDLConcreteSound.m \
	OOSDLSound.m \
	OOSDLSoundChannel.m \
	OOSDLSoundMixer.m \
	OOSoundSource.m \
	OOSoundSourcePool.m \
	SDLMusic.m

OOLITE_UI_FILES = \
	GuiDisplayGen.m \
	HeadUpDisplay.m \
	OOEncodingConverter.m

OO_UTILITY_FILES = \
	Comparison.m \
	NSDictionaryOOExtensions.m \
	NSFileManagerOOExtensions.m \
	NSMutableDictionaryOOExtensions.m \
	NSScannerOOExtensions.m \
	NSStringOOExtensions.m \
	NSThreadOOExtensions.m \
	NSNumberOOExtensions.m \
	OOAsyncQueue.m \
	OOAsyncWorkManager.m \
	OOCollectionExtractors.m \
	OOColor.m \
	OOConstToString.m \
	OOCPUInfo.m \
	OOEntityFilterPredicate.m \
	OOExcludeObjectEnumerator.m \
	OOFilteringEnumerator.m \
	OOIsNumberLiteral.m \
	OOLogging.m \
	OOLogHeader.m \
	OOLogOutputHandler.m \
	OOPriorityQueue.m \
	OOProbabilitySet.m \
	OOShipGroup.m \
	OOStringParsing.m \
	OOWeakReference.m \
	OOXMLExtensions.m \
	OODeepCopy.m \
	OORegExpMatcher.m \
	NSObjectOOExtensions.m

OOLITE_MISC_FILES = \
	AI.m \
	AIGraphViz.m \
	GameController.m \
	OOJoystickManager.m \
	OOSDLJoystickManager.m \
	main.m \
	MyOpenGLView.m \
	OOCharacter.m \
	OOCocoa.m \
	OOEquipmentType.m \
	OORoleSet.m \
	OOShipRegistry.m \
	OOSpatialReference.m \
	OOTrumble.m \
	Universe.m

oolite_OBJC_FILES = \
	$(OOLITE_DEBUG_FILES) \
	$(OOLITE_ENTITY_FILES) \
	$(OOLITE_GRAPHICS_DRAWABLE_FILES) \
	$(OOLITE_GRAPHICS_MATERIAL_FILES) \
	$(OOLITE_GRAPHICS_MISC_FILES) \
	$(OOLITE_MATHS_FILES) \
	$(OOLITE_OXP_VERIFIER_FILES) \
	$(OOLITE_RSRC_MGMT_FILES) \
	$(OOLITE_SCRIPTING_FILES) \
	$(OOLITE_SOUND_FILES) \
	$(OOLITE_UI_FILES) \
	$(OO_UTILITY_FILES) \
	$(OOLITE_MISC_FILES)

include $(GNUSTEP_MAKEFILES)/objc.make
include GNUmakefile.postamble
