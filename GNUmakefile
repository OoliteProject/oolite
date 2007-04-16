include $(GNUSTEP_MAKEFILES)/common.make
CP = cp
vpath %.m src/SDL:src/Core:src/Core/JavaScript:src/Core/Scripting
vpath %.h src/SDL:src/Core
vpath %.c src/SDL:src/Core:src/BSDCompat
GNUSTEP_INSTALLATION_DIR = $(GNUSTEP_USER_ROOT)
ifeq ($(GNUSTEP_HOST_OS),mingw32)
	ADDITIONAL_INCLUDE_DIRS = -Ideps/Windows-x86-deps/include -Isrc/SDL -Isrc/Core -Isrc/Core/Scripting -Isrc/Core/Materials -Isrc/Core/Entities
	ADDITIONAL_OBJC_LIBS = -lglu32 -lopengl32 -lmingw32 -lSDLmain -lSDL -lSDL_mixer -lSDL_image -lgnustep-base -ljs32
	ADDITIONAL_CFLAGS = -DLINUX -DWIN32 -DNEED_STRLCPY `sdl-config --cflags`
# note the vpath stuff above isn't working for me, so adding src/SDL and src/Core explicitly
	ADDITIONAL_OBJCFLAGS = -DLOADSAVEGUI -DLINUX -DWIN32 -DXP_WIN -Wno-import `sdl-config --cflags`	oolite_LIB_DIRS += -L$(GNUSTEP_LOCAL_ROOT)/lib -Ldeps/Windows-x86-deps/lib
else
	ADDITIONAL_INCLUDE_DIRS = -Isrc/SDL -Isrc/Core -Isrc/BSDCompat -Isrc/Core/Scripting -Isrc/Core/Materials -Isrc/Core/Entities
	ADDITIONAL_OBJC_LIBS = -lGLU -lGL -lSDL -lpthread -lSDL_mixer -lSDL_image -lgnustep-base
	ADDITIONAL_CFLAGS = -DLINUX -DNEED_STRLCPY `sdl-config --cflags`
	ADDITIONAL_OBJCFLAGS = -DLOADSAVEGUI -DLINUX -Wno-import `sdl-config --cflags`
	oolite_LIB_DIRS += -L/usr/X11R6/lib/
endif
OBJC_PROGRAM_NAME = oolite

oolite_C_FILES = legacy_random.c strlcpy.c
oolite_OBJC_FILES = Comparison.m AI.m DustEntity.m Entity.m GameController.m GuiDisplayGen.m HeadUpDisplay.m main.m MyOpenGLView.m OpenGLSprite.m ParticleEntity.m PlanetEntity.m PlayerEntityLegacyScriptEngine.m PlayerEntityContracts.m PlayerEntityControls.m PlayerEntityLoadSave.m PlayerEntitySound.m PlayerEntity.m ResourceManager.m RingEntity.m ShipEntityAI.m ShipEntity.m SkyEntity.m StationEntity.m TextureStore.m Universe.m OOSound.m SDLMusic.m SDLImage.m NSFileManagerOOExtensions.m JoystickHandler.m PlayerEntityStickMapper.m OOBasicSoundReferencePoint.m OOBasicSoundSource.m OOCharacter.m OOTrumble.m WormholeEntity.m NSScannerOOExtensions.m OOXMLExtensions.m NSMutableDictionaryOOExtensions.m Geometry.m Octree.m CollisionRegion.m OOColor.m OOLogging.m OOCacheManager.m OOCache.m OOStringParsing.m OOCollectionExtractors.m OOVector.m OOMatrix.m OOQuaternion.m OOVoxel.m OOTriangle.m OOPListParsing.m OOFastArithmetic.m OOTextureScaling.m OOConstToString.m OOScript.m OOJSScript.m OOJavaScriptEngine.m OOPListScript.m OOSCompiler.m OOSTokenizer.m NSStringOOExtensions.m PlayerEntityScriptMethods.m OOWeakReference.m OOJSEntity.m EntityOOJavaScriptExtensions.m OOJSQuaternion.m OOMaterial.m OOShaderMaterial.m OOShaderProgram.m OOShaderUniform.m OOTexture.m OOTextureLoader.m OOPNGTextureLoader.m OOOpenGLExtensionManager.m OOBasicMaterial.m OOSingleTextureMaterial.m OOCPUInfo.m OOSelfDrawingEntity.m OOEntityWithDrawable.m OODrawable.m

include $(GNUSTEP_MAKEFILES)/objc.make
include GNUmakefile.postamble
