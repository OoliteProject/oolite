# Unit tests of converted game classes (Phase 3; proposed ADR-0056, exemplar bead oo-11m):
# meson test -C build/meson_<type> --suite core, or bash tools/check-core-tests.sh.
#
# One executable per tests/unit/core/test_<Class>.mm. It links the GAME'S OWN objects for the
# class, its Objective-C bridge and whatever else they reference (extracted from the oolite
# target, so compiled exactly as the game compiles them), with the game's include directories and
# dependencies but not its link arguments (-mwindows would hide the test's output). Add a converted
# class as one entry: its test name and the game sources whose objects it needs (['*']: all but main).
# tools/check-core-tests.sh fails when a test_*.mm here is missing from this list.

core_tests = {
    'test_OOJSEngineTimeManagement': ['Core/Scripting/OOJSEngineTimeManagement.mm', 'Core/Scripting/OOJSEngineTimeManagement+ObjCBridge.mm', 'Core/OOProfilingStopwatch.mm', 'Core/OODescription.mm'],
    'test_OOJSGuiScreenKeyDefinition': ['Core/Scripting/OOJSGuiScreenKeyDefinition.mm', 'Core/Scripting/OOJSGuiScreenKeyDefinition+ObjCBridge.mm', 'Core/OOWeakReference.mm', 'Core/OOWeakReference+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOJSInterfaceDefinition': ['Core/Scripting/OOJSInterfaceDefinition.mm', 'Core/Scripting/OOJSInterfaceDefinition+ObjCBridge.mm', 'Core/OOWeakReference.mm', 'Core/OOWeakReference+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOJSPopulatorDefinition': ['Core/Scripting/OOJSPopulatorDefinition.mm', 'Core/Scripting/OOJSPopulatorDefinition+ObjCBridge.mm', 'Core/OOWeakReference.mm', 'Core/OOWeakReference+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOJSTimeLimiter': ['*'],
    'test_OOPListScript': ['*'],
    'test_OOScript': ['*'],
    'test_OOJSScript': ['*'],
    'test_OOCache': ['Core/OOCache.mm', 'Core/OODescription.mm'],
    'test_OOCacheManager': ['Core/OOCacheManager.mm', 'Core/OOCacheManager+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOEncodingConverter': ['Core/OOEncodingConverter.mm', 'Core/OOCache.mm', 'Core/OODescription.mm'],
    'test_OOFullScreenController': ['Core/OOFullScreenController.mm'],
    'test_OOSoundReferencePoint': ['Core/OOBasicSoundReferencePoint.mm'],
    'test_OOColor': ['Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOJoystickProfile': ['Core/OOJoystickProfile.mm', 'Core/OOJoystickProfile+ObjCBridge.mm'],
    'test_OOSDLJoystickManager': ['SDL/OOSDLJoystickManager.mm', 'SDL/OOSDLJoystickManager+ObjCBridge.mm', 'Core/OOJoystickManager.mm', 'Core/OOJoystickManager+ObjCBridge.mm', 'Core/OOJoystickProfile.mm', 'Core/OOJoystickProfile+ObjCBridge.mm', 'Core/OOCallByName.mm', 'Core/OODescription.mm'],
    'test_OOJoystickManager': ['Core/OOJoystickManager.mm', 'Core/OOJoystickManager+ObjCBridge.mm', 'SDL/OOSDLJoystickManager.mm', 'SDL/OOSDLJoystickManager+ObjCBridge.mm', 'Core/OOJoystickProfile.mm', 'Core/OOJoystickProfile+ObjCBridge.mm', 'Core/OOCallByName.mm', 'Core/OODescription.mm'],
    'test_OORegExpMatcher': ['Core/OORegExpMatcher.mm', 'Core/OORegExpMatcher+ObjCBridge.mm'],
    'test_OOFileScannerVerifierStage': ['Core/OXPVerifier/OOFileScannerVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOOXPVerifierStage.mm', 'Core/OXPVerifier/OOOXPVerifierStage+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOAIStateMachineVerifierStage': ['Core/OXPVerifier/OOAIStateMachineVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOOXPVerifierStage.mm', 'Core/OXPVerifier/OOOXPVerifierStage+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOCheckJSSyntaxVerifierStage': ['Core/OXPVerifier/OOCheckJSSyntaxVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOOXPVerifierStage.mm', 'Core/OXPVerifier/OOOXPVerifierStage+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOCheckPListSyntaxVerifierStage': ['Core/OXPVerifier/OOCheckPListSyntaxVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOOXPVerifierStage.mm', 'Core/OXPVerifier/OOOXPVerifierStage+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOCheckDemoShipsPListVerifierStage': ['Core/OXPVerifier/OOCheckDemoShipsPListVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOOXPVerifierStage.mm', 'Core/OXPVerifier/OOOXPVerifierStage+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOCheckRequiresPListVerifierStage': ['Core/OXPVerifier/OOCheckRequiresPListVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOOXPVerifierStage.mm', 'Core/OXPVerifier/OOOXPVerifierStage+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOCheckEquipmentPListVerifierStage': ['Core/OXPVerifier/OOCheckEquipmentPListVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOOXPVerifierStage.mm', 'Core/OXPVerifier/OOOXPVerifierStage+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOTextureVerifierStage': ['Core/OXPVerifier/OOTextureVerifierStage.mm', 'Core/OXPVerifier/OOTextureVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOOXPVerifierStage.mm', 'Core/OXPVerifier/OOOXPVerifierStage+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOCheckShipDataPListVerifierStage': ['Core/OXPVerifier/OOCheckShipDataPListVerifierStage.mm', 'Core/OXPVerifier/OOCheckShipDataPListVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOModelVerifierStage.mm', 'Core/OXPVerifier/OOModelVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOAIStateMachineVerifierStage.mm', 'Core/OXPVerifier/OOTextureVerifierStage.mm', 'Core/OXPVerifier/OOTextureVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOOXPVerifierStage.mm', 'Core/OXPVerifier/OOOXPVerifierStage+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOModelVerifierStage': ['Core/OXPVerifier/OOModelVerifierStage.mm', 'Core/OXPVerifier/OOModelVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOTextureVerifierStage.mm', 'Core/OXPVerifier/OOTextureVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOOXPVerifierStage.mm', 'Core/OXPVerifier/OOOXPVerifierStage+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OODrawable': ['Core/OODrawable.mm', 'Core/OODrawable+ObjCBridge.mm', 'Core/NSObjectOOExtensions.mm', 'Core/OOVector.mm', 'Core/legacy_random.c', 'Core/OODescription.mm'],
    'test_OOMaterial': ['Core/Materials/OOMaterial.mm', 'Core/Materials/OOMaterial+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOShaderUniformMethodType': ['Core/Materials/OOShaderUniformMethodType.mm', 'Core/OOMatrix.mm', 'Core/OOOpenGLExtensionManager.mm', 'Core/OOOpenGLExtensionManager+ObjCBridge.mm', 'Core/OOVector.mm', 'Core/OOHPVector.mm', 'Core/OOQuaternion.cpp', 'Core/legacy_random.c'],
    'test_OOBasicMaterial': ['Core/Materials/OOBasicMaterial.mm', 'Core/Materials/OOBasicMaterial+ObjCBridge.mm', 'Core/Materials/OOMaterial.mm', 'Core/Materials/OOMaterial+ObjCBridge.mm', 'Core/Materials/OOMaterialSpecifier.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OOOpenGL.mm', 'Core/OODescription.mm'],
    'test_OOSingleTextureMaterial': ['Core/Materials/OOSingleTextureMaterial.mm', 'Core/Materials/OOSingleTextureMaterial+ObjCBridge.mm', 'Core/Materials/OOBasicMaterial.mm', 'Core/Materials/OOBasicMaterial+ObjCBridge.mm', 'Core/Materials/OOMaterial.mm', 'Core/Materials/OOMaterial+ObjCBridge.mm', 'Core/Materials/OOMaterialSpecifier.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OOOpenGL.mm', 'Core/OODescription.mm'],
    'test_OOMaterialConvenienceCreators': ['Core/Materials/OOMaterialConvenienceCreators.mm', 'Core/Materials/OOMaterialConvenienceCreators+ObjCBridge.mm', 'Core/Materials/OOShaderMaterial.mm', 'Core/Materials/OOShaderMaterial+ObjCBridge.mm', 'Core/Materials/OOSingleTextureMaterial.mm', 'Core/Materials/OOSingleTextureMaterial+ObjCBridge.mm', 'Core/Materials/OOMultiTextureMaterial.mm', 'Core/Materials/OOMultiTextureMaterial+ObjCBridge.mm', 'Core/Materials/OOBasicMaterial.mm', 'Core/Materials/OOBasicMaterial+ObjCBridge.mm', 'Core/Materials/OOMaterial.mm', 'Core/Materials/OOMaterial+ObjCBridge.mm', 'Core/Materials/OOMaterialSpecifier.mm', 'Core/Materials/OOShaderProgram.mm', 'Core/Materials/OOShaderProgram+ObjCBridge.mm', 'Core/Materials/OOShaderUniform.mm', 'Core/Materials/OOShaderUniform+ObjCBridge.mm', 'Core/Materials/OOShaderUniformMethodType.mm', 'Core/OOOpenGLMatrixManager.mm', 'Core/OOOpenGLMatrixManager+ObjCBridge.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OOOpenGL.mm', 'Core/OOOpenGLExtensionManager.mm', 'Core/OOOpenGLExtensionManager+ObjCBridge.mm', 'Core/OOWeakReference.mm', 'Core/OOWeakReference+ObjCBridge.mm', 'Core/OOPListGameTypes.mm', 'Core/OOIsNumberLiteral.cpp', 'Core/OOVector.mm', 'Core/OOVector+ObjCBridge.mm', 'Core/OOHPVector.mm', 'Core/OOQuaternion.cpp', 'Core/OOMatrix.mm', 'Core/legacy_random.c', 'Core/OODescription.mm'],
    'test_OOMultiTextureMaterial': ['Core/Materials/OOMultiTextureMaterial.mm', 'Core/Materials/OOMultiTextureMaterial+ObjCBridge.mm', 'Core/Materials/OOBasicMaterial.mm', 'Core/Materials/OOBasicMaterial+ObjCBridge.mm', 'Core/Materials/OOMaterial.mm', 'Core/Materials/OOMaterial+ObjCBridge.mm', 'Core/Materials/OOMaterialSpecifier.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OOOpenGL.mm', 'Core/OOOpenGLExtensionManager.mm', 'Core/OOOpenGLExtensionManager+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOShaderMaterial': ['Core/Materials/OOShaderMaterial.mm', 'Core/Materials/OOShaderMaterial+ObjCBridge.mm', 'Core/Materials/OOBasicMaterial.mm', 'Core/Materials/OOBasicMaterial+ObjCBridge.mm', 'Core/Materials/OOMaterial.mm', 'Core/Materials/OOMaterial+ObjCBridge.mm', 'Core/Materials/OOMaterialSpecifier.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OOOpenGL.mm', 'Core/OOOpenGLExtensionManager.mm', 'Core/OOOpenGLExtensionManager+ObjCBridge.mm', 'Core/OOWeakReference.mm', 'Core/OOWeakReference+ObjCBridge.mm', 'Core/OOPListGameTypes.mm', 'Core/OOIsNumberLiteral.cpp', 'Core/OOVector.mm', 'Core/OOVector+ObjCBridge.mm', 'Core/OOHPVector.mm', 'Core/OOQuaternion.cpp', 'Core/OOMatrix.mm', 'Core/legacy_random.c', 'Core/OODescription.mm'],
    'test_OODefaultShaderSynthesizer': ['*'],
    'test_OOShaderUniform': ['Core/Materials/OOShaderUniform.mm', 'Core/Materials/OOShaderUniform+ObjCBridge.mm', 'Core/Materials/OOShaderUniformMethodType.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OOOpenGL.mm', 'Core/OOOpenGLExtensionManager.mm', 'Core/OOOpenGLExtensionManager+ObjCBridge.mm', 'Core/OOWeakReference.mm', 'Core/OOWeakReference+ObjCBridge.mm', 'Core/OOVector.mm', 'Core/OOHPVector.mm', 'Core/OOQuaternion.cpp', 'Core/OOMatrix.mm', 'Core/legacy_random.c', 'Core/OODescription.mm'],
    'test_OOShaderProgram': ['Core/Materials/OOShaderProgram.mm', 'Core/Materials/OOShaderProgram+ObjCBridge.mm', 'Core/OOOpenGLMatrixManager.mm', 'Core/OOOpenGLMatrixManager+ObjCBridge.mm', 'Core/OOOpenGL.mm', 'Core/OOOpenGLExtensionManager.mm', 'Core/OOOpenGLExtensionManager+ObjCBridge.mm', 'Core/OOMatrix.mm', 'Core/OOVector.mm', 'Core/OOHPVector.mm', 'Core/OOQuaternion.cpp', 'Core/legacy_random.c', 'Core/OODescription.mm'],
    'test_OOOXPVerifierStage': ['Core/OXPVerifier/OOOXPVerifierStage.mm', 'Core/OXPVerifier/OOOXPVerifierStage+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOPListSchemaVerifier': ['Core/OXPVerifier/OOPListSchemaVerifier.mm', 'Core/OXPVerifier/OOPListSchemaVerifier+ObjCBridge.mm', 'Core/OOPListGameTypes.mm', 'Core/OOIsNumberLiteral.cpp', 'Core/OOVector.mm', 'Core/OOVector+ObjCBridge.mm', 'Core/OOHPVector.mm', 'Core/OOQuaternion.cpp', 'Core/legacy_random.c', 'Core/OODescription.mm'],
    'test_OOOpenALController': ['Core/OOOpenALController.mm'],
    'test_OOSound': ['Core/OOALSound.mm', 'Core/OOALSound+ObjCBridge.mm', 'Core/OOOpenALController.mm', 'Core/OODescription.mm'],
    'test_OOALSoundDecoder': ['Core/OOALSoundDecoder.mm', 'Core/OOALSoundDecoder+ObjCBridge.mm', 'Core/MiniZip/unzip.c', 'Core/MiniZip/ioapi.c', 'Core/OODescription.mm'],
    'test_OOALBufferedSound': ['Core/OOALBufferedSound.mm', 'Core/OOALBufferedSound+ObjCBridge.mm', 'Core/OOALSound.mm', 'Core/OOALSound+ObjCBridge.mm', 'Core/OOALSoundDecoder.mm', 'Core/OOALSoundDecoder+ObjCBridge.mm', 'Core/MiniZip/unzip.c', 'Core/MiniZip/ioapi.c', 'Core/OOOpenALController.mm', 'Core/OODescription.mm'],
    'test_OOALStreamedSound': ['Core/OOALStreamedSound.mm', 'Core/OOALStreamedSound+ObjCBridge.mm', 'Core/OOALSound.mm', 'Core/OOALSound+ObjCBridge.mm', 'Core/OOALSoundDecoder.mm', 'Core/OOALSoundDecoder+ObjCBridge.mm', 'Core/MiniZip/unzip.c', 'Core/MiniZip/ioapi.c', 'Core/OOOpenALController.mm', 'Core/OODescription.mm'],
    'test_OOMusic': ['Core/OOALMusic.mm', 'Core/OOALMusic+ObjCBridge.mm', 'Core/OOVector.mm', 'Core/legacy_random.c', 'Core/OOALSound.mm', 'Core/OOALSound+ObjCBridge.mm', 'Core/OOSoundSource.mm', 'Core/OOSoundSource+ObjCBridge.mm', 'Core/OOOpenALController.mm', 'Core/OODescription.mm'],
    'test_OOSoundChannel': ['Core/OOALSoundChannel.mm', 'Core/OOALSoundChannel+ObjCBridge.mm', 'Core/OOALSound.mm', 'Core/OOALSound+ObjCBridge.mm', 'Core/OOOpenALController.mm', 'Core/OODescription.mm'],
    'test_OOSoundMixer': ['Core/OOALSoundMixer.mm', 'Core/OOALSoundMixer+ObjCBridge.mm', 'Core/OOALSound.mm', 'Core/OOALSound+ObjCBridge.mm', 'Core/OOOpenALController.mm', 'Core/OODescription.mm'],
    'test_OOSoundSource': ['Core/OOSoundSource.mm', 'Core/OOSoundSource+ObjCBridge.mm', 'Core/OOVector.mm', 'Core/legacy_random.c', 'Core/OODescription.mm'],
    'test_OOSoundSourcePool': ['Core/OOSoundSourcePool.mm', 'Core/OOSoundSourcePool+ObjCBridge.mm', 'Core/OOVector.mm', 'Core/legacy_random.c'],
    'test_OOMusicController': ['Core/OOMusicController.mm', 'Core/OOMusicController+ObjCBridge.mm'],
    'test_OOShipGroup': ['Core/OOShipGroup.mm', 'Core/OOShipGroup+ObjCBridge.mm', 'Core/OOWeakReference.mm', 'Core/OOWeakReference+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOGraphicsResetManager': ['Core/OOGraphicsResetManager.mm', 'Core/OOGraphicsResetManager+ObjCBridge.mm', 'Core/OOOpenGLExtensionManager.mm', 'Core/OOOpenGLExtensionManager+ObjCBridge.mm'],
    'test_OOOpenGLOnly': [],	# src/Core/OOOpenGLOnly.h (upstream #748)
    'test_OOOpenGLExtensionManager': ['Core/OOOpenGLExtensionManager.mm', 'Core/OOOpenGLExtensionManager+ObjCBridge.mm'],
    'test_OOOpenGLStateManager': ['Core/OOOpenGLStateManager.mm', 'Core/OOOpenGL.mm', 'Core/OOOpenGLExtensionManager.mm', 'Core/OOOpenGLExtensionManager+ObjCBridge.mm'],
    'test_OOTextureSprite': ['Core/OOTextureSprite.mm', 'Core/OOTextureSprite+ObjCBridge.mm', 'Core/OOOpenGLStateManager.mm', 'Core/OOOpenGL.mm', 'Core/OOOpenGLExtensionManager.mm', 'Core/OOOpenGLExtensionManager+ObjCBridge.mm'],
    'test_OOTexture': ['*'],
    'test_OONullTexture': ['*'],
    'test_OOConcreteTexture': ['*'],
    'test_OOTextureScaling': ['Core/OOTextureScaling.mm', 'Core/Materials/OOPixMap.mm'],
    'test_OOTextureLoader': ['*'],
    'test_OOTextureGenerator': ['*'],
    'test_OOPNGTextureLoader': ['*'],
    'test_OOPixMapTextureLoader': ['*'],
    'test_OOCombinedEmissionMapGenerator': ['*'],
    'test_OOStandaloneAtmosphereGenerator': ['*'],
    'test_OOPlanetTextureGenerator': ['*'],
    'test_OOCrosshairs': ['Core/OOCrosshairs.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOOpenGLMatrixManager': ['Core/OOOpenGLMatrixManager.mm', 'Core/OOOpenGLMatrixManager+ObjCBridge.mm', 'Core/OOMatrix.mm', 'Core/OOVector.mm', 'Core/legacy_random.c', 'Core/OOOpenGLExtensionManager.mm', 'Core/OOOpenGLExtensionManager+ObjCBridge.mm'],
    'test_OOCharacter': ['Core/OOCharacter.mm', 'Core/OOCharacter+ObjCBridge.mm', 'Core/legacy_random.c', 'Core/OODescription.mm'],
    'test_OOTrumble': ['Core/OOTrumble.mm', 'Core/OOTrumble+ObjCBridge.mm', 'Core/OOVector.mm', 'Core/legacy_random.c'],
    'test_OOCommodities': ['Core/OOCommodities.mm', 'Core/OOCommodities+ObjCBridge.mm', 'Core/OOCommodityMarket.mm', 'Core/OOCommodityMarket+ObjCBridge.mm', 'Core/legacy_random.c'],
    'test_OOCommodityMarket': ['Core/OOCommodityMarket.mm', 'Core/OOCommodityMarket+ObjCBridge.mm'],
    'test_OOEquipmentType': ['Core/OOEquipmentType.mm', 'Core/OOEquipmentType+ObjCBridge.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOConstToString': ['Core/OOConstToString.mm', 'Core/OOEquipmentType.mm', 'Core/OOEquipmentType+ObjCBridge.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OOCommodityMarket.mm', 'Core/OOCommodityMarket+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOPriorityQueue': ['Core/OOPriorityQueue.mm', 'Core/OODescription.mm'],
    'test_OORoleSet': ['Core/OORoleSet.mm', 'Core/OORoleSet+ObjCBridge.mm', 'Core/OODescription.mm', 'Core/legacy_random.c'],
    'test_OOProbabilitySet': ['Core/OOProbabilitySet.mm', 'Core/OODescription.mm', 'Core/legacy_random.c'],
    'test_OOShipRegistry': ['Core/OOShipRegistry.mm', 'Core/OOShipRegistry+ObjCBridge.mm', 'Core/OORoleSet.mm', 'Core/OORoleSet+ObjCBridge.mm', 'Core/OOCacheManager.mm', 'Core/OOCacheManager+ObjCBridge.mm', 'Core/OOProbabilitySet.mm', 'Core/OOPListGameTypes.mm', 'Core/OOIsNumberLiteral.cpp', 'Core/OOVector.mm', 'Core/OOVector+ObjCBridge.mm', 'Core/OOHPVector.mm', 'Core/OOQuaternion.cpp', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/legacy_random.c', 'Core/OODescription.mm'],
    'test_OOProbabilisticTextureManager': ['Core/OOProbabilisticTextureManager.mm', 'Core/OODescription.mm', 'Core/legacy_random.c'],
    'test_CollisionRegion': ['*'],
    'test_Octree': ['*'],
    'test_OOJSVector': ['Core/Scripting/OOJSVector.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/OOHPVector.mm', 'Core/OOVector.mm', 'Core/OOQuaternion.cpp', 'Core/legacy_random.c'],
    'test_OOJSDock': ['Core/Scripting/OOJSDock.mm', 'Core/Scripting/OOJSDock+ObjCBridge.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm'],
    'test_OOJSSoundSource': ['Core/Scripting/OOJSSoundSource.mm', 'Core/Scripting/OOJSSoundSource+ObjCBridge.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm'],
    'test_OOJSSound': ['Core/Scripting/OOJSSound.mm', 'Core/Scripting/OOJSSound+ObjCBridge.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm'],
    'test_OOJSSun': ['Core/Scripting/OOJSSun.mm', 'Core/Scripting/OOJSSun+ObjCBridge.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm'],
    'test_OOJSOolite': ['Core/Scripting/OOJSOolite.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm'],
    'test_OOJSEquipmentInfo': ['Core/Scripting/OOJSEquipmentInfo.mm', 'Core/Scripting/OOJSEquipmentInfo+ObjCBridge.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/OOEquipmentType.mm', 'Core/OOEquipmentType+ObjCBridge.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OOWeakReference.mm', 'Core/OOWeakReference+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOJSPlayer': ['Core/Scripting/OOJSPlayer.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/OODescription.mm', 'Core/legacy_random.c'],
    'test_OOJSEntity': ['Core/Scripting/OOJSEntity.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/Scripting/OOConstToJSString.cpp', 'Core/OOQuaternion.cpp', 'Core/OOVector.mm', 'Core/OOHPVector.mm', 'Core/legacy_random.c'],
    'test_OOJSMissionVariables': ['Core/Scripting/OOJSMissionVariables.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/OOIsNumberLiteral.cpp'],
    'test_OOJSMission': ['Core/Scripting/OOJSMission.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/Scripting/OOConstToJSString.cpp', 'Core/OODescription.mm', 'Core/OOVector.mm', 'Core/legacy_random.c'],
    'test_OOJSStation': ['Core/Scripting/OOJSStation.mm', 'Core/Scripting/OOJSStation+ObjCBridge.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/OOCommodities.mm', 'Core/OOCommodities+ObjCBridge.mm', 'Core/OOCommodityMarket.mm', 'Core/OOCommodityMarket+ObjCBridge.mm', 'Core/Scripting/OOJSInterfaceDefinition.mm', 'Core/Scripting/OOJSInterfaceDefinition+ObjCBridge.mm', 'Core/OOWeakReference.mm', 'Core/OOWeakReference+ObjCBridge.mm', 'Core/OOEquipmentType.mm', 'Core/OOEquipmentType+ObjCBridge.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OODescription.mm', 'Core/legacy_random.c'],
    'test_OOJSGlobal': ['Core/Scripting/OOJSGlobal.mm', 'Core/Scripting/OOJSGlobal+ObjCBridge.mm', 'Core/Scripting/OOConstToJSString.cpp', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/Scripting/OOJSGuiScreenKeyDefinition.mm', 'Core/Scripting/OOJSGuiScreenKeyDefinition+ObjCBridge.mm', 'Core/OOWeakReference.mm', 'Core/OOWeakReference+ObjCBridge.mm', 'Core/OODescription.mm', 'Core/legacy_random.c'],
    'test_OOJSPlanet': ['Core/Scripting/OOJSPlanet.mm', 'Core/Scripting/OOJSPlanet+ObjCBridge.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOJSSystemInfo': ['Core/Scripting/OOJSSystemInfo.mm', 'Core/Scripting/OOJSSystemInfo+ObjCBridge.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/OOSystemDescriptionManager.mm', 'Core/OOSystemDescriptionManager+ObjCBridge.mm', 'Core/OOCommodities.mm', 'Core/OOCommodities+ObjCBridge.mm', 'Core/OOCommodityMarket.mm', 'Core/OOCommodityMarket+ObjCBridge.mm', 'Core/OODescription.mm', 'Core/OOIsNumberLiteral.cpp', 'Core/legacy_random.c'],
    'test_OOJSManifest': ['Core/Scripting/OOJSManifest.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/OOCommodities.mm', 'Core/OOCommodities+ObjCBridge.mm', 'Core/OOCommodityMarket.mm', 'Core/OOCommodityMarket+ObjCBridge.mm', 'Core/legacy_random.c'],
    'test_OOJSShipGroup': ['Core/Scripting/OOJSShipGroup.mm', 'Core/Scripting/OOJSShipGroup+ObjCBridge.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/OOShipGroup.mm', 'Core/OOShipGroup+ObjCBridge.mm', 'Core/OOWeakReference.mm', 'Core/OOWeakReference+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOJSVisualEffect': ['Core/Scripting/OOJSVisualEffect.mm', 'Core/Scripting/OOJSVisualEffect+ObjCBridge.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOJSWaypoint': ['Core/Scripting/OOJSWaypoint.mm', 'Core/Scripting/OOJSWaypoint+ObjCBridge.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/OOQuaternion.cpp', 'Core/OOVector.mm', 'Core/OOHPVector.mm', 'Core/legacy_random.c'],
    'test_OOJSFlasher': ['Core/Scripting/OOJSFlasher.mm', 'Core/Scripting/OOJSFlasher+ObjCBridge.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOJSExhaustPlume': ['Core/Scripting/OOJSExhaustPlume.mm', 'Core/Scripting/OOJSExhaustPlume+ObjCBridge.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm'],
    'test_OOJSQuaternion': ['Core/Scripting/OOJSQuaternion.mm', 'Core/Scripting/OOJSVector.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/OOHPVector.mm', 'Core/OOVector.mm', 'Core/OOQuaternion.cpp', 'Core/legacy_random.c'],
    'test_OOJSClock': ['Core/Scripting/OOJSClock.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm'],
    'test_OoliteEquipmentControlScript': [],	# Resources/Scripts/oolite-equipment-control.js (upstream #369)
    'test_OOMeshToOctreeConverter': ['*'],
    'test_OOPolygonSprite': ['*'],
    'test_OOVector': ['Core/OOVector.mm', 'Core/OOVector+ObjCBridge.mm', 'Core/legacy_random.c', 'Core/OODescription.mm'],
    'test_OOAsyncQueue': ['Core/OOAsyncQueue.mm'],
    'test_OOProfilingStopwatch': ['Core/OOProfilingStopwatch.mm'],
    'test_OOAsyncWorkManager': ['Core/OOAsyncWorkManager.mm', 'Core/OOAsyncWorkManager+ObjCBridge.mm', 'Core/OOAsyncQueue.mm', 'Core/OOCPUInfo.mm', 'Core/OODescription.mm'],
    'test_AI': ['Core/AI.mm', 'Core/AI+ObjCBridge.mm', 'Core/OOWeakReference.mm', 'Core/OOWeakReference+ObjCBridge.mm', 'Core/OOCallByName.mm', 'Core/OODescription.mm'],
    'test_OOWeakReference': ['Core/OOWeakReference.mm', 'Core/OOWeakReference+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOWeakSet': ['Core/OOWeakSet.mm', 'Core/OOWeakSet+ObjCBridge.mm', 'Core/OOWeakReference.mm', 'Core/OOWeakReference+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOJSFunction': ['Core/Scripting/OOJSFunction.mm', 'Core/Scripting/OOJSFunction+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOJSTimer': ['Core/Scripting/OOJSTimer.mm', 'Core/Scripting/OOJSTimer+ObjCBridge.mm', 'Core/Scripting/OOScriptTimer.mm', 'Core/Scripting/OOScriptTimer+ObjCBridge.mm', 'Core/OOPriorityQueue.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/OODescription.mm'],
    'test_OOScriptTimer': ['Core/Scripting/OOScriptTimer.mm', 'Core/Scripting/OOScriptTimer+ObjCBridge.mm', 'Core/OOPriorityQueue.mm', 'Core/OODescription.mm'],
    'test_OOJSFrameCallbacks': ['Core/Scripting/OOJSFrameCallbacks.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm'],
    'test_OOJSCall': ['Core/Scripting/OOJSCall.mm', 'Core/Scripting/OOJSCall+ObjCBridge.mm', 'Core/OOCallByName.mm', 'Core/Materials/OOShaderUniformMethodType.mm', 'Core/OODescription.mm'],
    'test_OOSystemDescriptionManager': ['Core/OOSystemDescriptionManager.mm', 'Core/OOSystemDescriptionManager+ObjCBridge.mm', 'Core/OODescription.mm', 'Core/legacy_random.c'],
    'test_GuiDisplayGen': ['*'],
    'test_Entity': ['*'],
    'test_OOEntityWithDrawable': ['*'],
    'test_OOPlanetEntity': ['*'],
    'test_OOPlanetDrawable': ['*'],
    'test_EntityOOJavaScriptExtensions': ['*'],
    'test_EntityShaderBindings': ['*'],
    'test_WormholeEntity': ['*'],
    'test_OOSunEntity': ['*'],
    'test_OOExhaustPlumeEntity': ['*'],
    'test_SkyEntity': ['*'],
    'test_OOSkyDrawable': ['*'],
    'test_OOWaypointEntity': ['*'],
    'test_OOFlasherEntity': ['*'],
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
    'test_OODebugMonitor': ['Core/Debug/OODebugMonitor.mm', 'Core/Debug/OODebugMonitor+ObjCBridge.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OOWeakReference.mm', 'Core/OOWeakReference+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOJSConsole': ['Core/Debug/OOJSConsole.mm', 'Core/Debug/OOJSConsole+ObjCBridge.mm', 'Core/Debug/OODebugMonitor+ObjCBridge.mm', 'Core/Scripting/OOJSEngineTimeManagement.mm', 'Core/Scripting/OOJSEngineTimeManagement+ObjCBridge.mm', 'Core/OOProfilingStopwatch.mm', 'Core/OOWeakReference.mm', 'Core/OOWeakReference+ObjCBridge.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/OODescription.mm'],
    'test_OODebugTCPConsoleClient': ['Core/Debug/OODebugTCPConsoleClient.mm', 'Core/Debug/OODebugTCPConsoleClient+ObjCBridge.mm', 'Core/Debug/OOTCPStreamDecoder.c', 'Core/Debug/OOTCPStreamDecoderAbstractionLayer.mm', 'Core/OODescription.mm'],
    'test_OODebugSupport': ['Core/Debug/OODebugSupport.mm', 'Core/Debug/OODebugSupport+ObjCBridge.mm'],
    'test_OODebugStandards': ['Core/Debug/OODebugStandards.mm'],
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
        if rel in wanted or (whole_game and rel != 'src/SDL/main.mm')
            sources += [f]
        endif
    endforeach
    assert(whole_game or sources.length() == game_sources.length(), name + ': a game source in core_tests is not in the oolite target')
    exe = executable(
        'core_' + name,
        name + '.mm',
        objects: oolite_bin.extract_objects(sources),
        include_directories: [oolite_includes, include_directories('../oofnd')],
        dependencies: oolite_dependencies,
        override_options: oolite_override_options,
        install: false,
    )
    test(name, exe, suite: 'core', timeout: 60)
endforeach
