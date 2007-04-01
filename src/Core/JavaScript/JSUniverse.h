//===========================================================================
// Universe proxy
//===========================================================================

static JSClass Universe_class =
{
	"Universe",
	JSCLASS_HAS_PRIVATE,
	
	JS_PropertyStub,
	JS_PropertyStub,
	JS_PropertyStub,
	JS_PropertyStub,
	JS_EnumerateStub,
	JS_ResolveStub,
	JS_ConvertStub,
	JS_FinalizeStub
};

/*
JSBool UniverseGetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp);

enum Universe_propertyIds {
	UNI_PLAYER_ENTITY
};

JSPropertySpec Universe_props[] = {
	{ "PlayerEntity", UNI_PLAYER_ENTITY, JSPROP_ENUMERATE },
	{ 0 }
};
*/


static JSBool UniverseCountShipsWithRole(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool UniverseAddShips(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool UniverseAddSystemShips(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool UniverseAddShipsAt(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool UniverseAddShipsAtPrecisely(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool UniverseAddShipsWithinRadius(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool UniverseSpawn(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);
static JSBool UniverseSpawnShip(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval);


static JSFunctionSpec Universe_funcs[] =
{
	{ "countShipsWithRole", UniverseCountShipsWithRole, 1, 0 },
	{ "addShips", UniverseAddShips, 2, 0 },
	{ "addSystemShips", UniverseAddSystemShips, 3, 0 },
	{ "addShipsAt", UniverseAddShipsAt, 6, 0 },
	{ "addShipsAtPrecisely", UniverseAddShipsAtPrecisely, 6, 0 },
	{ "addShipsWithinRadius", UniverseAddShipsWithinRadius, 7, 0 },
	{ "spawn", UniverseSpawn, 2, 0 },
	{ "spawnShip", UniverseSpawnShip, 1, 0 },
	{ 0 }
};


static JSBool UniverseCountShipsWithRole(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	if (argc == 1)
	{
		NSString *role = JSValToNSString(cx, argv[0]);
		int num = [[Universe sharedUniverse] countShipsWithRole:role];
		*rval = INT_TO_JSVAL(num);
	}
	return JS_TRUE;
}


static JSBool UniverseAddShips(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	if (argc == 2)
	{
		NSString *role = JSValToNSString(cx, argv[0]);
		int num = JSVAL_TO_INT(argv[1]);

		while (num--)
			[[Universe sharedUniverse] witchspaceShipWithRole:role];
	}
	return JS_TRUE;
}


static JSBool UniverseAddSystemShips(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	if (argc == 3)
	{
		jsdouble posn;
		NSString *role = JSValToNSString(cx, argv[0]);
		int num = JSVAL_TO_INT(argv[1]);
		JS_ValueToNumber(cx, argv[2], &posn);
		while (num--)
			[[Universe sharedUniverse] addShipWithRole:role nearRouteOneAt:posn];
	}
	return JS_TRUE;
}


static JSBool UniverseAddShipsAt(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	if (argc == 6)
	{
		jsdouble x, y, z;
		PlayerEntity *playerEntity = [PlayerEntity sharedPlayer];
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


static JSBool UniverseAddShipsAtPrecisely(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	if (argc == 6)
	{
		jsdouble x, y, z;
		PlayerEntity *playerEntity = [PlayerEntity sharedPlayer];
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


static JSBool UniverseAddShipsWithinRadius(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	if (argc == 7)
	{
		jsdouble x, y, z;
		PlayerEntity *playerEntity = [PlayerEntity sharedPlayer];
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


static JSBool UniverseSpawn(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	if (argc == 2)
	{
		PlayerEntity *playerEntity = [PlayerEntity sharedPlayer];
		NSString *role = JSValToNSString(cx, argv[0]);
		int num = JSVAL_TO_INT(argv[1]);
		NSString *arg = [NSString stringWithFormat:@"%@ %d", role, num];
		[playerEntity spawn:arg];
	}
	return JS_TRUE;
}


static JSBool UniverseSpawnShip(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	if (argc == 1)
	{
		PlayerEntity *playerEntity = [PlayerEntity sharedPlayer];
		[playerEntity spawnShip:JSValToNSString(cx, argv[0])];
	}
	return JS_TRUE;
}


/*static JSBool UniverseAddMessage(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	JSBool ok;
	int32 count;
	if (argc != 2)  return JS_FALSE;

	ok = JS_ValueToInt32(cx, argv[1], &count);
	NSString *str = JSValToNSString(cx, argv[0]);
	[[Universe sharedUniverse] addMessage: str forCount:(int)count];
	return JS_TRUE;
}


static JSBool UniverseAddCommsMessage(JSContext *cx, JSObject *obj, uintN argc, jsval *argv, jsval *rval)
{
	JSBool ok;
	int32 count;
	if (argc != 2)  return JS_FALSE;

	ok = JS_ValueToInt32(cx, argv[1], &count);
	NSString *str = JSValToNSString(cx, argv[0]);
	[[Universe sharedUniverse] addCommsMessage: str forCount:(int)count];
	return JS_TRUE;
}*/

/*
JSBool UniverseGetProperty(JSContext *cx, JSObject *obj, jsval name, jsval *vp) {
	if (JSVAL_IS_INT(name)) {
		PlayerEntity *playerEntity = [PlayerEntity sharedPlayer];

		switch (JSVAL_TO_INT(name)) {
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
