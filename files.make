oolite_C_FILES = \
    legacy_random.c \
    strlcpy.c \
    OOTCPStreamDecoder.c \
    OOPlanetData.c \
	ioapi.c \
	unzip.c

oolite_CC_FILES = \
	OOSaveEXRSnapshot.cpp

ifeq ($(GNUSTEP_HOST_OS),mingw32)
oolite_C_FILES += \
	miniz.c
endif

OOLITE_DEBUG_FILES = \
    OODebugMonitor.m \
	OODebugStandards.m \
    OODebugSupport.m \
    OODebugTCPConsoleClient.m \
    OOJSConsole.m \
    OOProfilingStopwatch.m \
    OOTCPStreamDecoderAbstractionLayer.m

OOLITE_ENTITY_FILES = \
    DockEntity.m \
    DustEntity.m \
    Entity.m \
    OOEntityWithDrawable.m \
    OOParticleSystem.m \
    PlanetEntity.m \
    PlayerEntity.m \
    PlayerEntityContracts.m \
    PlayerEntityControls.m \
    PlayerEntityLegacyScriptEngine.m \
    PlayerEntityLoadSave.m \
    PlayerEntityScriptMethods.m \
    PlayerEntitySound.m \
    PlayerEntityStickMapper.m \
    PlayerEntityStickProfile.m \
    PlayerEntityKeyMapper.m \
    ProxyPlayerEntity.m \
    OOBreakPatternEntity.m \
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
    OOExplosionCloudEntity.m \
    ShipEntityLoadRestore.m \
    OOLaserShotEntity.m \
    OOQuiriumCascadeEntity.m \
    OORingEffectEntity.m \
    OOVisualEffectEntity.m \
    OOWaypointEntity.m

OOLITE_GRAPHICS_DRAWABLE_FILES = \
    OODrawable.m \
    OOPlanetDrawable.m \
    OOMesh.m

OOLITE_GRAPHICS_MATERIAL_FILES = \
    OOMaterialSpecifier.m \
    OOBasicMaterial.m \
	OODefaultShaderSynthesizer.m \
    OOMaterial.m \
    OONullTexture.m \
    OOPlanetTextureGenerator.m \
    OOStandaloneAtmosphereGenerator.m \
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
    OOOpenGLStateManager.m \
    OOOpenGLExtensionManager.m \
    OOOpenGLMatrixManager.m \
    OOProbabilisticTextureManager.m \
    OOSkyDrawable.m \
    OOTextureSprite.m \
    OOPolygonSprite.m \
    OOConvertCubeMapToLatLong.m

OOLITE_MATHS_FILES = \
    CollisionRegion.m \
    OOMeshToOctreeConverter.m \
    Octree.m \
    OOHPVector.m \
    OOMatrix.m \
    OOQuaternion.m \
    OOVector.m \
    OOVoxel.m

OOLITE_OXP_VERIFIER_FILES = \
    OOAIStateMachineVerifierStage.m \
    OOCheckDemoShipsPListVerifierStage.m \
    OOCheckEquipmentPListVerifierStage.m \
    OOCheckJSSyntaxVerifierStage.m \
    OOCheckPListSyntaxVerifierStage.m \
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
	OOOXZManager.m \
    OOPListParsing.m \
	OOSystemDescriptionManager.m \
    ResourceManager.m \
    TextureStore.m

OOLITE_SCRIPTING_FILES = \
    EntityOOJavaScriptExtensions.m \
    OOJavaScriptEngine.m \
    OOJSEngineTimeManagement.m \
    OOJSEngineDebuggerHelpers.m \
    OOConstToJSString.m \
    OOJSCall.m \
    OOJSClock.m \
    OOJSDock.m \
    OOJSEntity.m \
    OOJSEquipmentInfo.m \
    OOJSExhaustPlume.m \
    OOJSFlasher.m \
    OOJSFunction.m \
    OOJSGlobal.m \
    OOJSInterfaceDefinition.m \
    OOJSGuiScreenKeyDefinition.m \
    OOJSManifest.m \
    OOJSMission.m \
    OOJSMissionVariables.m \
    OOJSOolite.m \
    OOJSPlanet.m \
    OOJSPlayer.m \
    OOJSPlayerShip.m \
    OOJSPopulatorDefinition.m \
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
	OOJSVisualEffect.m \
    OOJSVector.m \
    OOJSWorldScripts.m \
	OOJSWormhole.m \
	OOJSWaypoint.m \
    OOLegacyScriptWhitelist.m \
    OOPListScript.m \
    OOScript.m \
    OOScriptTimer.m \
    OOJSFrameCallbacks.m \
    OOJSFont.m

OOLITE_SOUND_FILES = \
	OOOpenALController.m \
	OOMusicController.m \
	OOSoundSource.m \
    OOSoundSourcePool.m \
	OOALMusic.m \
	OOALSound.m \
	OOALSoundChannel.m \
	OOALSoundMixer.m \
    OOALSoundDecoder.m \
	OOALBufferedSound.m \
	OOALStreamedSound.m


OOLITE_UI_FILES = \
    GuiDisplayGen.m \
    HeadUpDisplay.m \
    OOEncodingConverter.m

OO_UTILITY_FILES = \
    Comparison.m \
    NSDataOOExtensions.m \
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
    OOStringExpander.m \
    OOStringParsing.m \
    OOWeakReference.m \
    OOWeakSet.m \
    OOXMLExtensions.m \
    OODeepCopy.m \
    OORegExpMatcher.m \
    NSObjectOOExtensions.m

OOLITE_MISC_FILES = \
    AI.m \
    AIGraphViz.m \
    GameController.m \
    GameController+SDLFullScreen.m \
    OOJoystickManager.m \
    OOJoystickProfile.m \
    OOSDLJoystickManager.m \
    main.m \
    MyOpenGLView.m \
    OOCharacter.m \
    OOCocoa.m \
	OOCommodities.m \
	OOCommodityMarket.m \
    OOEquipmentType.m \
    OOMouseInteractionMode.m \
    OORoleSet.m \
    OOShipLibraryDescriptions.m \
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
