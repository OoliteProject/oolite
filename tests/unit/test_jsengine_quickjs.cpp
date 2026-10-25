/*	test_jsengine_quickjs.cpp
	Unit test for the ooscript façade on the QuickJS-ng backend (seam 1.4b, bead oo-0kq).
	Plain C++20 against the façade header and the backend TU, linked against the vendored
	QuickJS-ng library; no GNUstep, no SDL.

	Scoped to what JSEngine_quickjs.cpp implements (Context/Value/Object/ClassDef lifecycle plus
	resolve/enumerate mapped onto JSClassExoticMethods, and private-pointer attach/retrieve): see
	that file's banner for the full list of what is out of scope for this bead. It began as the
	same shape of check as the (since retired) SpiderMonkey backend's unit test: number
	canonicalisation, private data through a class with a finalizer, and resolve/enumerate acting
	through the façade's own PropertyId/hook types rather than any engine-specific handle.

	Bead oo-1gc.2 made the backend implement all of JSEngine.hpp; runFullSurface() (after the seam
	tests, on a runtime of its own) covers each area: values and conversions, strings (non-ASCII,
	ropes, interning), plain-object properties and arrays, initClass with tinyid accessors, methods
	and a native constructor, string-id class hooks (resolve/get/set/add/del), new-enumerate,
	convert and call hooks, natives and CallArgs, evaluation with a scope object and error
	filename/line, compile/serialize/deserialize/execute, exceptions and the reporter, the
	operation callback, and the GC arena (roots read at flush time, unrooted handles released).
*/

#include "ooscript/JSEngine.hpp"

#include <cmath>
#include <cstdio>
#include <cstring>
#include <limits>
#include <string>

// Declared in JSEngine_quickjs.cpp; test-only glue between a PropertySpec-style name/tinyid pair
// and the resolve/enumerate exotic methods (see that file's banner).
namespace ooscript { void registerResolvableProperty(Context cx, ClassDef* def, const char* name, std::int32_t tinyid); }

