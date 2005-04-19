include $(GNUSTEP_MAKEFILES)/common.make
GNUSTEP_INSTALLATION_DIR = $(GNUSTEP_USER_ROOT)
ADDITIONAL_GUI_LIBS = -lGLU -lGL
APP_NAME = oolite
oolite_LIB_DIRS += -L/usr/X11R6/lib/ 
oolite_C_FILES = vector.c legacy_random.c
oolite_OBJC_FILES = AI.m DustEntity.m Entity.m GameController.m GuiDisplayGen.m HeadUpDisplay.m main.m MyOpenGLView.m OpenGLSprite.m ParticleEntity.m PlanetEntity.m PlayerEntity_Additions.m PlayerEntity_contracts.m PlayerEntity.m ResourceManager.m RingEntity.m ShipEntity_AI.m ShipEntity.m SkyEntity.m StationEntity.m TextureStore.m Universe.m

include $(GNUSTEP_MAKEFILES)/application.make

