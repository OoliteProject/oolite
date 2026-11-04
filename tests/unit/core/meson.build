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
    'test_OOCache': ['Core/OOCache.mm', 'Core/OODescription.mm'],
    'test_OOCacheManager': ['Core/OOCacheManager.mm', 'Core/OOCacheManager+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOEncodingConverter': ['Core/OOEncodingConverter.mm', 'Core/OOCache.mm', 'Core/OODescription.mm'],
    'test_OOFullScreenController': ['Core/OOFullScreenController.mm'],
    'test_OOSoundReferencePoint': ['Core/OOBasicSoundReferencePoint.mm'],
    'test_OOColor': ['Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOJoystickProfile': ['Core/OOJoystickProfile.mm', 'Core/OOJoystickProfile+ObjCBridge.mm'],
    'test_OOSDLJoystickManager': ['SDL/OOSDLJoystickManager.mm', 'SDL/OOSDLJoystickManager+ObjCBridge.mm', 'Core/OOJoystickManager.mm', 'Core/OOJoystickProfile.mm', 'Core/OOJoystickProfile+ObjCBridge.mm', 'Core/OOCallByName.mm', 'Core/OODescription.mm'],
    'test_OORegExpMatcher': ['Core/OORegExpMatcher.mm', 'Core/OORegExpMatcher+ObjCBridge.mm'],
    'test_OOFileScannerVerifierStage': ['Core/OXPVerifier/OOFileScannerVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOOXPVerifierStage.mm', 'Core/OXPVerifier/OOOXPVerifierStage+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOAIStateMachineVerifierStage': ['Core/OXPVerifier/OOAIStateMachineVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOOXPVerifierStage.mm', 'Core/OXPVerifier/OOOXPVerifierStage+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOCheckJSSyntaxVerifierStage': ['Core/OXPVerifier/OOCheckJSSyntaxVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOOXPVerifierStage.mm', 'Core/OXPVerifier/OOOXPVerifierStage+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOCheckPListSyntaxVerifierStage': ['Core/OXPVerifier/OOCheckPListSyntaxVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOOXPVerifierStage.mm', 'Core/OXPVerifier/OOOXPVerifierStage+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOCheckDemoShipsPListVerifierStage': ['Core/OXPVerifier/OOCheckDemoShipsPListVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOOXPVerifierStage.mm', 'Core/OXPVerifier/OOOXPVerifierStage+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOCheckRequiresPListVerifierStage': ['Core/OXPVerifier/OOCheckRequiresPListVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOOXPVerifierStage.mm', 'Core/OXPVerifier/OOOXPVerifierStage+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOCheckEquipmentPListVerifierStage': ['Core/OXPVerifier/OOCheckEquipmentPListVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage.mm', 'Core/OXPVerifier/OOFileScannerVerifierStage+ObjCBridge.mm', 'Core/OXPVerifier/OOOXPVerifierStage.mm', 'Core/OXPVerifier/OOOXPVerifierStage+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OODrawable': ['Core/OODrawable.mm', 'Core/OODrawable+ObjCBridge.mm', 'Core/NSObjectOOExtensions.mm', 'Core/OOVector.mm', 'Core/legacy_random.c', 'Core/OODescription.mm'],
    'test_OOMaterial': ['Core/Materials/OOMaterial.mm', 'Core/Materials/OOMaterial+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOShaderUniformMethodType': ['Core/Materials/OOShaderUniformMethodType.mm', 'Core/OOMatrix.mm', 'Core/OOOpenGLExtensionManager.mm', 'Core/OOOpenGLExtensionManager+ObjCBridge.mm', 'Core/OOVector.mm', 'Core/OOHPVector.mm', 'Core/OOQuaternion.cpp', 'Core/legacy_random.c'],
    'test_OOBasicMaterial': ['Core/Materials/OOBasicMaterial.mm', 'Core/Materials/OOBasicMaterial+ObjCBridge.mm', 'Core/Materials/OOMaterial.mm', 'Core/Materials/OOMaterial+ObjCBridge.mm', 'Core/Materials/OOMaterialSpecifier.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OOOpenGL.mm', 'Core/OODescription.mm'],
    'test_OOSingleTextureMaterial': ['Core/Materials/OOSingleTextureMaterial.mm', 'Core/Materials/OOSingleTextureMaterial+ObjCBridge.mm', 'Core/Materials/OOBasicMaterial.mm', 'Core/Materials/OOBasicMaterial+ObjCBridge.mm', 'Core/Materials/OOMaterial.mm', 'Core/Materials/OOMaterial+ObjCBridge.mm', 'Core/Materials/OOMaterialSpecifier.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OOOpenGL.mm', 'Core/OODescription.mm'],
    'test_OOMultiTextureMaterial': ['Core/Materials/OOMultiTextureMaterial.mm', 'Core/Materials/OOMultiTextureMaterial+ObjCBridge.mm', 'Core/Materials/OOBasicMaterial.mm', 'Core/Materials/OOBasicMaterial+ObjCBridge.mm', 'Core/Materials/OOMaterial.mm', 'Core/Materials/OOMaterial+ObjCBridge.mm', 'Core/Materials/OOMaterialSpecifier.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OOOpenGL.mm', 'Core/OOOpenGLExtensionManager.mm', 'Core/OOOpenGLExtensionManager+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOOXPVerifierStage': ['Core/OXPVerifier/OOOXPVerifierStage.mm', 'Core/OXPVerifier/OOOXPVerifierStage+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOOpenALController': ['Core/OOOpenALController.mm'],
    'test_OOShipGroup': ['Core/OOShipGroup.mm', 'Core/OOShipGroup+ObjCBridge.mm', 'Core/OOWeakReference.mm', 'Core/OOWeakReference+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOGraphicsResetManager': ['Core/OOGraphicsResetManager.mm', 'Core/OOGraphicsResetManager+ObjCBridge.mm', 'Core/OOOpenGLExtensionManager.mm', 'Core/OOOpenGLExtensionManager+ObjCBridge.mm'],
    'test_OOOpenGLOnly': [],	# src/Core/OOOpenGLOnly.h (upstream #748)
    'test_OOOpenGLExtensionManager': ['Core/OOOpenGLExtensionManager.mm', 'Core/OOOpenGLExtensionManager+ObjCBridge.mm'],
    'test_OOOpenGLStateManager': ['Core/OOOpenGLStateManager.mm', 'Core/OOOpenGL.mm', 'Core/OOOpenGLExtensionManager.mm', 'Core/OOOpenGLExtensionManager+ObjCBridge.mm'],
    'test_OOCrosshairs': ['Core/OOCrosshairs.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOOpenGLMatrixManager': ['Core/OOOpenGLMatrixManager.mm', 'Core/OOOpenGLMatrixManager+ObjCBridge.mm', 'Core/OOMatrix.mm', 'Core/OOVector.mm', 'Core/legacy_random.c', 'Core/OOOpenGLExtensionManager.mm', 'Core/OOOpenGLExtensionManager+ObjCBridge.mm'],
    'test_OOCharacter': ['Core/OOCharacter.mm', 'Core/OOCharacter+ObjCBridge.mm', 'Core/legacy_random.c', 'Core/OODescription.mm'],
    'test_OOTrumble': ['Core/OOTrumble.mm', 'Core/OOTrumble+ObjCBridge.mm', 'Core/OOVector.mm', 'Core/legacy_random.c'],
    'test_OOCommodities': ['Core/OOCommodities.mm', 'Core/OOCommodities+ObjCBridge.mm', 'Core/OOCommodityMarket.mm', 'Core/OOCommodityMarket+ObjCBridge.mm', 'Core/legacy_random.c'],
    'test_OOCommodityMarket': ['Core/OOCommodityMarket.mm', 'Core/OOCommodityMarket+ObjCBridge.mm'],
    'test_OOEquipmentType': ['Core/OOEquipmentType.mm', 'Core/OOEquipmentType+ObjCBridge.mm', 'Core/OOColor.mm', 'Core/OOColor+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOPriorityQueue': ['Core/OOPriorityQueue.mm', 'Core/OODescription.mm'],
    'test_OORoleSet': ['Core/OORoleSet.mm', 'Core/OORoleSet+ObjCBridge.mm', 'Core/OODescription.mm', 'Core/legacy_random.c'],
    'test_OOProbabilitySet': ['Core/OOProbabilitySet.mm', 'Core/OODescription.mm', 'Core/legacy_random.c'],
    'test_CollisionRegion': ['*'],
    'test_Octree': ['*'],
    'test_OOJSVector': ['Core/Scripting/OOJSVector.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/OOHPVector.mm', 'Core/OOVector.mm', 'Core/OOQuaternion.cpp', 'Core/legacy_random.c'],
    'test_OOJSQuaternion': ['Core/Scripting/OOJSQuaternion.mm', 'Core/Scripting/OOJSVector.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/OOHPVector.mm', 'Core/OOVector.mm', 'Core/OOQuaternion.cpp', 'Core/legacy_random.c'],
    'test_OOJSClock': ['Core/Scripting/OOJSClock.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm'],
    'test_OoliteEquipmentControlScript': [],	# Resources/Scripts/oolite-equipment-control.js (upstream #369)
    'test_OOMeshToOctreeConverter': ['*'],
    'test_OOPolygonSprite': ['*'],
    'test_OOVector': ['Core/OOVector.mm', 'Core/OOVector+ObjCBridge.mm', 'Core/legacy_random.c', 'Core/OODescription.mm'],
    'test_OOAsyncQueue': ['Core/OOAsyncQueue.mm'],
    'test_OOProfilingStopwatch': ['Core/OOProfilingStopwatch.mm'],
    'test_OOAsyncWorkManager': ['Core/OOAsyncWorkManager.mm', 'Core/OOAsyncWorkManager+ObjCBridge.mm', 'Core/OOAsyncQueue.mm', 'Core/OOCPUInfo.mm', 'Core/OODescription.mm'],
    'test_OOWeakReference': ['Core/OOWeakReference.mm', 'Core/OOWeakReference+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOWeakSet': ['Core/OOWeakSet.mm', 'Core/OOWeakSet+ObjCBridge.mm', 'Core/OOWeakReference.mm', 'Core/OOWeakReference+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOJSFunction': ['Core/Scripting/OOJSFunction.mm', 'Core/Scripting/OOJSFunction+ObjCBridge.mm', 'Core/OODescription.mm'],
    'test_OOJSTimer': ['Core/Scripting/OOJSTimer.mm', 'Core/Scripting/OOJSTimer+ObjCBridge.mm', 'Core/Scripting/OOScriptTimer.mm', 'Core/Scripting/OOScriptTimer+ObjCBridge.mm', 'Core/OOPriorityQueue.mm', 'Core/Scripting/OOJSEngineNativeWrappers.mm', 'Core/Scripting/OOJSClasses.mm', 'Core/OODescription.mm'],
    'test_OOScriptTimer': ['Core/Scripting/OOScriptTimer.mm', 'Core/Scripting/OOScriptTimer+ObjCBridge.mm', 'Core/OOPriorityQueue.mm', 'Core/OODescription.mm'],
    'test_OOSystemDescriptionManager': ['Core/OOSystemDescriptionManager.mm', 'Core/OOSystemDescriptionManager+ObjCBridge.mm', 'Core/OODescription.mm', 'Core/legacy_random.c'],
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