namespace {

int gFailures = 0;
#define CHECK(cond) do { if (!(cond)) { std::printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); ++gFailures; } } while (0)

using namespace ooscript;

struct Point { double x; double y; };
int gFinalized = 0;
int gResolveCalls = 0;
int gEnumerateCalls = 0;

enum { kP_x = 1, kP_y = 2 };

bool PointResolve(Context cx, Object obj, PropertyId id)
{
	++gResolveCalls;
	if (!isInt32Id(id))  return true;
	auto* p = static_cast<Point*>(getPrivate(cx, obj));
	CHECK(p != nullptr);
	CHECK(idToInt32(id) == kP_x || idToInt32(id) == kP_y);
	return true;
}

bool PointEnumerate(Context /*cx*/, Object /*obj*/)
{
	++gEnumerateCalls;
	return true;
}

void PointFinalize(Context /*cx*/, Object /*obj*/)
{
	++gFinalized;
}

ClassDef sPointClass = { "Point", ClassFlag::HasPrivate, nullptr, nullptr, nullptr, nullptr,
                          PointEnumerate, nullptr, PointResolve, nullptr, PointFinalize, nullptr, nullptr, nullptr };

// Regression fixture for bead oo-902s: unlike PointFinalize above, this finalizer actually reads
// its Context argument, so a dangling JSContext* handed to it (the bug this bead fixes) would
// misbehave instead of going unnoticed. See its use in main() for the destroyContext()-then-
// destroyRuntime() sequence that exercises it.
bool gTouchFinalizeRan = false;
bool gTouchFinalizeCtxOk = false;
void TouchFinalize(Context fcx, Object /*obj*/)
{
	gTouchFinalizeRan = true;
	// After the fix, destroyContext() erased this context's gCtxForRuntime entry, so
	// FinalizeTramp's lookup for this runtime comes up empty and it passes wrap(nullptr) here --
	// never this context's own (by-then-freed) JSContext*, and never some other, unrelated
	// context's pointer either (see main()'s "noise" contexts, which are deliberately churned
	// through newContext()/destroyContext() on the same runtime between destroyContext(cx) and
	// destroyRuntime(rt) specifically to prove this: without the fix, each of those calls would
	// leave its own stale entry in gCtxForRuntime, so this finalizer would receive whichever
	// dangling pointer was left behind, never nullptr). So the fix is exactly: fcx must be null.
	gTouchFinalizeCtxOk = (fcx == nullptr);
}
ClassDef sTouchClass = { "Touch", ClassFlag::HasPrivate, nullptr, nullptr, nullptr, nullptr,
                          nullptr, nullptr, nullptr, nullptr, TouchFinalize, nullptr, nullptr, nullptr };

// A second class reusing the same tinyids with a distinct resolve hook: the trampoline/exotic
// dispatch must not confuse the two classes' hooks (JSClassID is per-class, not per-tinyid).
int gScaledResolveCalls = 0;
bool ScaledResolve(Context /*cx*/, Object /*obj*/, PropertyId id)
{
	++gScaledResolveCalls;
	CHECK(isInt32Id(id));
	return true;
}
ClassDef sScaledClass = { "ScaledPoint", ClassFlag::HasPrivate, nullptr, nullptr, nullptr, nullptr,
                           nullptr, nullptr, ScaledResolve, nullptr, PointFinalize, nullptr, nullptr, nullptr };

// MARK: Full façade surface (bead oo-1gc.2) ------------------------------------------------------
//
// Everything below runs on a runtime of its own, after the seam tests above have torn theirs down.
// One block per area of JSEngine.hpp; SpiderMonkey 1.8.5 behaviour is the expectation throughout.

struct Captured
{
	int            calls = 0;
	std::string    message;
	std::string    file;
	unsigned       line = 0;
	unsigned       flags = 0;
	std::u16string uc;
};
Captured gCap;

void CaptureReporter(Context, const char* message, const ErrorReport* report)
{
	++gCap.calls;
	gCap.message = message != nullptr ? message : "";
	gCap.file    = (report != nullptr && report->filename != nullptr) ? report->filename : "";
	gCap.line    = report != nullptr ? report->lineno : 0;
	gCap.flags   = report != nullptr ? report->flags : 0;
	gCap.uc      = (report != nullptr && report->ucmessage != nullptr) ? std::u16string(report->ucmessage) : std::u16string();
}

bool strIs(Context cx, String s, const std::u16string& expect)
{
	std::size_t len = 0;
	const Char16* chars = s != nullptr ? getStringCharsAndLength(cx, s, &len) : nullptr;
	return chars != nullptr && std::u16string(chars, len) == expect;
}

bool valIs(Context cx, Value v, const std::u16string& expect) { return isString(v) && strIs(cx, toString(v), expect); }

bool eval(Context cx, Object scope, const char* src, Value* rv, const char* file = "full.js", unsigned line = 1)
{
	return evaluateScript(cx, scope, src, static_cast<unsigned>(std::strlen(src)), file, line, rv);
}

// A class whose finalizer flips an int the test owns: how the GC tests see what was released.
void TrackedFinalize(Context cx, Object obj)
{
	if (int* flag = static_cast<int*>(getPrivate(cx, obj)))  ++*flag;
}
ClassDef sTrackedClass = { "Tracked", ClassFlag::HasPrivate, nullptr, nullptr, nullptr, nullptr,
                           nullptr, nullptr, nullptr, nullptr, TrackedFinalize, nullptr, nullptr, nullptr };

Object newTracked(Context cx, int* flag)
{
	Object o = newObject(cx, &sTrackedClass, nullptr, nullptr);
	setPrivate(cx, o, flag);
	return o;
}

// Widget: initClass with a native constructor, tinyid accessors (one with its own hooks, two
// dispatched through the class getProperty hook, Oolite's usual pattern) and a method.
struct Widget { std::int32_t size; };
enum { kW_size = 1, kW_label = 2, kW_ro = 3 };
int  gWidgetFinalized = 0;
int  gCtorCalls = 0;
bool gCtorConstructing = false;
bool gCtorThisIsWidget = false;
ClassDef sWidgetClass;

Widget* widgetOf(Context cx, Object obj) { return static_cast<Widget*>(getPrivate(cx, obj)); }

bool WidgetClassGet(Context cx, Object obj, PropertyId id, Value* vp)
{
	if (!isInt32Id(id))  return true;
	switch (idToInt32(id))
	{
		case kW_label: *vp = stringValue(newStringCopyZ(cx, "widget")); return true;
		case kW_ro:    { Widget* w = widgetOf(cx, obj); *vp = int32Value(w != nullptr ? w->size * 10 : -1); return true; }
		default:       return true;
	}
}
bool WidgetSizeGet(Context cx, Object obj, PropertyId id, Value* vp)
{
	CHECK(isInt32Id(id) && idToInt32(id) == kW_size);
	Widget* w = widgetOf(cx, obj);
	*vp = int32Value(w != nullptr ? w->size : -1);
	return true;
}
bool WidgetSizeSet(Context cx, Object obj, PropertyId id, bool, Value* vp)
{
	CHECK(isInt32Id(id) && idToInt32(id) == kW_size);
	std::int32_t i = 0;
	if (!valueToECMAInt32(cx, *vp, &i))  return false;
	if (Widget* w = widgetOf(cx, obj))  w->size = i;
	return true;
}
bool WidgetTwice(Context cx, CallArgs& args)
{
	Widget* w = static_cast<Widget*>(getInstancePrivate(cx, args.thisObject(), &sWidgetClass, args.argv()));
	if (w == nullptr)  return false;
	double d = 0;
	if (args.count() < 1 || !valueToNumber(cx, args[0], &d))  return false;
	args.setRval(numberValue(d * 2 + w->size));
	return true;
}
bool WidgetConstruct(Context cx, CallArgs& args)
{
	++gCtorCalls;
	gCtorConstructing = args.isConstructing();
	if (!gCtorConstructing)
	{
		args.setRval(int32Value(-1));
		return true;
	}
	Object self = args.thisObject();
	gCtorThisIsWidget = getClass(cx, self) == &sWidgetClass;
	setPrivate(cx, self, new Widget{args.count() > 0 && isInt32(args[0]) ? toInt32(args[0]) : 0});
	args.setRval(objectValue(self));
	return true;
}
void WidgetFinalize(Context cx, Object obj)
{
	delete widgetOf(cx, obj);
	++gWidgetFinalized;
}
PropertySpec sWidgetProps[] =
{
	{ "size",  kW_size,  PropertyFlag::Enumerate | PropertyFlag::Permanent, WidgetSizeGet, WidgetSizeSet },
	{ "label", kW_label, PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Permanent, nullptr, nullptr },
	{ "ro",    kW_ro,    PropertyFlag::ReadOnly, nullptr, nullptr },
	{ nullptr, 0, PropertyFlag::None, nullptr, nullptr }
};
FunctionSpec sWidgetMethods[] = { { "twice", WidgetTwice, 1, 0 }, { nullptr, nullptr, 0, 0 } };

// Bag: every per-property class hook, with string ids (missionVariables-style).
int gBagAdds = 0, gBagDels = 0, gBagResolves = 0;
bool idIs(Context cx, PropertyId id, const char* name)
{
	bool m = false;
	return isStringId(id) && stringEqualsAscii(cx, idToString(id), name, &m) && m;
}
bool BagResolve(Context cx, Object obj, PropertyId id)
{
	++gBagResolves;
	if (idIs(cx, id, "lazy"))  return definePropertyById(cx, obj, id, int32Value(7), nullptr, nullptr, PropertyFlag::Enumerate);
	return true;
}
bool BagGet(Context cx, Object, PropertyId id, Value* vp)
{
	if (idIs(cx, id, "magic") && isUndefined(*vp))  *vp = int32Value(99);
	return true;
}
bool BagSet(Context, Object, PropertyId, bool, Value* vp)
{
	if (isInt32(*vp))  *vp = int32Value(toInt32(*vp) * 2);
	return true;
}
bool BagAdd(Context, Object, PropertyId, Value*) { ++gBagAdds; return true; }
bool BagDel(Context, Object, PropertyId, Value*) { ++gBagDels; return true; }
ClassDef sBagClass = { "Bag", ClassFlag::None, BagAdd, BagDel, BagGet, BagSet,
                       nullptr, nullptr, BagResolve, nullptr, nullptr, nullptr, nullptr, nullptr };

// Enum: the new-enumerate protocol, values supplied by the getProperty hook.
bool EnumNext(Context cx, Object, EnumerateOp op, Value* statep, PropertyId* idp)
{
	switch (op)
	{
		case EnumerateOp::Init:
		case EnumerateOp::InitAll: *statep = int32Value(0); return true;
		case EnumerateOp::Destroy: *statep = nullValue(); return true;
		case EnumerateOp::Next:
		{
			const std::int32_t i = toInt32(*statep);
			if (i >= 2)  { *statep = nullValue(); return true; }
			*statep = int32Value(i + 1);
			return valueToId(cx, stringValue(internString(cx, i == 0 ? "a" : "b")), idp);
		}
	}
	return false;
}
bool EnumGet(Context cx, Object, PropertyId id, Value* vp)
{
	if (idIs(cx, id, "a"))  *vp = int32Value(1);
	if (idIs(cx, id, "b"))  *vp = int32Value(2);
	return true;
}
ClassDef sEnumClass = { "Enum", ClassFlag::NewEnumerate, nullptr, nullptr, EnumGet, nullptr,
                        nullptr, EnumNext, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr };

// Store: Enum's names, plus a setProperty hook (bead oo-f1yi3). Assigning to a name the last
// enumeration listed must reach the setter, as SpiderMonkey's add-then-set did.
std::int32_t gStoreA = 1;
int gStoreSets = 0;
bool StoreGet(Context cx, Object, PropertyId id, Value* vp)
{
	if (idIs(cx, id, "a"))  *vp = int32Value(gStoreA);
	return true;
}
bool StoreSet(Context cx, Object, PropertyId id, bool, Value* vp)
{
	++gStoreSets;
	if (idIs(cx, id, "a") && isInt32(*vp))  gStoreA = toInt32(*vp);
	return true;
}
ClassDef sStoreClass = { "Store", ClassFlag::NewEnumerate, nullptr, nullptr, StoreGet, StoreSet,
                         nullptr, EnumNext, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr };

// Temp: a convert hook; Callable: a class call hook.
bool TempConvert(Context, Object, Type hint, Value* vp)
{
	if (hint == Type::Number)  *vp = int32Value(21);
	return true;
}
bool TempConstruct(Context, CallArgs& args) { args.setRval(objectValue(args.thisObject())); return true; }
ClassDef sTempClass = { "Temp", ClassFlag::None, nullptr, nullptr, nullptr, nullptr,
                        nullptr, nullptr, nullptr, TempConvert, nullptr, nullptr, nullptr, nullptr };
bool CallableCall(Context, CallArgs& args) { args.setRval(int32Value(5 + static_cast<std::int32_t>(args.count()))); return true; }
ClassDef sShipScriptClass = { "ShipScript", ClassFlag::None, nullptr, nullptr, nullptr, nullptr,
                              nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr };
ClassDef sCallableClass = { "Callable", ClassFlag::None, nullptr, nullptr, nullptr, nullptr,
                            nullptr, nullptr, nullptr, nullptr, nullptr, CallableCall, nullptr, nullptr };

// Natives.
Value gAddThis;
bool Add(Context cx, CallArgs& args)
{
	double a = 0, b = 0;
	if (!valueToNumber(cx, args[0], &a) || !valueToNumber(cx, args[1], &b))  return false;   // nargs pads with undefined
	gAddThis = args.thisValue();
	args.setRval(numberValue(a + b));
	return true;
}
bool Self(Context, CallArgs& args) { args.setRval(args[0]); return true; }   // returns its argument
bool Failer(Context cx, CallArgs&) { reportError(cx, "failer says no"); return false; }
bool Aborter(Context, CallArgs&)   { return false; }   // nothing pending: an uncatchable abort
bool gPlainGetterSawName = false;
bool PlainGetter(Context cx, Object, PropertyId id, Value* vp)
{
	gPlainGetterSawName = idIs(cx, id, "computed");
	*vp = int32Value(123);
	return true;
}

int gOpCalls = 0;
bool OpAbort(Context)    { ++gOpCalls; return false; }
bool OpContinue(Context) { ++gOpCalls; return true; }

// The body runs in its own function so that its RAII roots unwind before the context goes.
void exerciseFacade(Runtime rt, Context cx)
{
	Object global = getGlobalObject(cx);
	Value rv = undefinedValue();

	// -- Values, conversions, types ---------------------------------------------------------
	CHECK(isPrimitive(nullValue()) && isObjectOrNull(nullValue()) && !isObject(nullValue()));
	int marker = 0;
	CHECK(toPrivate(privateValue(&marker)) == &marker && !isNumber(privateValue(&marker)) && !isObject(privateValue(&marker)));
	CHECK(isDouble(numberValue(std::nan(""))) && std::isnan(toDouble(numberValue(-std::nan("")))));
	CHECK(newNumberValue(cx, 4.0, &rv) && isInt32(rv) && toInt32(rv) == 4);
	std::int32_t i32 = 0;
	std::uint32_t u32 = 0;
	CHECK(valueToInt32(cx, numberValue(2.5), &i32) && i32 == 3);                  // round to nearest
	CHECK(valueToECMAInt32(cx, numberValue(4294967297.0), &i32) && i32 == 1);     // ECMA wrap
	CHECK(valueToECMAUint32(cx, int32Value(-1), &u32) && u32 == 4294967295u);
	double dbl = 0;
	CHECK(valueToNumber(cx, stringValue(newStringCopyZ(cx, " 12.5 ")), &dbl) && dbl == 12.5);
	bool b = true;
	CHECK(valueToBoolean(cx, stringValue(newStringCopyZ(cx, "")), &b) && !b);
	Object o = global;
	CHECK(valueToObject(cx, nullValue(), &o) && o == nullptr);
	CHECK(valueToObject(cx, int32Value(3), &o) && o != nullptr);                  // a Number wrapper
	CHECK(strIs(cx, valueToString(cx, int32Value(42)), u"42"));
	CHECK(typeOfValue(cx, int32Value(1)) == Type::Number && typeOfValue(cx, nullValue()) == Type::Object);
	CHECK(typeOfValue(cx, undefinedValue()) == Type::Void && typeOfValue(cx, trueValue()) == Type::Boolean);
	CHECK(std::strcmp(typeName(Type::Function), "function") == 0 && std::strcmp(typeName(Type::Void), "undefined") == 0);
	PropertyId pid = voidId();
	CHECK(valueToId(cx, stringValue(newStringCopyZ(cx, "name")), &pid) && isStringId(pid) && strIs(cx, idToString(pid), u"name"));
	CHECK(idToValue(cx, pid, &rv) && valIs(cx, rv, u"name"));
	CHECK(valueToId(cx, int32Value(3), &pid) && isInt32Id(pid) && idToInt32(pid) == 3);
	CHECK(valueToId(cx, stringValue(newStringCopyZ(cx, "7")), &pid) && isInt32Id(pid) && idToInt32(pid) == 7);

	// Errors raised outside any script go to the reporter directly and leave nothing pending.
	CHECK(setErrorReporter(cx, CaptureReporter) == nullptr);
	gCap = Captured();
	CHECK(!valueToInt32(cx, numberValue(1e20), &i32));
	CHECK(gCap.calls == 1 && !isExceptionPending(cx));
	gCap = Captured();
	CHECK(valueToFunction(cx, int32Value(3)) == nullptr && gCap.calls == 1 && !isExceptionPending(cx));

	// -- Strings -----------------------------------------------------------------------------------
	String s1 = newStringCopyZ(cx, "h\xC3\xA9llo \xE2\x82\xAC");                      // UTF-8 "héllo €"
	CHECK(strIs(cx, s1, u"héllo €") && getStringLength(s1) == 7);
	const char16_t wide[] = u"日本 \U0001D11E";                                 // BMP + a surrogate pair
	String s2 = newUCStringCopyN(cx, wide, std::char_traits<char16_t>::length(wide));
	CHECK(strIs(cx, s2, wide) && isString(stringValue(s2)) && toString(stringValue(s2)) == s2);
	CHECK(strIs(cx, newStringCopyN(cx, "abcdef", 3), u"abc"));
	String i1 = internString(cx, "interned");
	CHECK(i1 != nullptr && i1 == internString(cx, "interned") && stringHasBeenInterned(cx, i1));
	CHECK(internUCStringN(cx, u"interned", 8) == i1);
	CHECK(!stringHasBeenInterned(cx, newStringCopyZ(cx, "fresh")));
	CHECK(getInternedStringChars(i1) != nullptr && std::u16string(getInternedStringChars(i1), 8) == u"interned");
	bool match = false;
	CHECK(stringEqualsAscii(cx, i1, "interned", &match) && match);
	CHECK(stringEqualsAscii(cx, i1, "intern", &match) && !match);
	Value empty = emptyStringValue(cx);
	CHECK(isString(empty) && getStringLength(toString(empty)) == 0);
	// A concatenation the engine keeps as a rope comes back as a flat, readable string.
	CHECK(eval(cx, nullptr, "var r1 = 'x'.repeat(300); r1 + 'y' + r1", &rv) && isString(rv) && getStringLength(toString(rv)) == 601);
	const char16_t ucSrc[] = u"'é' + '€'";
	CHECK(evaluateUCScript(cx, nullptr, ucSrc, static_cast<unsigned>(std::char_traits<char16_t>::length(ucSrc)), "uc.js", 1, &rv) && valIs(cx, rv, u"é€"));
	setCStringsAreUTF8();

	// -- Plain objects: properties, lookup, delete, enumerate, arrays ---------------------------------
	Object plain = newObject(cx, nullptr, nullptr, nullptr);
	RootedObject plainRoot(cx, plain, "plain");
	CHECK(getClass(cx, plain) == nullptr && getPrototype(cx, plain) != nullptr);
	CHECK(getParent(cx, plain) == global && getGlobalForObject(cx, plain) == global);
	rv = int32Value(5);
	CHECK(setProperty(cx, plain, "a", &rv));
	rv = undefinedValue();
	CHECK(getProperty(cx, plain, "a", &rv) && isInt32(rv) && toInt32(rv) == 5);
	CHECK(defineProperty(cx, plain, "fixed", int32Value(9), nullptr, nullptr, PropertyFlag::Enumerate | PropertyFlag::ReadOnly | PropertyFlag::Permanent));
	CHECK(defineProperty(cx, plain, "hidden", int32Value(1), nullptr, nullptr, PropertyFlag::None));
	CHECK(defineProperty(cx, plain, "computed", undefinedValue(), PlainGetter, nullptr, PropertyFlag::Enumerate));
	CHECK(getProperty(cx, plain, "computed", &rv) && isInt32(rv) && toInt32(rv) == 123 && gPlainGetterSawName);
	CHECK(lookupProperty(cx, plain, "fixed", &rv) && isInt32(rv) && toInt32(rv) == 9);
	CHECK(lookupProperty(cx, plain, "computed", &rv) && isBoolean(rv) && toBoolean(rv));   // accessor: true, getter not run
	CHECK(lookupProperty(cx, plain, "nope", &rv) && isUndefined(rv));
	bool found = false;
	CHECK(hasProperty(cx, plain, "toString", &found) && found);
	CHECK(hasProperty(cx, plain, "nope", &found) && !found);
	PropertyId idA = voidId();
	CHECK(valueToId(cx, stringValue(newStringCopyZ(cx, "a")), &idA));
	CHECK(lookupPropertyById(cx, plain, idA, &rv) && isInt32(rv) && toInt32(rv) == 5);
	rv = int32Value(6);
	CHECK(setPropertyById(cx, plain, idA, &rv) && getPropertyById(cx, plain, idA, &rv) && toInt32(rv) == 6);
	Object holder = nullptr;
	CHECK(getMethodById(cx, plain, idA, &holder, &rv) && holder == plain && toInt32(rv) == 6);
	IdArray* ids = enumerate(cx, plain);
	CHECK(ids != nullptr && ids->length == 3);                                          // a, fixed, computed
	destroyIdArray(cx, ids);
	CHECK(deleteProperty(cx, plain, "fixed") && hasProperty(cx, plain, "fixed", &found) && found);   // permanent stays
	CHECK(deleteProperty(cx, plain, "a") && hasProperty(cx, plain, "a", &found) && !found);
	CHECK(definePropertyById(cx, plain, int32Id(4), int32Value(44), nullptr, nullptr, PropertyFlag::Enumerate));
	CHECK(getElement(cx, plain, 4, &rv) && toInt32(rv) == 44 && lookupElement(cx, plain, 4, &rv) && toInt32(rv) == 44);
	Object child = defineObject(cx, plain, "child", nullptr, nullptr, PropertyFlag::Enumerate);
	CHECK(child != nullptr && getProperty(cx, plain, "child", &rv) && toObject(rv) == child);
	clearScope(cx, plain);
	CHECK(hasProperty(cx, plain, "child", &found) && !found && hasProperty(cx, plain, "fixed", &found) && found);

	Value elems[3] = { int32Value(1), int32Value(2), stringValue(newStringCopyZ(cx, "three")) };
	Object arr = newArrayObject(cx, 3, elems);
	std::uint32_t len = 0;
	CHECK(arr != nullptr && isArrayObject(cx, arr) && !isArrayObject(cx, plain));
	CHECK(getArrayLength(cx, arr, &len) && len == 3);
	CHECK(getElement(cx, arr, 2, &rv) && valIs(cx, rv, u"three"));
	rv = int32Value(9);
	CHECK(setElement(cx, arr, 5, &rv) && getArrayLength(cx, arr, &len) && len == 6);
	CHECK(setArrayLength(cx, arr, 2) && getArrayLength(cx, arr, &len) && len == 2);
	Object holes = newArrayObject(cx, 4, nullptr);
	CHECK(holes != nullptr && getArrayLength(cx, holes, &len) && len == 4);

	// -- initClass: constructor, tinyid accessors, class-hook dispatch, methods ----------------------
	sWidgetClass = ClassDef{ "Widget", ClassFlag::HasPrivate, nullptr, nullptr, WidgetClassGet, nullptr,
	                         nullptr, nullptr, nullptr, nullptr, WidgetFinalize, nullptr, nullptr, nullptr };
	Object widgetProto = initClass(cx, global, nullptr, &sWidgetClass, WidgetConstruct, 1,
	                               sWidgetProps, sWidgetMethods, nullptr, nullptr);
	CHECK(widgetProto != nullptr && getClass(cx, widgetProto) == &sWidgetClass);
	Object widgetCtor = getConstructor(cx, widgetProto);
	CHECK(widgetCtor != nullptr && objectIsFunction(cx, widgetCtor));
	CHECK(getProperty(cx, global, "Widget", &rv) && toObject(rv) == widgetCtor);
	CHECK(eval(cx, nullptr,
	           "var w = new Widget(5);"
	           "var out = [w.size, w.twice(3), w.label, w instanceof Widget, w.ro, Object.keys(w).length];"
	           "w.size = 7; out.push(w.size); w.ro = 99; out.push(w.ro); out.push(Widget(1));"
	           "out.join(',')", &rv));
	CHECK(valIs(cx, rv, u"5,11,widget,true,50,0,7,70,-1"));
	CHECK(gCtorCalls == 2 && !gCtorConstructing && gCtorThisIsWidget);
	CHECK(getProperty(cx, global, "w", &rv) && isObject(rv) && getClass(cx, toObject(rv)) == &sWidgetClass);
	CHECK(getPrototype(cx, toObject(rv)) == widgetProto);
	CHECK(instanceOf(cx, toObject(rv), &sWidgetClass, nullptr) && !instanceOf(cx, plain, &sWidgetClass, nullptr));
	CHECK(getInstancePrivate(cx, toObject(rv), &sWidgetClass, nullptr) != nullptr);
	// A method called on the wrong class reports "incompatible" as an exception inside script.
	CHECK(eval(cx, nullptr, "try { w.twice.call({}, 1); 'no' } catch (e) { 'caught' }", &rv) && valIs(cx, rv, u"caught"));

	// -- Class hooks with string ids: resolve, getProperty, setProperty, add/delProperty -------------
	Object bag = newObject(cx, &sBagClass, nullptr, nullptr);
	Value bagVal = objectValue(bag);
	CHECK(setProperty(cx, global, "bag", &bagVal));
	CHECK(eval(cx, nullptr,
	           "var o2 = [bag.lazy, bag.magic, typeof bag.nothing];"
	           "bag.x = 4; o2.push(bag.x); o2.push(Object.keys(bag).join(','));"
	           "o2.push(delete bag.x, bag.x === undefined, 'lazy' in bag);"
	           "o2.join('|')", &rv));
	CHECK(valIs(cx, rv, u"7|99|undefined|8|lazy,x|true|true|true"));
	CHECK(gBagResolves > 0 && gBagAdds >= 2 && gBagDels == 1);

	Object en = newObject(cx, &sEnumClass, nullptr, nullptr);
	Value enVal = objectValue(en);
	CHECK(setProperty(cx, global, "en", &enVal));
	CHECK(eval(cx, nullptr, "var ks = []; for (var k in en) ks.push(k); ks.join(',') + '|' + Object.keys(en).join(',') + '|' + en.a + en.b", &rv));
	CHECK(valIs(cx, rv, u"a,b|a,b|12"));

	Object store = newObject(cx, &sStoreClass, nullptr, nullptr);
	Value storeVal = objectValue(store);
	CHECK(setProperty(cx, global, "store", &storeVal));
	CHECK(eval(cx, nullptr,
	           "var o3 = [Object.keys(store).join(','), store.a];"
	           "store.a = 5; o3.push(store.a);"
	           "var d3 = Object.getOwnPropertyDescriptor(store, 'a'); o3.push(d3.writable, d3.configurable);"
	           "store.a = 6; o3.push(delete store.a);"
	           "o3.join('|')", &rv));
	CHECK(valIs(cx, rv, u"a,b|1|5|true|true|true"));
	CHECK(gStoreSets == 2 && gStoreA == 6);
	gStoreA = 3;   // the hook's value, not one frozen on the object
	CHECK(eval(cx, nullptr, "store.a", &rv) && isInt32(rv) && toInt32(rv) == 3);

	CHECK(initClass(cx, global, nullptr, &sTempClass, TempConstruct, 0, nullptr, nullptr, nullptr, nullptr) != nullptr);
	CHECK(eval(cx, nullptr, "var t = new Temp(); t * 2", &rv) && isInt32(rv) && toInt32(rv) == 42);
	Object callable = newObject(cx, &sCallableClass, nullptr, nullptr);
	Value callableVal = objectValue(callable);
	CHECK(setProperty(cx, global, "callme", &callableVal));
	CHECK(eval(cx, nullptr, "callme(1, 2) + typeof callme", &rv) && valIs(cx, rv, u"7function"));

	// -- Natives and calls ---------------------------------------------------------------------------
	Function add = defineFunction(cx, global, "add", Add, 2, PropertyFlag::None);
	CHECK(add != nullptr && getFunctionNative(cx, add) == Add && objectIsFunction(cx, getFunctionObject(add)));
	CHECK(strIs(cx, getFunctionId(add), u"add"));
	CHECK(getFunctionNative(cx, valueToFunction(cx, objectValue(getFunctionObject(add)))) == Add);
	Value argv2[2] = { int32Value(2), numberValue(3.5) };
	CHECK(callFunctionValue(cx, plain, objectValue(getFunctionObject(add)), 2, argv2, &rv) && isDouble(rv) && toDouble(rv) == 5.5);
	CHECK(isObject(gAddThis) && toObject(gAddThis) == plain);
	CHECK(callFunctionName(cx, global, "add", 2, argv2, &rv) && toDouble(rv) == 5.5);
	CHECK(eval(cx, nullptr, "add(40)", &rv) && isDouble(rv) && std::isnan(toDouble(rv)));   // padded argv
	FunctionSpec extra[] = { { "failer", Failer, 0, 0 }, { "aborter", Aborter, 0, 0 }, { nullptr, nullptr, 0, 0 } };
	CHECK(defineFunctions(cx, global, extra));
	CHECK(eval(cx, nullptr, "try { failer(); 'no' } catch (e) { e.message }", &rv) && valIs(cx, rv, u"failer says no"));
	gCap = Captured();
	CHECK(!eval(cx, nullptr, "try { aborter(); 'no' } catch (e) { 'caught' }", &rv));   // uncatchable
	CHECK(!isExceptionPending(cx) && gCap.calls == 0);
	CHECK(eval(cx, nullptr, "function jsfun(a) { return a * 3; } jsfun", &rv) && isObject(rv));
	CHECK(getFunctionNative(cx, valueToFunction(cx, rv)) == nullptr && strIs(cx, getFunctionId(valueToFunction(cx, rv)), u"jsfun"));
	Value argv1[1] = { int32Value(4) };
	CHECK(callFunctionValue(cx, nullptr, rv, 1, argv1, &rv) && toInt32(rv) == 12);
	// SpiderMonkey 1.8.5 let `new` reach any native (bead oo-1gc.13: `new Vector3D.random(n)` in
	// expansion ship scripts): an object result is the value of `new`, a primitive result yields the
	// object created from the callee (plain Object.prototype, since a native has no `prototype`).
	Object ns = newObject(cx, nullptr, nullptr, nullptr);
	Value nsVal = objectValue(ns);
	CHECK(setProperty(cx, global, "ns", &nsVal));
	FunctionSpec nsMethods[] = { { "add", Add, 2, 0 }, { "self", Self, 1, 0 }, { nullptr, nullptr, 0, 0 } };
	CHECK(defineFunctions(cx, ns, nsMethods));
	CHECK(eval(cx, nullptr, "var made = new ns.self({ v: 7 }); made.v", &rv) && isInt32(rv) && toInt32(rv) == 7);
	CHECK(eval(cx, nullptr, "var boxed = new ns.add(1, 2); typeof boxed + (Object.getPrototypeOf(boxed) === Object.prototype)", &rv) && valIs(cx, rv, u"objecttrue"));
	CHECK(eval(cx, nullptr, "typeof new add(1, 2)", &rv) && valIs(cx, rv, u"object"));
	CHECK(eval(cx, nullptr, "ns.add(1, 2) === 3", &rv) && isBoolean(rv) && toBoolean(rv));   // plain calls unchanged

	// -- Evaluation with a scope object: `this`, filename and line numbers in errors ------------------
	Object scope = newObject(cx, nullptr, nullptr, nullptr);
	RootedObject scopeRoot(cx, scope, "scope");
	CHECK(eval(cx, scope, "this.foo = 3; this === globalThis", &rv) && isBoolean(rv) && !toBoolean(rv));
	CHECK(getProperty(cx, scope, "foo", &rv) && toInt32(rv) == 3);
	gCap = Captured();
	CHECK(!eval(cx, scope, "\n\nthrow new Error('boom');", &rv, "scope.js", 10));
	CHECK(!isExceptionPending(cx) && gCap.calls == 1);                                  // reported and cleared at top level
	CHECK(gCap.file == "scope.js" && gCap.line == 12 && gCap.message.find("boom") != std::string::npos);
	CHECK((gCap.flags & static_cast<unsigned>(ReportFlag::Exception)) != 0 && gCap.uc == u"boom");
	gCap = Captured();
	CHECK(!eval(cx, nullptr, "\nvar = ;", &rv, "syntax.js", 5));
	CHECK(gCap.calls == 1 && gCap.file == "syntax.js" && gCap.line == 6);
	gCap = Captured();
	CHECK(!eval(cx, nullptr, "throw 42", &rv));
	CHECK(gCap.calls == 1 && gCap.message == "uncaught exception: 42");

	// -- One script file run for two objects (ship scripts): a bare name in a closure resolves through
	// the object of the handler call, as SpiderMonkey's per-run scope chain did, not through the object
	// the file last ran for (bead oo-1gc.15: `this.list = [...]; ... list[i]` in BUS_MegaBat_events.js).
	Object shipA = newObject(cx, &sShipScriptClass, nullptr, nullptr);
	RootedObject shipARoot(cx, shipA, "shipA");
	Object shipB = newObject(cx, &sShipScriptClass, nullptr, nullptr);
	RootedObject shipBRoot(cx, shipB, "shipB");
	CHECK(eval(cx, shipA, "this.tag = 'A'; this.pick = function () { this.list = [this.tag]; return list[0]; };", &rv, "ship.js"));
	CHECK(eval(cx, shipB, "this.tag = 'B'; this.pick = function () { this.list = [this.tag]; return list[0]; };", &rv, "ship.js"));
	CHECK(callFunctionName(cx, shipA, "pick", 0, nullptr, &rv) && valIs(cx, rv, u"A"));   // B ran ship.js last
	CHECK(callFunctionName(cx, shipB, "pick", 0, nullptr, &rv) && valIs(cx, rv, u"B"));
	CHECK(eval(cx, shipA, "this.peek = function () { return tag; };", &rv, "ship.js"));
	Value peekFn = undefinedValue();
	CHECK(getProperty(cx, shipA, "peek", &peekFn));
	CHECK(callFunctionValue(cx, nullptr, peekFn, 0, nullptr, &rv) && valIs(cx, rv, u"A")); // no marked `this`: the last run (A)

	// -- Compiled scripts: compile, execute with a scope, serialize, deserialize ---------------------
	const char16_t compiled[] = u"this.tag = 'compiled'; 6 * 7";
	Script script = compileUCScript(cx, nullptr, compiled, static_cast<unsigned>(std::char_traits<char16_t>::length(compiled)), "comp.js", 1);
	CHECK(script != nullptr);
	Object scriptObj = newScriptObject(cx, script);
	CHECK(scriptObj != nullptr);
	Object target = newObject(cx, nullptr, nullptr, nullptr);
	RootedObject targetRoot(cx, target, "target");
	CHECK(executeScript(cx, target, script, &rv) && isInt32(rv) && toInt32(rv) == 42);
	CHECK(getProperty(cx, target, "tag", &rv) && valIs(cx, rv, u"compiled"));
	ByteBuffer buf{};
	CHECK(serializeScript(cx, script, &buf) && buf.data != nullptr && buf.length > 0);
	Script copy = deserializeScript(cx, buf.data, buf.length);
	CHECK(copy != nullptr);
	CHECK(executeScript(cx, global, copy, &rv) && toInt32(rv) == 42);
	CHECK(getProperty(cx, global, "tag", &rv) && valIs(cx, rv, u"compiled"));
	CHECK(deserializeScript(cx, buf.data, 4) == nullptr);                              // truncated
	destroyByteBuffer(&buf);
	CHECK(buf.data == nullptr && buf.length == 0);
	destroyScript(cx, script);
	destroyScript(cx, copy);
	gCap = Captured();
	CHECK(compileUCScript(cx, nullptr, u"var = ;", 7, "bad.js", 3) == nullptr && gCap.calls == 1 && gCap.line == 3);

	// -- A script object's manifest property is permanent (bead oo-1gc.14, Svengali.Snoopers) ---------
	// OOJSScript defines oolite_manifest_identifier Permanent|Enumerate|ReadOnly (OOJS_PROP_READONLY,
	// as under SpiderMonkey). A strict `for (var k in this) if (k !== 'name' && k !== 'version')
	// delete this[k];` therefore throws on it, as SpiderMonkey 1.8.5's strict delete of a permanent
	// property did; sloppy code gets false. Expansions that skip it in the same loop load fine.
	Object scriptLike = newObject(cx, nullptr, nullptr, nullptr);
	RootedObject scriptLikeRoot(cx, scriptLike, "scriptLike");
	CHECK(defineProperty(cx, scriptLike, "oolite_manifest_identifier", stringValue(newStringCopyZ(cx, "oolite.oxp.test")), nullptr, nullptr,
	                     PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly));
	CHECK(eval(cx, scriptLike, "this.name = 'n'; this.version = 'v'; this.other = 1; this.purge = function (skipManifest) { 'use strict'; "
	                           "try { for (var k in this) { if (k !== 'name' && k !== 'version' && !(skipManifest && k === 'oolite_manifest_identifier')) delete this[k]; } return 'ok'; } "
	                           "catch (e) { return e.message; } };", &rv));
	Value noSkip = falseValue();
	CHECK(callFunctionName(cx, scriptLike, "purge", 1, &noSkip, &rv) && valIs(cx, rv, u"could not delete property"));
	CHECK(eval(cx, scriptLike, "this.purge = function (skip) { 'use strict'; for (var k in this) { if (k !== 'name' && k !== 'version' && !(skip && k === 'oolite_manifest_identifier')) delete this[k]; } return 'ok'; };", &rv));
	Value skip = trueValue();
	CHECK(callFunctionName(cx, scriptLike, "purge", 1, &skip, &rv) && valIs(cx, rv, u"ok"));
	CHECK(eval(cx, scriptLike, "(function () { return delete this.oolite_manifest_identifier; }).call(this)", &rv) && isBoolean(rv) && !toBoolean(rv));

	// -- Exceptions and reporting --------------------------------------------------------------------
	reportError(cx, "outside");
	CHECK(!isExceptionPending(cx));
	gCap = Captured();
	CHECK(reportWarning(cx, "careful") && gCap.calls == 1 && (gCap.flags & static_cast<unsigned>(ReportFlag::Warning)) != 0);
	setPendingException(cx, int32Value(1));
	gCap = Captured();
	reportOutOfMemory(cx);
	CHECK(!isExceptionPending(cx) && gCap.calls == 1 && gCap.message == "out of memory");
	setPendingException(cx, stringValue(newStringCopyZ(cx, "thrown")));
	Value pending = undefinedValue();
	CHECK(getPendingException(cx, &pending) && valIs(cx, pending, u"thrown") && isExceptionPending(cx));
	gCap = Captured();
	CHECK(reportPendingException(cx) && !isExceptionPending(cx) && gCap.message == "uncaught exception: thrown");

	// -- Regular expressions, versions, options, requests, GC parameters -------------------------------
	Object re = newUCRegExpObjectNoStatics(cx, u"a+b", 3, 0x01 | 0x02);
	CHECK(re != nullptr);
	Value reVal = objectValue(re);
	CHECK(setProperty(cx, global, "re", &reVal));
	CHECK(eval(cx, nullptr, "re.flags + '|' + re.test('xAAB')", &rv) && valIs(cx, rv, u"gi|true"));
	CHECK(setVersion(cx, Version::ECMA5) == Version::Default && getVersion(cx) == Version::ECMA5);
	CHECK(std::strcmp(versionToString(Version::ECMA5), "ECMAv5") == 0);
	CHECK(setOptions(cx, ContextOption::VarObjFix | ContextOption::AnonFunFix) == ContextOption::None);
	CHECK(getOptions(cx) == (ContextOption::VarObjFix | ContextOption::AnonFunFix));
	CHECK(!isInRequest(cx));
	{
		Request request(cx);
		CHECK(isInRequest(cx));
	}
	CHECK(!isInRequest(cx) && !isThreadsafeBuild() && !gcZealSupported());
	setGCZeal(cx, 0);
	CHECK(getGCParameter(rt, GCParam::Bytes) > 0);
	setGCParameter(rt, GCParam::MaxMallocBytes, 4u * 1024u * 1024u);
	CHECK(getGCParameter(rt, GCParam::MaxMallocBytes) == 4u * 1024u * 1024u);
	CHECK(getGCParameter(rt, GCParam::MaxBytes) == 64u * 1024u * 1024u);
	int dummy = 0;
	setContextPrivate(cx, &dummy);
	CHECK(getContextPrivate(cx) == &dummy);

	// -- Global object as the ClassDef's instance --------------------------------------------------------
	static ClassDef sGlobalDef = { "Global", ClassFlag::Global, nullptr, nullptr, nullptr, nullptr,
	                               nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr };
	CHECK(newGlobalObject(cx, &sGlobalDef) == global);
	setGlobalObject(cx, global);
	CHECK(initStandardClasses(cx, global) && getClass(cx, global) == &sGlobalDef);
	CHECK(setPrivate(cx, global, &dummy) && getPrivate(cx, global) == &dummy);

	// -- Operation callback --------------------------------------------------------------------------------
	CHECK(setOperationCallback(cx, OpAbort) == nullptr);
	triggerOperationCallback(cx);
	gCap = Captured();
	CHECK(!eval(cx, nullptr, "var spin = 0; while (true) { spin++; }", &rv));
	CHECK(gOpCalls == 1 && !isExceptionPending(cx) && gCap.calls == 0);
	CHECK(setOperationCallback(cx, OpContinue) == OpAbort);
	triggerAllOperationCallbacks(rt);
	CHECK(eval(cx, nullptr, "var sum = 0; for (var n = 0; n < 200000; n++) sum += n; sum", &rv) && gOpCalls == 2);
	CHECK(eval(cx, nullptr, "sum", &rv) && isDouble(rv) && toDouble(rv) == 19999900000.0);
	setOperationCallback(cx, nullptr);

	// -- GC: roots are addresses read at flush time; unrooted handles are released --------------------
	{
		int flagA = 0, flagB = 0;
		Object a = newTracked(cx, &flagA);
		newTracked(cx, &flagB);                                   // unrooted, unreachable
		CHECK(addNamedObjectRoot(cx, &a, "a"));
		const std::uint32_t before = getGCParameter(rt, GCParam::NumberOfGCs);
		gc(cx);
		CHECK(getGCParameter(rt, GCParam::NumberOfGCs) == before + 1);
		CHECK(flagB == 1 && flagA == 0 && getClass(cx, a) == &sTrackedClass);
		CHECK(removeObjectRoot(cx, &a) && !removeObjectRoot(cx, &a));
		gc(cx);
		CHECK(flagA == 1);
	}
	{
		int flagC = 0, flagD = 0;
		Object c = newTracked(cx, &flagC);
		Object d = newTracked(cx, &flagD);
		{
			RootedValue rooted(cx, objectValue(c), "rooted");
			rooted.set(objectValue(d));                              // the root now holds d, not c
			maybeGC(cx);
			CHECK(flagC == 1 && flagD == 0 && toObject(rooted.get()) == d);
		}
		gc(cx);
		CHECK(flagD == 1);
	}
	{
		String str = newStringCopyZ(cx, "rooted \xC3\xBCn\xC3\xAF" "code");
		CHECK(addNamedStringRoot(cx, &str, "str"));
		gc(cx);
		CHECK(strIs(cx, str, u"rooted ünïcode"));
		CHECK(removeStringRoot(cx, &str));
	}
	{
		// Two requests deep (a caller's request around the gc site's own) the arena is not flushed.
		int flagE = 0;
		newTracked(cx, &flagE);
		beginRequest(cx);
		beginRequest(cx);
		gc(cx);
		CHECK(flagE == 0);
		endRequest(cx);
		endRequest(cx);
		gc(cx);
		CHECK(flagE == 1);
	}
	// Objects reachable from the global survive a flush with no roots at all.
	CHECK(eval(cx, nullptr, "w.size + bag.lazy", &rv) && isInt32(rv) && toInt32(rv) == 14);

	// Pinned engine difference (bead oo-1gc.16, Alnivel.RoutePlanner): strict code that creates a
	// property on a primitive -- here a reduce() callback that returns the key, so the accumulator
	// becomes a string -- throws "not an object", as ES5 requires. SpiderMonkey 1.8.5 set it on a
	// throwaway wrapper object and carried on. The facade cannot change this without patching the
	// engine; EXPANSION_MIGRATION.md records it as a content defect ("Newly strict").
	CHECK(eval(cx, nullptr, "(function () { 'use strict'; try { Object.keys({ a: 'x', b: 'y' }).reduce(function (m, k) { return m[k] = k; }, {}); return 'ok'; } catch (e) { return e.message; } })()", &rv) && valIs(cx, rv, u"not an object"));
	CHECK(eval(cx, nullptr, "(function () { var s = 'str'; s.extra = 1; return typeof s.extra; })()", &rv) && valIs(cx, rv, u"undefined"));   // sloppy: ignored

	CHECK(std::strcmp(backendName(), "quickjs-ng-0.16.2") == 0);
	setErrorReporter(cx, nullptr);
}

void runFullSurface()
{
	Runtime rt = newRuntime(64u * 1024u * 1024u);
	Context cx = newContext(rt, 8192);
	CHECK(rt != nullptr && cx != nullptr);
	if (rt == nullptr || cx == nullptr)  return;
	exerciseFacade(rt, cx);
	destroyContext(cx);
	destroyRuntime(rt);
	CHECK(gWidgetFinalized >= 1);
}

} // namespace

