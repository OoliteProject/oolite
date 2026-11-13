/*

OOEntityObjectNamesTable.h

The names a C++ entity answers outside the by-name table
OOEntityCalledByNameTable.h: for a ship, a station, a dock, the player, a proxy,
a visual effect and a waypoint, each name of its class and its root classes,
with the Objective-C dispatcher's rules (a planet's five shader names from their
declarations). This file is the source.

One row per name: when the object answers it (null: every entity; the planet's
and the beacon's names for the parts that answer them), the kind
(OOEntityCalledByName.h) and the method's type encoding, as the dispatcher logs
it. The JS glue (isVisibleToScripts, deleteJSSelf) has no row: a call to it does
not respond. Included by OOEntityCalledByName.cpp only, after AnswersPlanet()
and AnswersBeacon().

*/

#pragma once

const OOEntityObjectName kOOEntityObjectNames[] = {
    {"absolutePositionForSubentity", nullptr,
     OOEntityObjectNameKind::kSignature, "{HPVector=ddd}16@0:8"},
    {"absolutePositionForSubentityOffset:", nullptr,
     OOEntityObjectNameKind::kSignature,
     "{HPVector=ddd}40@0:8{HPVector=ddd}16"},
    {"addToLinkedLists", nullptr, OOEntityObjectNameKind::kCalled, "v16@0:8"},
    {"airColorAsVector", &AnswersPlanet, OOEntityObjectNameKind::kSignature,
     "{Vector=fff}16@0:8"},
    {"airColorMixRatio", &AnswersPlanet, OOEntityObjectNameKind::kCalled,
     "f16@0:8"},
    {"airDensity", &AnswersPlanet, OOEntityObjectNameKind::kCalled, "f16@0:8"},
    {"applyRoll:andClimb:", nullptr, OOEntityObjectNameKind::kSignature,
     "v24@0:8f16f20"},
    {"applyRoll:climb:andYaw:", nullptr, OOEntityObjectNameKind::kSignature,
     "v28@0:8f16f20f24"},
    {"applyVelocity:", nullptr, OOEntityObjectNameKind::kSignature,
     "v24@0:8d16"},
    {"autorelease", nullptr, OOEntityObjectNameKind::kLifetime, "@16@0:8"},
    {"beaconCode", &AnswersBeacon, OOEntityObjectNameKind::kSignature,
     "{optional<std::basic_string<char>>={_Optional_payload<std::basic_string<"
     "char>, false, false, false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}16@0:8"},
    {"beaconDrawable", &AnswersBeacon, OOEntityObjectNameKind::kSignature,
     "^{OOHUDBeaconIcon=^^?{atomic<unsigned int>=I}^{WeakControl}}16@0:8"},
    {"beaconLabel", &AnswersBeacon, OOEntityObjectNameKind::kSignature,
     "{optional<std::basic_string<char>>={_Optional_payload<std::basic_string<"
     "char>, false, false, false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}16@0:8"},
    {"boundingBox", nullptr, OOEntityObjectNameKind::kSignature,
     "{?={Vector=fff}{Vector=fff}}16@0:8"},
    {"camZeroDistance", nullptr, OOEntityObjectNameKind::kCalled, "d16@0:8"},
    {"cameraRangeBack", nullptr, OOEntityObjectNameKind::kCalled, "f16@0:8"},
    {"cameraRangeFront", nullptr, OOEntityObjectNameKind::kCalled, "f16@0:8"},
    {"cameraRelativePosition", nullptr, OOEntityObjectNameKind::kSignature,
     "{Vector=fff}16@0:8"},
    {"canCollide", nullptr, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"checkCloseCollisionWith:", nullptr, OOEntityObjectNameKind::kSignature,
     "c24@0:8@16"},
    {"class", nullptr, OOEntityObjectNameKind::kSignature, "#16@0:8"},
    {"collisionRadius", nullptr, OOEntityObjectNameKind::kCalled, "f16@0:8"},
    {"compareBeaconCodeWith:", &AnswersBeacon,
     OOEntityObjectNameKind::kSignature, "q24@0:8@16"},
    {"compareZeroDistance:", nullptr, OOEntityObjectNameKind::kSignature,
     "q24@0:8@16"},
    {"conformsToProtocol:", nullptr, OOEntityObjectNameKind::kSignature,
     "c24@0:8@16"},
    {"copy", nullptr, OOEntityObjectNameKind::kLifetime, "@16@0:8"},
#ifdef OO_DEBUG_MONITOR_ENABLED
    {"cxx_allTextures", nullptr, OOEntityObjectNameKind::kSignature,
     "{vector<std::shared_ptr<OOTexture>, "
     "std::allocator<std::shared_ptr<OOTexture>>>={_Vector_impl=^{Ref<OOTexture>}^{Ref<"
     "OOTexture>}^{Ref<OOTexture>}}}16@0:8"},
#endif
    {"cxx_collidingEntities", nullptr, OOEntityObjectNameKind::kSignature,
     "^{vector<oo::EntityHold, "
     "std::allocator<oo::EntityHold>>={_Vector_impl=^{EntityHold}^{EntityHold}^"
     "{EntityHold}}}16@0:8"},
    {"cxx_description", nullptr, OOEntityObjectNameKind::kSignature,
     "{optional<std::basic_string<char>>={_Optional_payload<std::basic_string<"
     "char>, false, false, false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}16@0:8"},
    {"cxx_descriptionComponents", nullptr, OOEntityObjectNameKind::kSignature,
     "{optional<std::basic_string<char>>={_Optional_payload<std::basic_string<"
     "char>, false, false, false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}16@0:8"},
    {"cxx_oo_jsClassName", nullptr, OOEntityObjectNameKind::kSignature,
     "{optional<std::basic_string<char>>={_Optional_payload<std::basic_string<"
     "char>, false, false, false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}16@0:8"},
    {"cxx_oo_jsDescription", nullptr, OOEntityObjectNameKind::kSignature,
     "{optional<std::basic_string<char>>={_Optional_payload<std::basic_string<"
     "char>, false, false, false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}16@0:8"},
    {"cxx_oo_jsDescriptionWithClassName:", nullptr,
     OOEntityObjectNameKind::kSignature,
     "{optional<std::basic_string<char>>={_Optional_payload<std::basic_string<"
     "char>, false, false, false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}24@0:8r^{optional<"
     "std::basic_string<char>>={_Optional_payload<std::basic_string<char>, "
     "false, false, false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}16"},
    {"cxx_shortDescription", nullptr, OOEntityObjectNameKind::kSignature,
     "{optional<std::basic_string<char>>={_Optional_payload<std::basic_string<"
     "char>, false, false, false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}16@0:8"},
    {"cxx_shortDescriptionComponents", nullptr,
     OOEntityObjectNameKind::kSignature,
     "{optional<std::basic_string<char>>={_Optional_payload<std::basic_string<"
     "char>, false, false, false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}16@0:8"},
    {"dealloc", nullptr, OOEntityObjectNameKind::kLifetime, "v16@0:8"},
#ifdef OO_DEBUG_MONITOR_ENABLED
    {"descriptionForObjDump", nullptr, OOEntityObjectNameKind::kSignature,
     "{optional<std::basic_string<char>>={_Optional_payload<std::basic_string<"
     "char>, false, false, false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}16@0:8"},
#endif
#ifdef OO_DEBUG_MONITOR_ENABLED
    {"descriptionForObjDumpBasic", nullptr, OOEntityObjectNameKind::kSignature,
     "{optional<std::basic_string<char>>={_Optional_payload<std::basic_string<"
     "char>, false, false, false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}16@0:8"},
#endif
    {"distanceTravelled", nullptr, OOEntityObjectNameKind::kCalled, "f16@0:8"},
    {"doesNotRecognizeSelector:", nullptr, OOEntityObjectNameKind::kSignature,
     "v24@0:8:16"},
    {"drawImmediate:translucent:", nullptr, OOEntityObjectNameKind::kSignature,
     "v24@0:8B16B20"},
    {"drawRotationMatrix", nullptr, OOEntityObjectNameKind::kSignature,
     "{OOMatrix=[4[4f]]}16@0:8"},
    {"drawSubEntityImmediate:translucent:", nullptr,
     OOEntityObjectNameKind::kSignature, "v24@0:8B16B20"},
    {"drawTransformationMatrix", nullptr, OOEntityObjectNameKind::kSignature,
     "{OOMatrix=[4[4f]]}16@0:8"},
    {"dumpSelfState", nullptr, OOEntityObjectNameKind::kCalled, "v16@0:8"},
    {"dumpState", nullptr, OOEntityObjectNameKind::kCalled, "v16@0:8"},
    {"energy", nullptr, OOEntityObjectNameKind::kCalled, "f16@0:8"},
    {"findCollisionRadius", nullptr, OOEntityObjectNameKind::kCalled,
     "d16@0:8"},
    {"fogUniform", nullptr, OOEntityObjectNameKind::kSignature,
     "^{OOColor=^^?{atomic<unsigned int>=I}^{WeakControl}[4f]}16@0:8"},
    {"forwardingTargetForSelector:", nullptr,
     OOEntityObjectNameKind::kSignature, "@24@0:8:16"},
    {"frustumRadius", nullptr, OOEntityObjectNameKind::kCalled, "f16@0:8"},
    {"hash", nullptr, OOEntityObjectNameKind::kLifetime, "Q16@0:8"},
    {"illuminationColorAsVector", &AnswersPlanet,
     OOEntityObjectNameKind::kSignature, "{Vector=fff}16@0:8"},
    {"init", nullptr, OOEntityObjectNameKind::kLifetime, "@16@0:8"},
    {"initWithCxxEntity:", nullptr, OOEntityObjectNameKind::kSignature,
     "@24@0:8^{Entity=^^?{atomic<unsigned "
     "int>=I}^{WeakControl}^^?"
     "Sb288I1b289I1b290I1b291I1b292I1b293I1b294I1b295I1b296I1b297I2b299I1b300I1"
     "b301I1b302I1iffff{HPVector=ddd}{Vector=fff}{Quaternion=ffff}{Ref<OOColor>"
     "=^{OOColor}}i^{Entity}^{Entity}^{Entity}^{Entity}^{Entity}^{Entity}^{"
     "Entity}S^{Entity}{Ref<CollisionRegion>=^{CollisionRegion}}{HPVector=ddd}{"
     "Quaternion=ffff}f{OOMatrix=[4[4f]]}{Vector=fff}ff{?={Vector=fff}{Vector="
     "fff}}f{vector<oo::EntityHold, "
     "std::allocator<oo::EntityHold>>={_Vector_impl=^{EntityHold}^{EntityHold}^"
     "{EntityHold}}}d^{ObjectRep}QQ{WeakRef<Entity>=^{WeakControl}^{Entity}}i}"
     "16"},
    {"isBeacon", &AnswersBeacon, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"isCascadeWeapon", nullptr, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"isDock", nullptr, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"isEffect", nullptr, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"isEqual:", nullptr, OOEntityObjectNameKind::kSignature, "c24@0:8@16"},
    {"isImmuneToBreakPatternHide", nullptr, OOEntityObjectNameKind::kCalled,
     "c16@0:8"},
    {"isInSpace", nullptr, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"isJammingScanning", &AnswersBeacon, OOEntityObjectNameKind::kCalled,
     "c16@0:8"},
    {"isKindOfClass:", nullptr, OOEntityObjectNameKind::kSignature,
     "c24@0:8#16"},
    {"isMemberOfClass:", nullptr, OOEntityObjectNameKind::kSignature,
     "c24@0:8#16"},
    {"isPlanet", nullptr, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"isPlayer", nullptr, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"isProxy", nullptr, OOEntityObjectNameKind::kLifetime, "c16@0:8"},
    {"isShip", nullptr, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"isShipWithSubEntityShip:", nullptr, OOEntityObjectNameKind::kSignature,
     "c24@0:8@16"},
    {"isSky", nullptr, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"isStation", nullptr, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"isStellarObject", nullptr, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"isSubEntity", nullptr, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"isSun", nullptr, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"isSunlit", nullptr, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"isVisible", nullptr, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"isVisualEffect", nullptr, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"isWaypoint", nullptr, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"isWormhole", nullptr, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"lastDrawCounter", nullptr, OOEntityObjectNameKind::kCalled, "Q16@0:8"},
    {"mass", nullptr, OOEntityObjectNameKind::kCalled, "f16@0:8"},
    {"maxEnergy", nullptr, OOEntityObjectNameKind::kCalled, "f16@0:8"},
    {"methodForSelector:", nullptr, OOEntityObjectNameKind::kSignature,
     "^?24@0:8:16"},
    {"moveForward:", nullptr, OOEntityObjectNameKind::kSignature, "v24@0:8d16"},
    {"mutableCopy", nullptr, OOEntityObjectNameKind::kLifetime, "@16@0:8"},
    {"nextBeacon", &AnswersBeacon, OOEntityObjectNameKind::kCalled, "@16@0:8"},
    {"normalOrientation", nullptr, OOEntityObjectNameKind::kSignature,
     "{Quaternion=ffff}16@0:8"},
    {"oo_clearJSSelf:", nullptr, OOEntityObjectNameKind::kSignature,
     "v24@0:8^{ObjectRep=}16"},
    {"oo_jsValueInContext:", nullptr, OOEntityObjectNameKind::kSignature,
     "{Value=Q}24@0:8^{ContextRep=}16"},
    {"orientation", nullptr, OOEntityObjectNameKind::kSignature,
     "{Quaternion=ffff}16@0:8"},
    {"orientationChanged", nullptr, OOEntityObjectNameKind::kCalled, "v16@0:8"},
    {"owner", nullptr, OOEntityObjectNameKind::kCalled, "@16@0:8"},
    {"parentEntity", nullptr, OOEntityObjectNameKind::kCalled, "@16@0:8"},
    {"performSelector:", nullptr, OOEntityObjectNameKind::kSignature,
     "@24@0:8:16"},
    {"performSelector:withObject:", nullptr, OOEntityObjectNameKind::kSignature,
     "@32@0:8:16@24"},
    {"performSelector:withObject:withObject:", nullptr,
     OOEntityObjectNameKind::kSignature, "@40@0:8:16@24@32"},
    {"position", nullptr, OOEntityObjectNameKind::kSignature,
     "{HPVector=ddd}16@0:8"},
    {"prevBeacon", &AnswersBeacon, OOEntityObjectNameKind::kCalled, "@16@0:8"},
    {"relativePosition", nullptr, OOEntityObjectNameKind::kSignature,
     "{Vector=fff}16@0:8"},
    {"release", nullptr, OOEntityObjectNameKind::kLifetime, "Vv16@0:8"},
    {"removeFromLinkedLists", nullptr, OOEntityObjectNameKind::kCalled,
     "v16@0:8"},
    {"respondsToSelector:", nullptr, OOEntityObjectNameKind::kSignature,
     "c24@0:8:16"},
    {"retain", nullptr, OOEntityObjectNameKind::kLifetime, "@16@0:8"},
    {"retainCount", nullptr, OOEntityObjectNameKind::kLifetime, "Q16@0:8"},
    {"rootShipEntity", nullptr, OOEntityObjectNameKind::kCalled, "@16@0:8"},
    {"rotationMatrix", nullptr, OOEntityObjectNameKind::kSignature,
     "{OOMatrix=[4[4f]]}16@0:8"},
    {"scanClass", nullptr, OOEntityObjectNameKind::kCalled, "i16@0:8"},
    {"self", nullptr, OOEntityObjectNameKind::kLifetime, "@16@0:8"},
    {"sessionID", nullptr, OOEntityObjectNameKind::kCalled, "Q16@0:8"},
    {"setAtmosphereFogging:", nullptr, OOEntityObjectNameKind::kSignature,
     "v24@0:8^{OOColor=^^?{atomic<unsigned int>=I}^{WeakControl}[4f]}16"},
    {"setBeaconCode:", &AnswersBeacon, OOEntityObjectNameKind::kSignature,
     "v24@0:8r^{optional<std::basic_string<char>>={_Optional_payload<std::"
     "basic_string<char>, false, false, "
     "false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}16"},
    {"setBeaconLabel:", &AnswersBeacon, OOEntityObjectNameKind::kSignature,
     "v24@0:8r^{optional<std::basic_string<char>>={_Optional_payload<std::"
     "basic_string<char>, false, false, "
     "false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}16"},
    {"setCollisionRadius:", nullptr, OOEntityObjectNameKind::kSignature,
     "v20@0:8f16"},
    {"setDistanceTravelled:", nullptr, OOEntityObjectNameKind::kSignature,
     "v20@0:8f16"},
    {"setEnergy:", nullptr, OOEntityObjectNameKind::kSignature, "v20@0:8f16"},
    {"setLastDrawCounter:", nullptr, OOEntityObjectNameKind::kSignature,
     "v24@0:8Q16"},
    {"setMaxEnergy:", nullptr, OOEntityObjectNameKind::kSignature,
     "v20@0:8f16"},
    {"setNextBeacon:", &AnswersBeacon, OOEntityObjectNameKind::kSignature,
     "v24@0:8@16"},
    {"setNormalOrientation:", nullptr, OOEntityObjectNameKind::kSignature,
     "v32@0:8{Quaternion=ffff}16"},
    {"setOrientation:", nullptr, OOEntityObjectNameKind::kSignature,
     "v32@0:8{Quaternion=ffff}16"},
    {"setOwner:", nullptr, OOEntityObjectNameKind::kSignature, "v24@0:8@16"},
    {"setPosition:", nullptr, OOEntityObjectNameKind::kSignature,
     "v40@0:8{HPVector=ddd}16"},
    {"setPositionX:y:z:", nullptr, OOEntityObjectNameKind::kSignature,
     "v40@0:8d16d24d32"},
    {"setPrevBeacon:", &AnswersBeacon, OOEntityObjectNameKind::kSignature,
     "v24@0:8@16"},
    {"setScanClass:", nullptr, OOEntityObjectNameKind::kSignature,
     "v20@0:8i16"},
    {"setStatus:", nullptr, OOEntityObjectNameKind::kSignature, "v20@0:8i16"},
    {"setThrowSparks:", nullptr, OOEntityObjectNameKind::kSignature,
     "v20@0:8c16"},
    {"setUniversalID:", nullptr, OOEntityObjectNameKind::kSignature,
     "v20@0:8S16"},
    {"setVelocity:", nullptr, OOEntityObjectNameKind::kSignature,
     "v28@0:8{Vector=fff}16"},
    {"spawnTime", nullptr, OOEntityObjectNameKind::kCalled, "f16@0:8"},
    {"speed", nullptr, OOEntityObjectNameKind::kCalled, "d16@0:8"},
    {"status", nullptr, OOEntityObjectNameKind::kCalled, "i16@0:8"},
    {"subEntityReallyDied:", nullptr, OOEntityObjectNameKind::kSignature,
     "v24@0:8^{ShipEntity=^^?{atomic<unsigned "
     "int>=I}^{WeakControl}^^?"
     "Sb288I1b289I1b290I1b291I1b292I1b293I1b294I1b295I1b296I1b297I2b299I1b300I1"
     "b301I1b302I1iffff{HPVector=ddd}{Vector=fff}{Quaternion=ffff}{Ref<OOColor>"
     "=^{OOColor}}i^{Entity}^{Entity}^{Entity}^{Entity}^{Entity}^{Entity}^{"
     "Entity}S^{Entity}{Ref<CollisionRegion>=^{CollisionRegion}}{HPVector=ddd}{"
     "Quaternion=ffff}f{OOMatrix=[4[4f]]}{Vector=fff}ff{?={Vector=fff}{Vector="
     "fff}}f{vector<oo::EntityHold, "
     "std::allocator<oo::EntityHold>>={_Vector_impl=^{EntityHold}^{EntityHold}^"
     "{EntityHold}}}d^{ObjectRep}QQ{WeakRef<Entity>=^{WeakControl}^{Entity}}i{"
     "Ref<OODrawable>=^{OODrawable}}^^?d{Vector=fff}{Vector=fff}{Vector=fff}{"
     "HPVector=ddd}fffffi{?={Vector=fff}{Vector=fff}}{PList={variant<std::"
     "monostate, bool, oo::PList::Integer, double, std::basic_string<char>, "
     "oo::Data, oo::PList::Date, std::vector<oo::PList>, "
     "std::map<std::basic_string<char>, oo::PList, std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>=(_Variadic_union<false, std::monostate, bool, "
     "oo::PList::Integer, double, std::basic_string<char>, oo::Data, "
     "oo::PList::Date, std::vector<oo::PList>, "
     "std::map<std::basic_string<char>, oo::PList, std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::monostate, "
     "true>={monostate=}}(_Variadic_union<false, bool, oo::PList::Integer, "
     "double, std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, std::shared_ptr<oo::PListForeign>>={_Uninitialized<bool, "
     "true>=B}(_Variadic_union<false, oo::PList::Integer, double, "
     "std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<oo::PList::Integer, "
     "true>={Integer=qB}}(_Variadic_union<false, double, "
     "std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, std::shared_ptr<oo::PListForeign>>={_Uninitialized<double, "
     "true>=d}(_Variadic_union<false, std::basic_string<char>, oo::Data, "
     "oo::PList::Date, std::vector<oo::PList>, "
     "std::map<std::basic_string<char>, oo::PList, std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::basic_string<char>, "
     "true>={basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)}}(_Variadic_union<"
     "false, oo::Data, oo::PList::Date, std::vector<oo::PList>, "
     "std::map<std::basic_string<char>, oo::PList, std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<oo::Data, "
     "true>={Data={vector<unsigned char, std::allocator<unsigned "
     "char>>={_Vector_impl=***}}}}(_Variadic_union<false, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<oo::PList::Date, "
     "true>={Date=d}}(_Variadic_union<false, std::vector<oo::PList>, "
     "std::map<std::basic_string<char>, oo::PList, std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::vector<oo::PList>, "
     "true>={vector<oo::PList, "
     "std::allocator<oo::PList>>={_Vector_impl=^{PList}^{PList}^{PList}}}}(_"
     "Variadic_union<false, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::map<std::basic_string<"
     "char>, oo::PList, std::less<void>>, true>={map<std::basic_string<char>, "
     "oo::PList, std::less<void>, std::allocator<std::pair<const "
     "std::basic_string<char>, oo::PList>>>={_Rb_tree<std::basic_string<char>, "
     "std::pair<const std::basic_string<char>, oo::PList>, "
     "std::_Select1st<std::pair<const std::basic_string<char>, oo::PList>>, "
     "std::less<void>, std::allocator<std::pair<const std::basic_string<char>, "
     "oo::PList>>>={_Rb_tree_impl<std::less<void>, "
     "true>={less<void>=}{_Rb_tree_node_base=i^{_Rb_tree_node_base}^{_Rb_tree_"
     "node_base}^{_Rb_tree_node_base}}Q}}}}(_Variadic_union<false, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::shared_ptr<oo::PListForeign>, "
     "true>={Ref<oo::PListForeign>=^{PListForeign}}}(_Variadic_union<true>=))))"
     ")))))))C}B}{Quaternion=ffff}{Ref<OOScript>=^{OOScript}}{Ref<OOScript>=^{"
     "OOScript}}d{PList={variant<std::monostate, bool, oo::PList::Integer, "
     "double, std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, std::shared_ptr<oo::PListForeign>>=(_Variadic_union<false, "
     "std::monostate, bool, oo::PList::Integer, double, "
     "std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::monostate, "
     "true>={monostate=}}(_Variadic_union<false, bool, oo::PList::Integer, "
     "double, std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, std::shared_ptr<oo::PListForeign>>={_Uninitialized<bool, "
     "true>=B}(_Variadic_union<false, oo::PList::Integer, double, "
     "std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<oo::PList::Integer, "
     "true>={Integer=qB}}(_Variadic_union<false, double, "
     "std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, std::shared_ptr<oo::PListForeign>>={_Uninitialized<double, "
     "true>=d}(_Variadic_union<false, std::basic_string<char>, oo::Data, "
     "oo::PList::Date, std::vector<oo::PList>, "
     "std::map<std::basic_string<char>, oo::PList, std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::basic_string<char>, "
     "true>={basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)}}(_Variadic_union<"
     "false, oo::Data, oo::PList::Date, std::vector<oo::PList>, "
     "std::map<std::basic_string<char>, oo::PList, std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<oo::Data, "
     "true>={Data={vector<unsigned char, std::allocator<unsigned "
     "char>>={_Vector_impl=***}}}}(_Variadic_union<false, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<oo::PList::Date, "
     "true>={Date=d}}(_Variadic_union<false, std::vector<oo::PList>, "
     "std::map<std::basic_string<char>, oo::PList, std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::vector<oo::PList>, "
     "true>={vector<oo::PList, "
     "std::allocator<oo::PList>>={_Vector_impl=^{PList}^{PList}^{PList}}}}(_"
     "Variadic_union<false, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::map<std::basic_string<"
     "char>, oo::PList, std::less<void>>, true>={map<std::basic_string<char>, "
     "oo::PList, std::less<void>, std::allocator<std::pair<const "
     "std::basic_string<char>, oo::PList>>>={_Rb_tree<std::basic_string<char>, "
     "std::pair<const std::basic_string<char>, oo::PList>, "
     "std::_Select1st<std::pair<const std::basic_string<char>, oo::PList>>, "
     "std::less<void>, std::allocator<std::pair<const std::basic_string<char>, "
     "oo::PList>>>={_Rb_tree_impl<std::less<void>, "
     "true>={less<void>=}{_Rb_tree_node_base=i^{_Rb_tree_node_base}^{_Rb_tree_"
     "node_base}^{_Rb_tree_node_base}}Q}}}}(_Variadic_union<false, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::shared_ptr<oo::PListForeign>, "
     "true>={Ref<oo::PListForeign>=^{PListForeign}}}(_Variadic_union<true>=))))"
     ")))))))C}B}{Ref<OOColor>=^{OOColor}}{Ref<OOColor>=^{OOColor}}{Ref<"
     "OOColor>=^{OOColor}}{Ref<OOColor>=^{OOColor}}{Ref<OOColor>=^{OOColor}}{"
     "Ref<OOColor>=^{OOColor}}{Ref<OOColor>=^{OOColor}}"
     "ffffffffb6784I1b6785I1b6786I1b6787I1b6788I1b6789I1b6790I1b6791I1b6792I1b6"
     "793I1b6794I1b6795I1b6796I1b6797I1b6798I1b6799I1b6800I1b6801I1b6802I1b6803"
     "I1b6804I1b6805I1b6806I1b6807I1b6808I1b6809I1b6810I1ffSfffIIIIiiQfC^{"
     "OOEquipmentType}^{OOEquipmentType}^{OOEquipmentType}^{OOEquipmentType}"
     "fffiffffffffII{optional<std::basic_string<char>>={_Optional_payload<std::"
     "basic_string<char>, false, false, "
     "false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}dd{Ref<AI>=^{AI}}{"
     "optional<std::basic_string<char>>={_Optional_payload<std::basic_string<"
     "char>, false, false, false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}{optional<std::"
     "basic_string<char>>={_Optional_payload<std::basic_string<char>, false, "
     "false, false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}{optional<std::"
     "basic_string<char>>={_Optional_payload<std::basic_string<char>, false, "
     "false, false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}{optional<std::"
     "basic_string<char>>={_Optional_payload<std::basic_string<char>, false, "
     "false, false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}{optional<std::"
     "basic_string<char>>={_Optional_payload<std::basic_string<char>, false, "
     "false, false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}{Ref<OORoleSet>=^{"
     "OORoleSet}}{optional<std::basic_string<char>>={_Optional_payload<std::"
     "basic_string<char>, false, false, "
     "false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}{PList={variant<"
     "std::monostate, bool, oo::PList::Integer, double, "
     "std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, std::shared_ptr<oo::PListForeign>>=(_Variadic_union<false, "
     "std::monostate, bool, oo::PList::Integer, double, "
     "std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::monostate, "
     "true>={monostate=}}(_Variadic_union<false, bool, oo::PList::Integer, "
     "double, std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, std::shared_ptr<oo::PListForeign>>={_Uninitialized<bool, "
     "true>=B}(_Variadic_union<false, oo::PList::Integer, double, "
     "std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<oo::PList::Integer, "
     "true>={Integer=qB}}(_Variadic_union<false, double, "
     "std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, std::shared_ptr<oo::PListForeign>>={_Uninitialized<double, "
     "true>=d}(_Variadic_union<false, std::basic_string<char>, oo::Data, "
     "oo::PList::Date, std::vector<oo::PList>, "
     "std::map<std::basic_string<char>, oo::PList, std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::basic_string<char>, "
     "true>={basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)}}(_Variadic_union<"
     "false, oo::Data, oo::PList::Date, std::vector<oo::PList>, "
     "std::map<std::basic_string<char>, oo::PList, std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<oo::Data, "
     "true>={Data={vector<unsigned char, std::allocator<unsigned "
     "char>>={_Vector_impl=***}}}}(_Variadic_union<false, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<oo::PList::Date, "
     "true>={Date=d}}(_Variadic_union<false, std::vector<oo::PList>, "
     "std::map<std::basic_string<char>, oo::PList, std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::vector<oo::PList>, "
     "true>={vector<oo::PList, "
     "std::allocator<oo::PList>>={_Vector_impl=^{PList}^{PList}^{PList}}}}(_"
     "Variadic_union<false, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::map<std::basic_string<"
     "char>, oo::PList, std::less<void>>, true>={map<std::basic_string<char>, "
     "oo::PList, std::less<void>, std::allocator<std::pair<const "
     "std::basic_string<char>, oo::PList>>>={_Rb_tree<std::basic_string<char>, "
     "std::pair<const std::basic_string<char>, oo::PList>, "
     "std::_Select1st<std::pair<const std::basic_string<char>, oo::PList>>, "
     "std::less<void>, std::allocator<std::pair<const std::basic_string<char>, "
     "oo::PList>>>={_Rb_tree_impl<std::less<void>, "
     "true>={less<void>=}{_Rb_tree_node_base=i^{_Rb_tree_node_base}^{_Rb_tree_"
     "node_base}^{_Rb_tree_node_base}}Q}}}}(_Variadic_union<false, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::shared_ptr<oo::PListForeign>, "
     "true>={Ref<oo::PListForeign>=^{PListForeign}}}(_Variadic_union<true>=))))"
     ")))))))C}B}{Vector=fff}{HPVector=ddd}{Vector=fff}QQddSffi{PList={variant<"
     "std::monostate, bool, oo::PList::Integer, double, "
     "std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, std::shared_ptr<oo::PListForeign>>=(_Variadic_union<false, "
     "std::monostate, bool, oo::PList::Integer, double, "
     "std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::monostate, "
     "true>={monostate=}}(_Variadic_union<false, bool, oo::PList::Integer, "
     "double, std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, std::shared_ptr<oo::PListForeign>>={_Uninitialized<bool, "
     "true>=B}(_Variadic_union<false, oo::PList::Integer, double, "
     "std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<oo::PList::Integer, "
     "true>={Integer=qB}}(_Variadic_union<false, double, "
     "std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, std::shared_ptr<oo::PListForeign>>={_Uninitialized<double, "
     "true>=d}(_Variadic_union<false, std::basic_string<char>, oo::Data, "
     "oo::PList::Date, std::vector<oo::PList>, "
     "std::map<std::basic_string<char>, oo::PList, std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::basic_string<char>, "
     "true>={basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)}}(_Variadic_union<"
     "false, oo::Data, oo::PList::Date, std::vector<oo::PList>, "
     "std::map<std::basic_string<char>, oo::PList, std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<oo::Data, "
     "true>={Data={vector<unsigned char, std::allocator<unsigned "
     "char>>={_Vector_impl=***}}}}(_Variadic_union<false, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<oo::PList::Date, "
     "true>={Date=d}}(_Variadic_union<false, std::vector<oo::PList>, "
     "std::map<std::basic_string<char>, oo::PList, std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::vector<oo::PList>, "
     "true>={vector<oo::PList, "
     "std::allocator<oo::PList>>={_Vector_impl=^{PList}^{PList}^{PList}}}}(_"
     "Variadic_union<false, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::map<std::basic_string<"
     "char>, oo::PList, std::less<void>>, true>={map<std::basic_string<char>, "
     "oo::PList, std::less<void>, std::allocator<std::pair<const "
     "std::basic_string<char>, oo::PList>>>={_Rb_tree<std::basic_string<char>, "
     "std::pair<const std::basic_string<char>, oo::PList>, "
     "std::_Select1st<std::pair<const std::basic_string<char>, oo::PList>>, "
     "std::less<void>, std::allocator<std::pair<const std::basic_string<char>, "
     "oo::PList>>>={_Rb_tree_impl<std::less<void>, "
     "true>={less<void>=}{_Rb_tree_node_base=i^{_Rb_tree_node_base}^{_Rb_tree_"
     "node_base}^{_Rb_tree_node_base}}Q}}}}(_Variadic_union<false, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::shared_ptr<oo::PListForeign>, "
     "true>={Ref<oo::PListForeign>=^{PListForeign}}}(_Variadic_union<true>=))))"
     ")))))))C}B}fidd{vector<oo::EntityHold, "
     "std::allocator<oo::EntityHold>>={_Vector_impl=^{EntityHold}^{EntityHold}^"
     "{EntityHold}}}{optional<std::basic_string<char>>={_Optional_payload<std::"
     "basic_string<char>, false, false, "
     "false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}Ifffffffiissdd{"
     "Vector=fff}fc{vector<Vector, "
     "std::allocator<Vector>>={_Vector_impl=^{Vector}^{Vector}^{Vector}}}{"
     "vector<Vector, "
     "std::allocator<Vector>>={_Vector_impl=^{Vector}^{Vector}^{Vector}}}{"
     "vector<Vector, "
     "std::allocator<Vector>>={_Vector_impl=^{Vector}^{Vector}^{Vector}}}{"
     "vector<Vector, "
     "std::allocator<Vector>>={_Vector_impl=^{Vector}^{Vector}^{Vector}}}{"
     "optional<std::vector<std::shared_ptr<OOCharacter>>>={_Optional_payload<std::"
     "vector<std::shared_ptr<OOCharacter>>, false, false, "
     "false>=(_Storage<std::vector<std::shared_ptr<OOCharacter>>, "
     "false>={_Empty_byte=}{vector<std::shared_ptr<OOCharacter>, "
     "std::allocator<std::shared_ptr<OOCharacter>>>={_Vector_impl=^{Ref<OOCharacter>}^{"
     "Ref<OOCharacter>}^{Ref<OOCharacter>}}})B}}{map<std::basic_string<char>, "
     "std::basic_string<char>, std::less<void>, std::allocator<std::pair<const "
     "std::basic_string<char>, "
     "std::basic_string<char>>>>={_Rb_tree<std::basic_string<char>, "
     "std::pair<const std::basic_string<char>, std::basic_string<char>>, "
     "std::_Select1st<std::pair<const std::basic_string<char>, "
     "std::basic_string<char>>>, std::less<void>, "
     "std::allocator<std::pair<const std::basic_string<char>, "
     "std::basic_string<char>>>>={_Rb_tree_impl<std::less<void>, "
     "true>={less<void>=}{_Rb_tree_node_base=i^{_Rb_tree_node_base}^{_Rb_tree_"
     "node_base}^{_Rb_tree_node_base}}Q}}}{optional<std::basic_string<char>>={_"
     "Optional_payload<std::basic_string<char>, false, false, "
     "false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}{Vector=fff}f[33^{"
     "ShipEntity}][33f]I[32{HPVector=ddd}]II{Ref<Octree>=^{Octree}}iS{PList={"
     "variant<std::monostate, bool, oo::PList::Integer, double, "
     "std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, std::shared_ptr<oo::PListForeign>>=(_Variadic_union<false, "
     "std::monostate, bool, oo::PList::Integer, double, "
     "std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::monostate, "
     "true>={monostate=}}(_Variadic_union<false, bool, oo::PList::Integer, "
     "double, std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, std::shared_ptr<oo::PListForeign>>={_Uninitialized<bool, "
     "true>=B}(_Variadic_union<false, oo::PList::Integer, double, "
     "std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<oo::PList::Integer, "
     "true>={Integer=qB}}(_Variadic_union<false, double, "
     "std::basic_string<char>, oo::Data, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, std::shared_ptr<oo::PListForeign>>={_Uninitialized<double, "
     "true>=d}(_Variadic_union<false, std::basic_string<char>, oo::Data, "
     "oo::PList::Date, std::vector<oo::PList>, "
     "std::map<std::basic_string<char>, oo::PList, std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::basic_string<char>, "
     "true>={basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)}}(_Variadic_union<"
     "false, oo::Data, oo::PList::Date, std::vector<oo::PList>, "
     "std::map<std::basic_string<char>, oo::PList, std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<oo::Data, "
     "true>={Data={vector<unsigned char, std::allocator<unsigned "
     "char>>={_Vector_impl=***}}}}(_Variadic_union<false, oo::PList::Date, "
     "std::vector<oo::PList>, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<oo::PList::Date, "
     "true>={Date=d}}(_Variadic_union<false, std::vector<oo::PList>, "
     "std::map<std::basic_string<char>, oo::PList, std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::vector<oo::PList>, "
     "true>={vector<oo::PList, "
     "std::allocator<oo::PList>>={_Vector_impl=^{PList}^{PList}^{PList}}}}(_"
     "Variadic_union<false, std::map<std::basic_string<char>, oo::PList, "
     "std::less<void>>, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::map<std::basic_string<"
     "char>, oo::PList, std::less<void>>, true>={map<std::basic_string<char>, "
     "oo::PList, std::less<void>, std::allocator<std::pair<const "
     "std::basic_string<char>, oo::PList>>>={_Rb_tree<std::basic_string<char>, "
     "std::pair<const std::basic_string<char>, oo::PList>, "
     "std::_Select1st<std::pair<const std::basic_string<char>, oo::PList>>, "
     "std::less<void>, std::allocator<std::pair<const std::basic_string<char>, "
     "oo::PList>>>={_Rb_tree_impl<std::less<void>, "
     "true>={less<void>=}{_Rb_tree_node_base=i^{_Rb_tree_node_base}^{_Rb_tree_"
     "node_base}^{_Rb_tree_node_base}}Q}}}}(_Variadic_union<false, "
     "std::shared_ptr<oo::PListForeign>>={_Uninitialized<std::shared_ptr<oo::PListForeign>, "
     "true>={Ref<oo::PListForeign>=^{PListForeign}}}(_Variadic_union<true>=))))"
     ")))))))C}B}{vector<oo::EntityHold, "
     "std::allocator<oo::EntityHold>>={_Vector_impl=^{EntityHold}^{EntityHold}^"
     "{EntityHold}}}[32^{OOEquipmentType}]{WeakRef<Entity>=^{WeakControl}^{"
     "Entity}}{WeakRef<Entity>=^{WeakControl}^{Entity}}{WeakRef<Entity>=^{"
     "WeakControl}^{Entity}}{WeakRef<Entity>=^{WeakControl}^{Entity}}{WeakRef<"
     "Entity>=^{WeakControl}^{Entity}}{WeakRef<Entity>=^{WeakControl}^{Entity}}"
     "{WeakRef<Entity>=^{WeakControl}^{Entity}}{WeakRef<Entity>=^{WeakControl}^"
     "{Entity}}f[4{HPVector=ddd}][4d][3{HPVector=ddd}]{WeakRef<Entity>=^{"
     "WeakControl}^{Entity}}{optional<std::basic_string<char>>={_Optional_"
     "payload<std::basic_string<char>, false, false, "
     "false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}{vector<std::basic_"
     "string<char>, "
     "std::allocator<std::basic_string<char>>>={_Vector_impl=^{basic_string<"
     "char, std::char_traits<char>, std::allocator<char>>}^{basic_string<char, "
     "std::char_traits<char>, std::allocator<char>>}^{basic_string<char, "
     "std::char_traits<char>, "
     "std::allocator<char>>}}}f{WeakRef<Entity>=^{WeakControl}^{Entity}}{Ref<"
     "OOShipGroup>=^{OOShipGroup}}{Ref<OOShipGroup>=^{OOShipGroup}}CC[16{"
     "Vector=fff}]c{WeakSet<Entity>={vector<std::weak_ptr<Entity>, "
     "std::allocator<std::weak_ptr<Entity>>>={_Vector_impl=^{WeakRef<Entity>}^{"
     "WeakRef<Entity>}^{WeakRef<Entity>}}}{unordered_set<const "
     "oo::detail::WeakControl *, std::hash<const oo::detail::WeakControl *>, "
     "std::equal_to<const oo::detail::WeakControl *>, std::allocator<const "
     "oo::detail::WeakControl *>>={_Hashtable<const oo::detail::WeakControl *, "
     "const oo::detail::WeakControl *, std::allocator<const "
     "oo::detail::WeakControl *>, std::__detail::_Identity, "
     "std::equal_to<const oo::detail::WeakControl *>, std::hash<const "
     "oo::detail::WeakControl *>, std::__detail::_Mod_range_hashing, "
     "std::__detail::_Default_ranged_hash, "
     "std::__detail::_Prime_rehash_policy, "
     "std::__detail::_Hashtable_traits<false, true, "
     "true>>=^^{_Hash_node_base}Q{_Hash_node_base=^{_Hash_node_base}}Q{_Prime_"
     "rehash_policy=fQ}^{_Hash_node_base}}}}{WeakSet<Entity>={vector<oo::"
     "WeakRef<Entity>, "
     "std::allocator<std::weak_ptr<Entity>>>={_Vector_impl=^{WeakRef<Entity>}^{"
     "WeakRef<Entity>}^{WeakRef<Entity>}}}{unordered_set<const "
     "oo::detail::WeakControl *, std::hash<const oo::detail::WeakControl *>, "
     "std::equal_to<const oo::detail::WeakControl *>, std::allocator<const "
     "oo::detail::WeakControl *>>={_Hashtable<const oo::detail::WeakControl *, "
     "const oo::detail::WeakControl *, std::allocator<const "
     "oo::detail::WeakControl *>, std::__detail::_Identity, "
     "std::equal_to<const oo::detail::WeakControl *>, std::hash<const "
     "oo::detail::WeakControl *>, std::__detail::_Mod_range_hashing, "
     "std::__detail::_Default_ranged_hash, "
     "std::__detail::_Prime_rehash_policy, "
     "std::__detail::_Hashtable_traits<false, true, "
     "true>>=^^{_Hash_node_base}Q{_Hash_node_base=^{_Hash_node_base}}Q{_Prime_"
     "rehash_policy=fQ}^{_Hash_node_base}}}}f{WeakRef<Entity>=^{WeakControl}^{"
     "Entity}}{optional<std::basic_string<char>>={_Optional_payload<std::basic_"
     "string<char>, false, false, false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}{optional<std::"
     "basic_string<char>>={_Optional_payload<std::basic_string<char>, false, "
     "false, false>=(_Storage<std::basic_string<char>, "
     "false>={_Empty_byte=}{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)})B}}{WeakRef<Entity>=^{"
     "WeakControl}^{Entity}}{WeakRef<Entity>=^{WeakControl}^{Entity}}{Ref<"
     "OOHUDBeaconIcon>=^{OOHUDBeaconIcon}}dcfd{Quaternion=ffff}}16"},
    {"superShaderBindingTarget", nullptr, OOEntityObjectNameKind::kCalled,
     "@16@0:8"},
    {"superclass", nullptr, OOEntityObjectNameKind::kSignature, "#16@0:8"},
    {"takeEnergyDamage:from:becauseOf:weaponIdentifier:", nullptr,
     OOEntityObjectNameKind::kSignature,
     "v48@0:8d16@24@32r^{basic_string<char, std::char_traits<char>, "
     "std::allocator<char>>={_Alloc_hider=*}Q(?=[16c]Q)}40"},
    {"terminatorThresholdVector", &AnswersPlanet,
     OOEntityObjectNameKind::kSignature, "{Vector=fff}16@0:8"},
    {"throwSparks", nullptr, OOEntityObjectNameKind::kCalled, "v16@0:8"},
    {"throwingSparks", nullptr, OOEntityObjectNameKind::kCalled, "c16@0:8"},
    {"timeElapsedSinceSpawn", nullptr, OOEntityObjectNameKind::kCalled,
     "f16@0:8"},
    {"transformationMatrix", nullptr, OOEntityObjectNameKind::kSignature,
     "{OOMatrix=[4[4f]]}16@0:8"},
    {"universalID", nullptr, OOEntityObjectNameKind::kCalled, "S16@0:8"},
    {"universalTime", nullptr, OOEntityObjectNameKind::kCalled, "f16@0:8"},
    {"update:", nullptr, OOEntityObjectNameKind::kSignature, "v24@0:8d16"},
    {"updateCameraRelativePosition", nullptr, OOEntityObjectNameKind::kCalled,
     "v16@0:8"},
    {"updateLinkedLists", nullptr, OOEntityObjectNameKind::kCalled, "v16@0:8"},
    {"validForAddToUniverse", nullptr, OOEntityObjectNameKind::kCalled,
     "c16@0:8"},
    {"vectorTo:", nullptr, OOEntityObjectNameKind::kSignature,
     "{Vector=fff}24@0:8@16"},
    {"velocity", nullptr, OOEntityObjectNameKind::kSignature,
     "{Vector=fff}16@0:8"},
    {"warnAboutHostiles", nullptr, OOEntityObjectNameKind::kCalled, "v16@0:8"},
    {"wasAddedToUniverse", nullptr, OOEntityObjectNameKind::kCalled, "v16@0:8"},
    {"wasRemovedFromUniverse", nullptr, OOEntityObjectNameKind::kCalled,
     "v16@0:8"},
    {"weakRefDied:", nullptr, OOEntityObjectNameKind::kSignature, "v24@0:8@16"},
    {"weakRefUnderlyingObject", nullptr, OOEntityObjectNameKind::kLifetime,
     "@16@0:8"},
    {"weakRetain", nullptr, OOEntityObjectNameKind::kLifetime, "@16@0:8"},
    {"weakSelf", nullptr, OOEntityObjectNameKind::kLifetime, "@16@0:8"},
    {"zeroDistance", nullptr, OOEntityObjectNameKind::kCalled, "d16@0:8"},
    {"zone", nullptr, OOEntityObjectNameKind::kSignature, "^{OOZone=}16@0:8"},
};
