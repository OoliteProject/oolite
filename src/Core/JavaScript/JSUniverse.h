//===========================================================================
// Universe proxy
//===========================================================================

JSClass Universe_class = {
	"Universe", JSCLASS_HAS_PRIVATE,
	JS_PropertyStub,JS_PropertyStub,JS_PropertyStub,JS_PropertyStub,
	JS_EnumerateStub,JS_ResolveStub,JS_ConvertStub,JS_FinalizeStub
};

/*
JSBool UniverseGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp);

enum Universe_propertyIds {
	UNI_PLAYER_ENTITY
};

JSPropertySpec Universe_props[] = {
	{ "PlayerEntity", UNI_PLAYER_ENTITY, JSPROP_ENUMERATE },
	{ 0 }
};
*/

JSBool UniverseCheckForShips(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool UniverseAddShips(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool UniverseAddSystemShips(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool UniverseAddShipsAt(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool UniverseAddShipsAtPrecisely(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool UniverseAddShipsWithinRadius(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool UniverseSpawn(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
JSBool UniverseSpawnShip(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);

JSFunctionSpec Universe_funcs[] = {
	{ "CheckForShips", UniverseCheckForShips, 1, 0 },
	{ "AddShips", UniverseAddShips, 2, 0 },
	{ "AddSystemShips", UniverseAddSystemShips, 3, 0 },
	{ "AddShipsAt", UniverseAddShipsAt, 6, 0 },
	{ "AddShipsAtPrecisely", UniverseAddShipsAtPrecisely, 6, 0 },
	{ "AddShipsWithinRadius", UniverseAddShipsWithinRadius, 7, 0 },
	{ "Spawn", UniverseSpawn, 2, 0 },
	{ "SpawnShip", UniverseSpawnShip, 1, 0 },
	{ 0 }
};

JSBool UniverseCheckForShips(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	if (argc == 1) {
	//	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
		NSString *role = JSValToNSString(cx, argv[0]);
		int num = [scriptedUniverse countShipsWithRole:role];
		*rval = INT_TO_JSVAL(num);
	}
	return JS_TRUE;
}

JSBool UniverseAddShips(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	if (argc == 2) {
	//	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
		NSString *role = JSValToNSString(cx, argv[0]);
		int num = JSVAL_TO_INT(argv[1]);

		while (num--)
			[scriptedUniverse witchspaceShipWithRole:role];
	}
	return JS_TRUE;
}

JSBool UniverseAddSystemShips(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	if (argc == 3) {
		jsdouble posn;
	//	PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
		NSString *role = JSValToNSString(cx, argv[0]);
		int num = JSVAL_TO_INT(argv[1]);
		JS_ValueToNumber(cx, argv[2], &posn);
		while (num--)
			[scriptedUniverse addShipWithRole:role nearRouteOneAt:posn];
	}
	return JS_TRUE;
}

JSBool UniverseAddShipsAt(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	if (argc == 6) {
		jsdouble x, y, z;
		PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
		NSString *role = JSValToNSString(cx, argv[0]);
		int num = JSVAL_TO_INT(argv[1]);
		NSString *coordScheme = JSValToNSString(cx, argv[2]);
		JS_ValueToNumber(cx, argv[3], &x);
		JS_ValueToNumber(cx, argv[4], &y);
		JS_ValueToNumber(cx, argv[5], &z);
		NSString *arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f", role, num, coordScheme, x, y, z];
		[playerEntity addShipsAt:arg];
	}
	return JS_TRUE;
}

JSBool UniverseAddShipsAtPrecisely(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	if (argc == 6) {
		jsdouble x, y, z;
		PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
		NSString *role = JSValToNSString(cx, argv[0]);
		int num = JSVAL_TO_INT(argv[1]);
		NSString *coordScheme = JSValToNSString(cx, argv[2]);
		JS_ValueToNumber(cx, argv[3], &x);
		JS_ValueToNumber(cx, argv[4], &y);
		JS_ValueToNumber(cx, argv[5], &z);
		NSString *arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f", role, num, coordScheme, x, y, z];
		[playerEntity addShipsAtPrecisely:arg];
	}
	return JS_TRUE;
}

JSBool UniverseAddShipsWithinRadius(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	if (argc == 7) {
		jsdouble x, y, z;
		PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
		NSString *role = JSValToNSString(cx, argv[0]);
		int num = JSVAL_TO_INT(argv[1]);
		NSString *coordScheme = JSValToNSString(cx, argv[2]);
		JS_ValueToNumber(cx, argv[3], &x);
		JS_ValueToNumber(cx, argv[4], &y);
		JS_ValueToNumber(cx, argv[5], &z);
		int rad = JSVAL_TO_INT(argv[6]);
		NSString *arg = [NSString stringWithFormat:@"%@ %d %@ %f %f %f %d", role, num, coordScheme, x, y, z, rad];
		[playerEntity addShipsAt:arg];
	}
	return JS_TRUE;
}

JSBool UniverseSpawn(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	if (argc == 2) {
		PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
		NSString *role = JSValToNSString(cx, argv[0]);
		int num = JSVAL_TO_INT(argv[1]);
		NSString *arg = [NSString stringWithFormat:@"%@ %d", role, num];
		[playerEntity spawn:arg];
	}
	return JS_TRUE;
}

JSBool UniverseSpawnShip(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	if (argc == 1) {
		PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];
		[playerEntity spawnShip:JSValToNSString(cx, argv[0])];
	}
	return JS_TRUE;
}


JSBool UniverseAddMessage(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	JSBool ok;
	int32 count;
	if (argc != 2)
		return JS_FALSE;

	ok = JS_ValueToInt32(cx, argv[1], &count);
	NSString *str = JSValToNSString(cx, argv[0]);
	[scriptedUniverse addMessage: str forCount:(int)count];
	//[str dealloc];
	return JS_TRUE;
}

JSBool UniverseAddCommsMessage(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval) {
	JSBool ok;
	int32 count;
	if (argc != 2)
		return JS_FALSE;

	ok = JS_ValueToInt32(cx, argv[1], &count);
	NSString *str = JSValToNSString(cx, argv[0]);
	[scriptedUniverse addCommsMessage: str forCount:(int)count];
	//[str dealloc];
	return JS_TRUE;
}

/*
JSBool UniverseGetProperty(JSContext *cx, JSObject *obj, jsval id, jsval *vp) {
	if (JSVAL_IS_INT(id)) {
		PlayerEntity *playerEntity = (PlayerEntity *)[scriptedUniverse entityZero];

		switch (JSVAL_TO_INT(id)) {
			case UNI_PLAYER_ENTITY: {
				JSObject *pe = JS_DefineObject(cx, universeObj, "PlayerEntity", &PlayerEntity_class, 0x00, JSPROP_ENUMERATE | JSPROP_READONLY | JSPROP_PERMANENT);
				if (pe == 0x00) {
					return JS_FALSE;
				}
				JS_DefineProperties(cx, pe, playerEntity_props);

				*vp = OBJECT_TO_JSVAL(pe);
				break;
			}
		}
	}

	return JS_TRUE;
}
*/