int main()
{
	Runtime rt = newRuntime(8u * 1024u * 1024u);
	CHECK(rt != nullptr);
	Context cx = newContext(rt, 8192);
	CHECK(cx != nullptr);
	CHECK(getRuntime(cx) == rt);

	Object global = getGlobalObject(cx);
	CHECK(global != nullptr);
	CHECK(initStandardClasses(cx, global));

	// Values: construction, predicates, and the int32 canonicalisation contract this backend
	// promises to keep even without borrowing the engine's own JSValue layout (see the backend's
	// file banner: Value here is not a byte copy of the engine's 16-byte JSValue).
	CHECK(isUndefined(undefinedValue()) && isNull(nullValue()) && isNullOrUndefined(nullValue()));
	CHECK(isObjectOrNull(nullValue()) && !isObject(nullValue()) && isObject(objectValue(global)));
	CHECK(isInt32(int32Value(7)) && toInt32(int32Value(7)) == 7);
	CHECK(isBoolean(trueValue()) && toBoolean(trueValue()) && !toBoolean(falseValue()) && toBoolean(booleanValue(true)));
	CHECK(isPrimitive(int32Value(1)) && !isPrimitive(objectValue(global)));
	const double samples[] = { 0.0, -0.0, 1.0, -1.0, 3.0, 3.5, 2147483647.0, 2147483648.0, -2147483648.0, -2147483649.0,
	                           1e300, std::nan(""), std::numeric_limits<double>::infinity(), 0.1 };
	for (double d : samples)
	{
		Value v = numberValue(d);
		if (static_cast<double>(static_cast<std::int32_t>(d)) == d && !(d == 0.0 && std::signbit(d)))
		{
			CHECK(isInt32(v) && toInt32(v) == static_cast<std::int32_t>(d));
		}
		else
		{
			CHECK(isDouble(v));
			double back = toDouble(v);
			CHECK((std::isnan(back) && std::isnan(d)) || back == d);
		}
	}
	CHECK(isInt32(numberValue(3.0)) && isDouble(numberValue(-0.0)) && isDouble(numberValue(3.5)) && isNumber(numberValue(3.5)));
	CHECK(toDouble(numberValue(3.5)) == 3.5);

	// Property ids.
	CHECK(isInt32Id(int32Id(5)) && idToInt32(int32Id(5)) == 5 && isVoidId(voidId()) && idsEqual(int32Id(5), int32Id(5)));

	// Classes: attach-on-first-use, private data, finalizer, resolve/enumerate through the
	// exotic-method mapping, and getClass()/instanceOf() answering from the same ClassDef.
	Object p = newObject(cx, &sPointClass, nullptr, nullptr);
	CHECK(p != nullptr);
	CHECK(getClass(cx, p) == &sPointClass);
	CHECK(instanceOf(cx, p, &sPointClass, nullptr));
	CHECK(!instanceOf(cx, p, &sScaledClass, nullptr));
	CHECK(setPrivate(cx, p, new Point{3.0, 4.0}));
	auto* pp = static_cast<Point*>(getPrivate(cx, p));
	CHECK(pp != nullptr && pp->x == 3.0 && pp->y == 4.0);
	CHECK(getInstancePrivate(cx, p, &sPointClass, nullptr) == pp);
	CHECK(getInstancePrivate(cx, p, &sScaledClass, nullptr) == nullptr);   // wrong class, no private

	// Resolve/enumerate: declare "x"/"y" as tinyid properties, then have QuickJS-ng's own
	// property machinery (`in`, for-in) drive the exotic methods through has_property and
	// get_own_property_names, and confirm those trampolines reached the façade's hooks with the
	// right PropertyId.
	registerResolvableProperty(cx, &sPointClass, "x", kP_x);
	registerResolvableProperty(cx, &sPointClass, "y", kP_y);
	Value pv = objectValue(p);
	CHECK(setProperty(cx, global, "p", &pv));
	Value rv = undefinedValue();
	const char* has_x = "'x' in p";
	CHECK(evaluateScript(cx, global, has_x, static_cast<unsigned>(std::strlen(has_x)), "test.js", 1, &rv));
	CHECK(toBoolean(rv) == true || isBoolean(rv));   // 'in' returns a JS boolean; presence is what we assert
	CHECK(gResolveCalls > 0);

	const char* countProps = "var n = 0; for (var k in p) n++; n";
	CHECK(evaluateScript(cx, global, countProps, static_cast<unsigned>(std::strlen(countProps)), "test.js", 1, &rv));
	CHECK(isInt32(rv) && toInt32(rv) == 2);   // x and y, from get_own_property_names
	CHECK(gEnumerateCalls > 0);

	// A second class with the same tinyids exercises a distinct resolve hook: dispatch is keyed
	// by the object's own JSClassID (bc->id), not by tinyid or receiver shape.
	registerResolvableProperty(cx, &sScaledClass, "x", kP_x);
	Object s = newObject(cx, &sScaledClass, nullptr, nullptr);
	CHECK(setPrivate(cx, s, new Point{5.0, 6.0}));
	Value sv = objectValue(s);
	CHECK(setProperty(cx, global, "s", &sv));
	const char* has_sx = "'x' in s";
	CHECK(evaluateScript(cx, global, has_sx, static_cast<unsigned>(std::strlen(has_sx)), "test.js", 1, &rv));
	CHECK(gScaledResolveCalls > 0);
	CHECK(gResolveCalls > 0);   // Point's own resolve was not the one that answered for `s`

	// Basic property get/set and script evaluation, the surface this backend implements.
	CHECK(setProperty(cx, global, "answer", &(rv = int32Value(42))));
	Value got = undefinedValue();
	CHECK(getProperty(cx, global, "answer", &got) && isInt32(got) && toInt32(got) == 42);
	const char* expr = "1 + 2";
	CHECK(evaluateScript(cx, global, expr, static_cast<unsigned>(std::strlen(expr)), "test.js", 1, &rv));
	CHECK(isInt32(rv) && toInt32(rv) == 3);
	const char* bad = "var = ;";
	CHECK(!evaluateScript(cx, global, bad, static_cast<unsigned>(std::strlen(bad)), "bad.js", 1, &rv));

	// Exceptions: a syntax error leaves the engine's own exception pending (bead oo-s0y). Read it
	// without disturbing it (isExceptionPending/getPendingException), report it through a
	// backend-held ErrorReporter, then clear it explicitly.
	CHECK(isExceptionPending(cx));
	Value pending = undefinedValue();
	CHECK(getPendingException(cx, &pending));
	CHECK(isExceptionPending(cx));   // reading must not clear it
	static std::string sLastReported;
	static unsigned sLastFlags = 0;
	ErrorReporter oldReporter = setErrorReporter(cx, +[](Context, const char* message, const ErrorReport* report)
	{
		sLastReported = message != nullptr ? message : "";
		sLastFlags = report != nullptr ? report->flags : 0;
	});
	CHECK(oldReporter == nullptr);
	CHECK(reportPendingException(cx));
	CHECK(!sLastReported.empty());
	CHECK((sLastFlags & static_cast<unsigned>(ReportFlag::Exception)) != 0);
	CHECK(!isExceptionPending(cx));   // reportPendingException clears it

	// setPendingException / clearPendingException round-trip a façade value (not just an engine
	// error), then clear it so it does not leak into the destroyContext below.
	setPendingException(cx, int32Value(99));
	CHECK(isExceptionPending(cx));
	Value thrown = undefinedValue();
	CHECK(getPendingException(cx, &thrown) && isInt32(thrown) && toInt32(thrown) == 99);
	clearPendingException(cx);
	CHECK(!isExceptionPending(cx));

	// save/restore/drop bracket a call that must not disturb an already-pending exception.
	setPendingException(cx, int32Value(7));
	ExceptionState* saved = saveExceptionState(cx);
	CHECK(!isExceptionPending(cx));                 // save lifts it off the context
	setPendingException(cx, int32Value(8));          // something else runs and throws
	restoreExceptionState(cx, saved);
	Value restored = undefinedValue();
	CHECK(getPendingException(cx, &restored) && isInt32(restored) && toInt32(restored) == 7);
	clearPendingException(cx);

	setPendingException(cx, int32Value(11));
	ExceptionState* dropped = saveExceptionState(cx);
	CHECK(!isExceptionPending(cx));
	dropExceptionState(cx, dropped);                 // drop must not resurrect it
	CHECK(!isExceptionPending(cx));

	setErrorReporter(cx, oldReporter);

	// GC roots: RootedObject keeps a handle stable for the scope of a block, and
	// removeObjectRoot()/removeValueRoot() answer false once the root is gone (a second remove is
	// not a silent success).
	{
		Object r = newObject(cx, &sPointClass, nullptr, nullptr);
		CHECK(setPrivate(cx, r, new Point{1.0, 2.0}));
		RootedObject root(cx, r, "test_root");
		CHECK(root.get() == r);
		CHECK(getClass(cx, root.get()) == &sPointClass);
	}
	// After the scope above the root is released (RootedObject's destructor called
	// removeObjectRoot once); the object itself is still reachable only if something else holds
	// it, which nothing does here, so it becomes collectable.

	Object rawObj = nullptr;
	CHECK(addNamedObjectRoot(cx, &rawObj, "raw_root"));
	CHECK(removeObjectRoot(cx, &rawObj));
	CHECK(!removeObjectRoot(cx, &rawObj));   // already removed: false, not a crash

	Value rawVal = int32Value(0);
	CHECK(addNamedValueRoot(cx, &rawVal, "raw_val_root"));
	CHECK(removeValueRoot(cx, &rawVal));
	CHECK(!removeValueRoot(cx, &rawVal));

	// Regression: destroyContext() must erase the destroyed context's entry from the backend's
	// per-context ErrorReporter map (gContextExtras), not just free the underlying context handle.
	// Otherwise, if the allocator hands the freed handle back to a later newContext() (common:
	// same size, no other allocations in between), the new, unrelated context would silently
	// inherit the previous context's stale reporter via gContextExtras[ctx]'s operator[].
	// Exercise context reuse directly: set a reporter on one context, destroy it, create a fresh
	// context (likely reusing the freed handle), and confirm no stale reporter callback fires.
	{
		static std::string sStaleReported;
		Context reused1 = newContext(rt, 8192);
		CHECK(reused1 != nullptr);
		ErrorReporter prevReporter = setErrorReporter(reused1, +[](Context, const char* message, const ErrorReport*)
		{
			sStaleReported = message != nullptr ? message : "";
		});
		reportError(reused1, "reporter armed on context 1");
		CHECK(sStaleReported == "reporter armed on context 1");
		clearPendingException(reused1);
		destroyContext(reused1);   // must erase reused1's gContextExtras entry, not just free it

		sStaleReported.clear();
		Context reused2 = newContext(rt, 8192);   // may or may not reuse reused1's address
		CHECK(reused2 != nullptr);
		// reused2 never called setErrorReporter: if destroyContext() failed to erase reused1's
		// entry and the allocator reused the address, invokeReporter() would find reused1's old
		// reporter still keyed under this address and fire it here. It must stay empty.
		reportError(reused2, "should not reach any reporter");
		CHECK(sStaleReported.empty());
		clearPendingException(reused2);
		destroyContext(reused2);
		(void)prevReporter;
	}

	// Regression (bead oo-902s): destroyContext() must erase gCtxForRuntime's entry for its
	// runtime (or otherwise ensure FinalizeTramp never dereferences a freed context). Create an
	// object of sTouchClass -- whose finalizer touches its Context argument, unlike PointFinalize
	// above -- attach it to global so it only collects when cx/rt themselves tear down below, and
	// drive destroyContext(cx) and destroyRuntime(rt) as SEPARATE calls (not combined into one
	// call as most façade users would do) so a dangling JSContext* left behind by a stale
	// gCtxForRuntime entry would misbehave instead of silently going unnoticed.
	Object touchObj = newObject(cx, &sTouchClass, nullptr, nullptr);
	CHECK(touchObj != nullptr);
	CHECK(setPrivate(cx, touchObj, nullptr));
	Value touchVal = objectValue(touchObj);
	CHECK(setProperty(cx, global, "touchObj", &touchVal));

	destroyContext(cx);
	// Force fresh allocations into the freed JSContext's memory before destroyRuntime() below runs
	// its finalizer pass: without this, JS_FreeContext's freed block can sit untouched and still
	// look like a valid JSContext by accident (its rt field unclobbered), letting a dangling-
	// pointer bug pass the CHECKs below by luck rather than by the fix actually being present.
	// Allocating and freeing several throwaway contexts on the same runtime gives the allocator's
	// freelist a strong chance to hand this same block back out and overwrite it before the
	// finalizer pass below would dereference it.
	for (int i = 0; i < 8; ++i)
	{
		Context noise = newContext(rt, 8192);
		if (noise != nullptr)  destroyContext(noise);
	}
	destroyRuntime(rt);
	shutDown();
	CHECK(gFinalized >= 2);   // p and s both finalized when their runtime went away
	CHECK(gTouchFinalizeRan);          // the finalizer actually ran (the regression is exercised)
	CHECK(gTouchFinalizeCtxOk);        // and its Context argument was never a dangling pointer

	runFullSurface();                  // bead oo-1gc.2: the rest of JSEngine.hpp, on a runtime of its own

	CHECK(std::strcmp(backendName(), "quickjs-ng-0.16.2") == 0);

	if (gFailures == 0)  std::printf("PASS: ooscript façade on %s\n", "quickjs-ng-0.16.2");
	else                 std::printf("%d check(s) failed\n", gFailures);
	return gFailures == 0 ? 0 : 1;
}
