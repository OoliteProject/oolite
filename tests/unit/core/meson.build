# Unit tests of converted game classes (Phase 3; proposed ADR-0056, exemplar bead oo-11m):
# meson test -C build/meson_<type> --suite core, or bash tools/check-core-tests.sh.
#
# One executable per tests/unit/core/test_<Class>.mm. It links the GAME'S OWN objects for the
# class, its Objective-C bridge and whatever else they reference (extracted from the oolite
# target, so compiled exactly as the game compiles them), with the game's include directories and
# dependencies but not its link arguments (-mwindows would hide the test's output). Add a converted
# class as one entry: its test name and the game sources whose objects it needs (['*']: all but main).
# tools/check-core-tests.sh fails when a test_*.mm here is missing from this list.

openal_tests = ['test_OOOpenALController', 'test_OOSound', 'test_OOALBufferedSound', 'test_OOALStreamedSound',
    'test_OOMusic', 'test_OOSoundChannel', 'test_OOSoundMixer', 'test_MyOpenGLView']

core_tests = {
    'test_OOJSEngineTimeManagement': ['Core/Scripting/OOJSEngineTimeManagement.cpp', 'Core/OOProfilingStopwatch.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOJSGuiScreenKeyDefinition': ['Core/Scripting/OOJSGuiScreenKeyDefinition.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOJSInterfaceDefinition': ['Core/Scripting/OOJSInterfaceDefinition.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOJSPopulatorDefinition': ['Core/Scripting/OOJSPopulatorDefinition.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOPListScript': ['*'],
    'test_OOScript': ['*'],
    'test_OOJSScript': ['*'],
    'test_OOJavaScriptEngine': ['*'],
    'test_OOJSSystem': ['*'],
    'test_OOJSPlayerShip': ['*'],
    'test_OOJSShip': ['*'],
    'test_OOCache': ['Core/OOCache.cpp'],
    'test_OOCacheManager': ['Core/OOCacheManager.cpp'],
    'test_OOEncodingConverter': ['Core/OOEncodingConverter.cpp', 'Core/OOCache.cpp'],
    'test_OOFullScreenController': ['Core/OOFullScreenController.cpp'],
    'test_OOSoundReferencePoint': ['Core/OOBasicSoundReferencePoint.cpp'],
    'test_OOColor': ['Core/OOColor.cpp'],
    'test_OOJoystickProfile': ['Core/OOJoystickProfile.cpp'],
    'test_OOSDLJoystickManager': ['SDL/OOSDLJoystickManager.cpp', 'Core/OOJoystickManager.cpp', 'Core/OOJoystickProfile.cpp'],
    'test_OOJoystickManager': ['Core/OOJoystickManager.cpp', 'Core/OOJoystickProfile.cpp'],
    'test_OORegExpMatcher': ['Core/OORegExpMatcher.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOFileScannerVerifierStage': ['Core/OXPVerifier/OOFileScannerVerifierStage.cpp', 'Core/OXPVerifier/OOOXPVerifierStage.cpp'],
    'test_OOAIStateMachineVerifierStage': ['Core/OXPVerifier/OOAIStateMachineVerifierStage.cpp', 'Core/OXPVerifier/OOFileScannerVerifierStage.cpp', 'Core/OXPVerifier/OOOXPVerifierStage.cpp'],
    'test_OOCheckJSSyntaxVerifierStage': ['Core/OXPVerifier/OOCheckJSSyntaxVerifierStage.cpp', 'Core/OXPVerifier/OOFileScannerVerifierStage.cpp', 'Core/OXPVerifier/OOOXPVerifierStage.cpp'],
    'test_OOCheckPListSyntaxVerifierStage': ['Core/OXPVerifier/OOCheckPListSyntaxVerifierStage.cpp', 'Core/OXPVerifier/OOFileScannerVerifierStage.cpp', 'Core/OXPVerifier/OOOXPVerifierStage.cpp'],
    'test_OOCheckDemoShipsPListVerifierStage': ['Core/OXPVerifier/OOCheckDemoShipsPListVerifierStage.cpp', 'Core/OXPVerifier/OOFileScannerVerifierStage.cpp', 'Core/OXPVerifier/OOOXPVerifierStage.cpp'],
    'test_OOCheckRequiresPListVerifierStage': ['Core/OXPVerifier/OOCheckRequiresPListVerifierStage.cpp', 'Core/OXPVerifier/OOFileScannerVerifierStage.cpp', 'Core/OXPVerifier/OOOXPVerifierStage.cpp'],
    'test_OOCheckEquipmentPListVerifierStage': ['Core/OXPVerifier/OOCheckEquipmentPListVerifierStage.cpp', 'Core/OXPVerifier/OOFileScannerVerifierStage.cpp', 'Core/OXPVerifier/OOOXPVerifierStage.cpp'],
    'test_OOTextureVerifierStage': ['Core/OXPVerifier/OOTextureVerifierStage.cpp', 'Core/OXPVerifier/OOFileScannerVerifierStage.cpp', 'Core/OXPVerifier/OOOXPVerifierStage.cpp'],
    'test_OOCheckShipDataPListVerifierStage': ['Core/OXPVerifier/OOCheckShipDataPListVerifierStage.cpp', 'Core/OXPVerifier/OOModelVerifierStage.cpp', 'Core/OXPVerifier/OOAIStateMachineVerifierStage.cpp', 'Core/OXPVerifier/OOTextureVerifierStage.cpp', 'Core/OXPVerifier/OOFileScannerVerifierStage.cpp', 'Core/OXPVerifier/OOOXPVerifierStage.cpp'],
    'test_OOModelVerifierStage': ['Core/OXPVerifier/OOModelVerifierStage.cpp', 'Core/OXPVerifier/OOTextureVerifierStage.cpp', 'Core/OXPVerifier/OOFileScannerVerifierStage.cpp', 'Core/OXPVerifier/OOOXPVerifierStage.cpp'],
    'test_OODrawable': ['Core/OODrawable.cpp', 'Core/OOVector.cpp', 'Core/legacy_random.c'],
    'test_OOMaterial': ['Core/Materials/OOMaterial.cpp'],
    'test_OOShaderUniformMethodType': ['Core/Materials/OOShaderUniformMethodType.cpp', 'Core/OOMatrix.cpp', 'Core/OOOpenGLExtensionManager.cpp', 'Core/OOVector.cpp', 'Core/OOHPVector.cpp', 'Core/OOQuaternion.cpp', 'Core/legacy_random.c', 'Core/OOOpenGL.cpp', 'Core/OOOpenGLStateManager.cpp'],
    'test_OOBasicMaterial': ['Core/Materials/OOBasicMaterial.cpp', 'Core/Materials/OOMaterial.cpp', 'Core/Materials/OOMaterialSpecifier.cpp', 'Core/OOColor.cpp', 'Core/OOOpenGL.cpp', 'Core/OOOpenGLStateManager.cpp'],
    'test_OOSingleTextureMaterial': ['Core/Materials/OOSingleTextureMaterial.cpp', 'Core/Materials/OOBasicMaterial.cpp', 'Core/Materials/OOMaterial.cpp', 'Core/Materials/OOMaterialSpecifier.cpp', 'Core/OOColor.cpp', 'Core/OOOpenGL.cpp', 'Core/OOOpenGLStateManager.cpp'],
    'test_OOMaterialConvenienceCreators': ['Core/Materials/OOMaterialConvenienceCreators.cpp', 'Core/Materials/OOShaderMaterial.cpp', 'Core/Materials/OOSingleTextureMaterial.cpp', 'Core/Materials/OOMultiTextureMaterial.cpp', 'Core/Materials/OOBasicMaterial.cpp', 'Core/Materials/OOMaterial.cpp', 'Core/Materials/OOMaterialSpecifier.cpp', 'Core/Materials/OOShaderProgram.cpp', 'Core/Materials/OOShaderUniform.cpp', 'Core/Materials/OOShaderUniformMethodType.cpp', 'Core/OOOpenGLMatrixManager.cpp', 'Core/OOColor.cpp', 'Core/OOOpenGL.cpp', 'Core/OOOpenGLExtensionManager.cpp', 'Core/OOPListGameTypes.cpp', 'Core/OOIsNumberLiteral.cpp', 'Core/OOVector.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/OOHPVector.cpp', 'Core/OOQuaternion.cpp', 'Core/OOMatrix.cpp', 'Core/legacy_random.c', 'Core/OOOpenGLStateManager.cpp'],
    'test_OOMultiTextureMaterial': ['Core/Materials/OOMultiTextureMaterial.cpp', 'Core/Materials/OOBasicMaterial.cpp', 'Core/Materials/OOMaterial.cpp', 'Core/Materials/OOMaterialSpecifier.cpp', 'Core/OOColor.cpp', 'Core/OOOpenGL.cpp', 'Core/OOOpenGLExtensionManager.cpp', 'Core/OOOpenGLStateManager.cpp'],
    'test_OOShaderMaterial': ['Core/Materials/OOShaderMaterial.cpp', 'Core/Materials/OOBasicMaterial.cpp', 'Core/Materials/OOMaterial.cpp', 'Core/Materials/OOMaterialSpecifier.cpp', 'Core/OOColor.cpp', 'Core/OOOpenGL.cpp', 'Core/OOOpenGLExtensionManager.cpp', 'Core/OOPListGameTypes.cpp', 'Core/OOIsNumberLiteral.cpp', 'Core/OOVector.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/OOHPVector.cpp', 'Core/OOQuaternion.cpp', 'Core/OOMatrix.cpp', 'Core/legacy_random.c', 'Core/OOOpenGLStateManager.cpp'],
    'test_OODefaultShaderSynthesizer': ['*'],
    'test_OOShaderUniform': ['Core/Materials/OOShaderUniform.cpp', 'Core/Materials/OOShaderUniformMethodType.cpp', 'Core/OOColor.cpp', 'Core/OOOpenGL.cpp', 'Core/OOOpenGLExtensionManager.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/OOVector.cpp', 'Core/OOHPVector.cpp', 'Core/OOQuaternion.cpp', 'Core/OOMatrix.cpp', 'Core/legacy_random.c', 'Core/OOOpenGLStateManager.cpp'],
    'test_OOShaderProgram': ['Core/Materials/OOShaderProgram.cpp', 'Core/OOOpenGLMatrixManager.cpp', 'Core/OOOpenGL.cpp', 'Core/OOOpenGLExtensionManager.cpp', 'Core/OOMatrix.cpp', 'Core/OOVector.cpp', 'Core/OOHPVector.cpp', 'Core/OOQuaternion.cpp', 'Core/legacy_random.c', 'Core/OOOpenGLStateManager.cpp'],
    'test_OOOXPVerifierStage': ['Core/OXPVerifier/OOOXPVerifierStage.cpp'],
    'test_OOOXPVerifier': ['*'],
    'test_OOPListSchemaVerifier': ['Core/OXPVerifier/OOPListSchemaVerifier.cpp', 'Core/OOPListGameTypes.cpp', 'Core/OOIsNumberLiteral.cpp', 'Core/OOVector.cpp', 'Core/OOHPVector.cpp', 'Core/OOQuaternion.cpp', 'Core/legacy_random.c'],
    'test_OOOpenALController': ['Core/OOOpenALController.cpp'],
    'test_OOSound': ['Core/OOALSound.cpp', 'Core/OOOpenALController.cpp'],
    'test_OOALSoundDecoder': ['Core/OOALSoundDecoder.cpp', 'Core/MiniZip/unzip.c', 'Core/MiniZip/ioapi.c'],
    'test_OOALBufferedSound': ['Core/OOALBufferedSound.cpp', 'Core/OOALSound.cpp', 'Core/OOALSoundDecoder.cpp', 'Core/MiniZip/unzip.c', 'Core/MiniZip/ioapi.c', 'Core/OOOpenALController.cpp'],
    'test_OOALStreamedSound': ['Core/OOALStreamedSound.cpp', 'Core/OOALSound.cpp', 'Core/OOALSoundDecoder.cpp', 'Core/MiniZip/unzip.c', 'Core/MiniZip/ioapi.c', 'Core/OOOpenALController.cpp'],
    'test_OOMusic': ['Core/OOALMusic.cpp', 'Core/OOVector.cpp', 'Core/legacy_random.c', 'Core/OOALSound.cpp', 'Core/OOSoundSource.cpp', 'Core/OOOpenALController.cpp'],
    'test_OOSoundChannel': ['Core/OOALSoundChannel.cpp', 'Core/OOALSound.cpp', 'Core/OOOpenALController.cpp'],
    'test_OOSoundMixer': ['Core/OOALSoundMixer.cpp', 'Core/OOALSound.cpp', 'Core/OOOpenALController.cpp'],
    'test_OOSoundSource': ['Core/OOSoundSource.cpp', 'Core/OOVector.cpp', 'Core/legacy_random.c'],
    'test_OOSoundSourcePool': ['Core/OOSoundSourcePool.cpp', 'Core/OOVector.cpp', 'Core/legacy_random.c'],
    'test_OOMusicController': ['Core/OOMusicController.cpp'],
    'test_OOShipGroup': ['Core/OOShipGroup.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOGraphicsResetManager': ['Core/OOGraphicsResetManager.cpp', 'Core/OOOpenGLExtensionManager.cpp', 'Core/OOOpenGL.cpp', 'Core/OOOpenGLStateManager.cpp'],
    'test_OOOpenGLExtensionManager': ['Core/OOOpenGLExtensionManager.cpp', 'Core/OOOpenGL.cpp', 'Core/OOOpenGLStateManager.cpp'],
    'test_OOOpenGLStateManager': ['Core/OOOpenGLStateManager.cpp', 'Core/OOOpenGL.cpp', 'Core/OOOpenGLExtensionManager.cpp'],
    'test_OOTextureSprite': ['Core/OOTextureSprite.cpp', 'Core/OOOpenGLStateManager.cpp', 'Core/OOOpenGL.cpp', 'Core/OOOpenGLExtensionManager.cpp'],
    'test_OOTexture': ['*'],
    'test_OONullTexture': ['*'],
    'test_OOConcreteTexture': ['*'],
    'test_OOTextureScaling': ['Core/OOTextureScaling.cpp', 'Core/Materials/OOPixMap.cpp'],
    'test_OOTextureLoader': ['*'],
    'test_OOTextureGenerator': ['*'],
    'test_OOPNGTextureLoader': ['*'],
    'test_OOPixMapTextureLoader': ['*'],
    'test_OOCombinedEmissionMapGenerator': ['*'],
    'test_OOStandaloneAtmosphereGenerator': ['*'],
    'test_OOPlanetTextureGenerator': ['*'],
    'test_OOCrosshairs': ['Core/OOCrosshairs.cpp', 'Core/OOColor.cpp'],
    'test_OOOpenGLMatrixManager': ['Core/OOOpenGLMatrixManager.cpp', 'Core/OOMatrix.cpp', 'Core/OOVector.cpp', 'Core/legacy_random.c', 'Core/OOOpenGLExtensionManager.cpp', 'Core/OOOpenGL.cpp', 'Core/OOOpenGLStateManager.cpp'],
    'test_OOCharacter': ['Core/OOCharacter.cpp', 'Core/legacy_random.c'],
    'test_OOTrumble': ['Core/OOTrumble.cpp', 'Core/OOVector.cpp', 'Core/legacy_random.c'],
    'test_OOCommodities': ['Core/OOCommodities.cpp', 'Core/OOCommodityMarket.cpp', 'Core/legacy_random.c'],
    'test_OOCommodityMarket': ['Core/OOCommodityMarket.cpp'],
    'test_OOEquipmentType': ['Core/OOEquipmentType.cpp', 'Core/OOColor.cpp'],
    'test_OOConstToString': ['Core/OOConstToString.cpp', 'Core/OOEquipmentType.cpp', 'Core/OOColor.cpp', 'Core/OOCommodityMarket.cpp'],
    'test_OOPriorityQueue': [],
    'test_OORoleSet': ['Core/OORoleSet.cpp', 'Core/legacy_random.c'],
    'test_OOProbabilitySet': ['Core/OOProbabilitySet.cpp', 'Core/legacy_random.c'],
    'test_OOShipRegistry': ['Core/OOShipRegistry.cpp', 'Core/OORoleSet.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/OOCacheManager.cpp', 'Core/OOProbabilitySet.cpp', 'Core/OOPListGameTypes.cpp', 'Core/OOIsNumberLiteral.cpp', 'Core/OOVector.cpp', 'Core/OOHPVector.cpp', 'Core/OOQuaternion.cpp', 'Core/OOColor.cpp', 'Core/legacy_random.c'],
    'test_OOProbabilisticTextureManager': ['Core/OOProbabilisticTextureManager.cpp', 'Core/legacy_random.c'],
    'test_CollisionRegion': ['*'],
    'test_Octree': ['*'],
    'test_OOJSVector': ['Core/Scripting/OOJSVector.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/OOHPVector.cpp', 'Core/OOVector.cpp', 'Core/OOQuaternion.cpp', 'Core/legacy_random.c'],
    'test_OOJSDock': ['Core/Scripting/OOJSDock.cpp', 'Core/Scripting/OOJSPrivateObject.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOJSSoundSource': ['Core/Scripting/OOJSSoundSource.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOJSSound': ['Core/Scripting/OOJSSound.cpp', 'Core/Scripting/OOJSPrivateObject.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOJSSun': ['Core/Scripting/OOJSSun.cpp', 'Core/Scripting/OOJSPrivateObject.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOJSOolite': ['Core/Scripting/OOJSOolite.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOJSEquipmentInfo': ['Core/Scripting/OOJSEquipmentInfo.cpp', 'Core/Scripting/OOJSPrivateObject.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/OOEquipmentType.cpp', 'Core/OOColor.cpp'],
    'test_OOJSPlayer': ['Core/Scripting/OOJSPlayer.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/legacy_random.c'],
    'test_OOJSEntity': ['Core/Scripting/OOJSEntity.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/Scripting/OOConstToJSString.cpp', 'Core/OOQuaternion.cpp', 'Core/OOVector.cpp', 'Core/OOHPVector.cpp', 'Core/legacy_random.c'],
    'test_OOJSMissionVariables': ['Core/Scripting/OOJSMissionVariables.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/OOIsNumberLiteral.cpp'],
    'test_OOJSMission': ['Core/Scripting/OOJSMission.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/Scripting/OOConstToJSString.cpp', 'Core/OOVector.cpp', 'Core/legacy_random.c'],
    'test_OOJSStation': ['Core/Scripting/OOJSStation.cpp', 'Core/Scripting/OOJSPrivateObject.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/OOCommodities.cpp', 'Core/OOCommodityMarket.cpp', 'Core/Scripting/OOJSInterfaceDefinition.cpp', 'Core/OOEquipmentType.cpp', 'Core/OOColor.cpp', 'Core/legacy_random.c'],
    'test_OOJSGlobal': ['Core/Scripting/OOJSGlobal.cpp', 'Core/Scripting/OOConstToJSString.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/OOColor.cpp', 'Core/Scripting/OOJSGuiScreenKeyDefinition.cpp', 'Core/legacy_random.c'],
    'test_OOJSPlanet': ['Core/Scripting/OOJSPlanet.cpp', 'Core/Scripting/OOJSPrivateObject.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/OOColor.cpp'],
    'test_OOJSSystemInfo': ['Core/Scripting/OOJSSystemInfo.cpp', 'Core/Scripting/OOJSPrivateObject.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/OOSystemDescriptionManager.cpp', 'Core/OOCommodities.cpp', 'Core/OOCommodityMarket.cpp', 'Core/OOIsNumberLiteral.cpp', 'Core/legacy_random.c'],
    'test_OOJSManifest': ['Core/Scripting/OOJSManifest.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/OOCommodities.cpp', 'Core/OOCommodityMarket.cpp', 'Core/legacy_random.c'],
    'test_OOJSShipGroup': ['Core/Scripting/OOJSShipGroup.cpp', 'Core/Scripting/OOJSPrivateObject.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/OOShipGroup.cpp'],
    'test_OOJSVisualEffect': ['Core/Scripting/OOJSVisualEffect.cpp', 'Core/Scripting/OOJSPrivateObject.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/OOColor.cpp', 'Core/OOVector.cpp', 'Core/legacy_random.c'],
    'test_OOJSWaypoint': ['Core/Scripting/OOJSWaypoint.cpp', 'Core/Scripting/OOJSPrivateObject.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/OOQuaternion.cpp', 'Core/OOVector.cpp', 'Core/OOHPVector.cpp', 'Core/legacy_random.c'],
    'test_OOJSFlasher': ['Core/Scripting/OOJSFlasher.cpp', 'Core/Scripting/OOJSPrivateObject.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/OOColor.cpp'],
    'test_OOJSExhaustPlume': ['Core/Scripting/OOJSExhaustPlume.cpp', 'Core/Scripting/OOJSPrivateObject.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOJSQuaternion': ['Core/Scripting/OOJSQuaternion.cpp', 'Core/Scripting/OOJSVector.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp', 'Core/OOHPVector.cpp', 'Core/OOVector.cpp', 'Core/OOQuaternion.cpp', 'Core/legacy_random.c'],
    'test_OOJSClock': ['Core/Scripting/OOJSClock.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOJSWormhole': ['Core/Scripting/OOJSWormhole.cpp', 'Core/Scripting/OOJSPrivateObject.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOMeshToOctreeConverter': ['*'],
    'test_OOMesh': ['*'],
    'test_OOPolygonSprite': ['*'],
    'test_OOVector': ['Core/OOVector.cpp', 'Core/legacy_random.c'],
    'test_OOFastArithmetic': [],
    # test_OOAsyncQueue retired with its only subject, the Objective-C OOAsyncQueue (bead oo-4aq6a.8, std-2026-10-19)
    'test_OOProfilingStopwatch': ['Core/OOProfilingStopwatch.cpp'],
    'test_OOAsyncWorkManager': ['Core/OOAsyncWorkManager.cpp', 'Core/OOCPUInfo.cpp'],
    'test_AI': ['Core/AI.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    # test_OOWeakReference retired with its only subject, the weak-reference class (bead oo-9ht.22, ADR-0049; Jon approved 2026-10-19)
    # test_OOWeakSet retired with its only subject, the Objective-C weak set (bead oo-9ht.22, ADR-0049; Jon approved 2026-10-19)
    'test_OOJSFunction': ['Core/Scripting/OOJSFunction.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOJSPrivateObject': ['Core/Scripting/OOJSPrivateObject.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOJSTimer': ['Core/Scripting/OOJSTimer.cpp', 'Core/Scripting/OOJSPrivateObject.cpp', 'Core/Scripting/OOScriptTimer.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOScriptTimer': ['Core/Scripting/OOScriptTimer.cpp'],
    'test_OOJSFrameCallbacks': ['Core/Scripting/OOJSFrameCallbacks.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOJSCall': ['Core/Scripting/OOJSCall.cpp', 'Core/Materials/OOShaderUniformMethodType.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOSystemDescriptionManager': ['Core/OOSystemDescriptionManager.cpp', 'Core/legacy_random.c'],
    'test_GuiDisplayGen': ['*'],
    'test_MyOpenGLView': ['*'],
    'test_ResourceManager': ['*'],
    'test_PlayerEntityStickProfile': ['*'],
    'test_HeadUpDisplay': ['*'],
    'test_GameController': ['*'],
    'test_Entity': ['*'],
    'test_Universe': ['*'],
    'test_ShipEntity': ['*'],
    'test_PlayerEntity': ['*'],
    'test_ProxyPlayerEntity': ['*'],
    'test_StationEntity': ['*'],
    'test_DockEntity': ['*'],
    'test_ShipEntityAI': ['*'],
    'test_OOEntityWithDrawable': ['*'],
    'test_OOPlanetEntity': ['*'],
    'test_OOPlanetDrawable': ['*'],
    'test_EntityOOJavaScriptExtensions': ['*'],
    'test_OOJSCallEntityMethods': ['*'],
    'test_OOEntityCalledByName': ['*'],
    'test_EntityShaderBindings': ['*'],
    'test_WormholeEntity': ['*'],
    'test_OOSunEntity': ['*'],
    'test_OOExhaustPlumeEntity': ['*'],
    'test_SkyEntity': ['*'],
    'test_OOSkyDrawable': ['*'],
    'test_OOWaypointEntity': ['*'],
    'test_OOFlasherEntity': ['*'],
    'test_OOVisualEffectEntity': ['*'],
    'test_OOFlashEffectEntity': ['*'],
    'test_OOPlasmaShotEntity': ['*'],
    'test_OOECMBlastEntity': ['*'],
    'test_OOLightParticleEntity': ['*'],
    'test_OOSparkEntity': ['*'],
    'test_OOPlasmaBurstEntity': ['*'],
    'test_DustEntity': ['*'],
    'test_OOQuiriumCascadeEntity': ['*'],
    'test_OOLaserShotEntity': ['*'],
    'test_OOBreakPatternEntity': ['*'],
    'test_OOParticleSystem': ['*'],
    'test_OORingEffectEntity': ['*'],
    'test_OODebugMonitor': ['Core/Debug/OODebugMonitor.cpp', 'Core/OOColor.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OOJSConsole': ['Core/Debug/OOJSConsole.cpp', 'Core/Scripting/OOJSEngineTimeManagement.cpp', 'Core/OOProfilingStopwatch.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.cpp', 'Core/Scripting/ooscript/JSEngine_quickjs.cpp'],
    'test_OODebugTCPConsoleClient': ['Core/Debug/OODebugTCPConsoleClient.cpp', 'Core/Debug/OOTCPStreamDecoder.c', 'Core/Debug/OOTCPStreamDecoderAbstractionLayer.cpp'],
    'test_OODebugSupport': ['Core/Debug/OODebugSupport.cpp'],
    'test_OODebugStandards': ['Core/Debug/OODebugStandards.cpp'],
    'test_OOOXZManager': ['*'],
}

fs = import('fs')

foreach name, game_sources : core_tests
    # The oolite target's own File objects for these sources (extract_objects matches Files, and
    # a files() made here would name a different directory).
    wanted = []
    foreach s : game_sources
        wanted += ['src/' + s]
    endforeach
    # ['*'] is every game object but main's, for a class whose object needs the game graph
    # (Universe, Entity ivars): proposed ADR-0056 amendment oo-44gg.
    whole_game = game_sources == ['*']
    sources = []
    foreach f : oolite_sources
        rel = fs.relative_to(f, meson.project_source_root()).replace('\\', '/')
        if rel in wanted or (whole_game and rel != 'src/SDL/main.cpp')
            sources += [f]
        endif
    endforeach
    assert(whole_game or sources.length() == game_sources.length(), name + ': a game source in core_tests is not in the oolite target')
    exe = executable(
        'core_' + name,
        name + '.cpp',
        objects: oolite_bin.extract_objects(sources),
        include_directories: [oolite_includes, include_directories('../oofnd')],
        dependencies: oolite_dependencies,
        override_options: oolite_override_options,
        install: false,
    )
    # 'openal': the tests that open the OpenAL device (alcOpenDevice). A sanitized run leaves them
    # out with --no-suite openal: the prebuilt libopenal-1.dll's onexit registration trips ASan's
    # allocator-ownership check inside ucrtbase.dll, a third-party report no suppression reaches
    # (oo-dg6vf; tools/asan-suppressions.txt). The game's sanitized launch uses --nosound instead.
    test(name, exe, suite: name in openal_tests ? ['core', 'openal'] : 'core', timeout: 60)
endforeach
