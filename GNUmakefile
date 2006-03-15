include $(GNUSTEP_MAKEFILES)/common.make
CP = cp
vpath %.m src/SDL:src/Core
vpath %.h src/SDL:src/Core
vpath %.c src/SDL:src/Core:src/BSDCompat
GNUSTEP_INSTALLATION_DIR = $(GNUSTEP_USER_ROOT)
ifeq ($(GNUSTEP_HOST_OS),mingw32)
	ADDITIONAL_INCLUDE_DIRS =
	ADDITIONAL_GUI_LIBS = -lglu32 -lopengl32 -lmingw32 -lSDLmain -lSDL -lSDL_mixer -lSDL_image
	ADDITIONAL_CFLAGS = -DLINUX -DWIN32 -DNEED_STRLCPY `sdl-config --cflags`
# note the vpath stuff above isn't working for me, so adding src/SDL and src/Core explicitly
	ADDITIONAL_OBJCFLAGS = -DLOADSAVEGUI -DLINUX -DWIN32 -DHAVE_SOUND -Isrc/SDL -Isrc/Core -Wno-import `sdl-config --cflags`
	oolite_LIB_DIRS += -L$(GNUSTEP_LOCAL_ROOT)/lib
else
	ADDITIONAL_INCLUDE_DIRS = -Isrc/SDL -Isrc/Core -Isrc/BSDCompat
	ADDITIONAL_GUI_LIBS = -lGLU -lGL -lSDL -lpthread -lSDL_mixer -lSDL_image
	ADDITIONAL_CFLAGS = -DLINUX -DNEED_STRLCPY `sdl-config --cflags`
	ADDITIONAL_OBJCFLAGS = -DLOADSAVEGUI -DLINUX -DHAVE_SOUND -Wno-import `sdl-config --cflags`
	oolite_LIB_DIRS += -L/usr/X11R6/lib/
endif
APP_NAME = oolite

oolite_C_FILES = vector.c legacy_random.c strlcpy.c
oolite_OBJC_FILES = Comparison.m AI.m DustEntity.m Entity.m GameController.m GuiDisplayGen.m HeadUpDisplay.m main.m MyOpenGLView.m OpenGLSprite.m ParticleEntity.m PlanetEntity.m PlayerEntity_Additions.m PlayerEntity_contracts.m PlayerEntity_Controls.m PlayerEntity_Sound.m PlayerEntity.m ResourceManager.m RingEntity.m ShipEntity_AI.m ShipEntity.m SkyEntity.m StationEntity.m TextureStore.m Universe.m OOSound.m OOMusic.m SDLImage.m LoadSave.m OOFileManager.m JoystickHandler.m PlayerEntity_StickMapper.m OOBasicSoundReferencePoint.m OOBasicSoundSource.m OOCharacter.m OOTrumble.m WormholeEntity.m ScannerExtension.m OOXMLExtensions.m MutableDictionaryExtension.m Geometry.m Octree.m CollisionRegion.m

include $(GNUSTEP_MAKEFILES)/application.make
include GNUmakefile.postamble

