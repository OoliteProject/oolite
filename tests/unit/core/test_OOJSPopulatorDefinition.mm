/*	test_OOJSPopulatorDefinition.mm
	Unit tests for OOJSPopulatorDefinition (src/Core/Scripting/OOJSPopulatorDefinition.h/.mm):
	bead oo-1h0h, a Phase 3 conversion in the house style of the OOColor exemplar (proposed
	ADR-0056; amendment oo-o89, as its superclass OOWeakRefObject is still Objective-C).

	A populator definition keeps a JS callback and its `this` alive (owned references) for the system
	populator, remembers the script that made it, and runs the callback with a location. The test
	runs it in a real QuickJS-ng context and
	links the game's own objects for the class and its superclass (OOWeakReference.mm and its
	bridge). What the rest of the engine would provide is defined below as the smallest stand-in
	that does the same thing: the engine object (which calls the function), the script stack
	(OOJSScript) and Vector3D (a plain array here). The engine's and OOJSScript's headers are not
	imported, because the test defines those classes (amendment oo-z1s4 item 4); the class's header
	names OOJSScript with @class for that (amendment oo-fg7i item 5). The expectations were written
	against the Objective-C class and run on it first (they now run through the facade, its
	forwarding test; the facade's own contract is checked last); they pin the initial state, the callback
	and its `this` (kept alive across a garbage collection), the run (its `this`, its location, the
	owning script pushed and popped), an engine reset, and the weak reference to a definition.
	Run: bash tools/check-core-tests.sh
*/

#import "OOJSPopulatorDefinition.h"
#import "OOWeakReference.h"
#import "OODescription.h"
#include "oofnd/Notification.hpp"
#include "oofnd/String.hpp"

#include "oo_test.hpp"

#include <quickjs.h>

#include <cstring>
#include <string>
#include <vector>


// MARK: What the rest of the engine provides ------------------------------------------------------

namespace {
std::vector<id> sPushed;
int sScriptDepth = 0;
int sCalls = 0;
} // namespace

JSContext *gOOJSMainThreadContext = nullptr;
extern const char * const kOOJavaScriptEngineWillResetNotificationName;
const char * const kOOJavaScriptEngineWillResetNotificationName = "org.aegidian.oolite OOJavaScriptEngine will reset";


// A vector is the array [x, y, z] here: enough to see what the definition hands over.
bool VectorToJSValue(JSContext *context, Vector vector, JSValue *outValue)
{
	JSValue array = JS_NewArray(context);
	if (JS_IsException(array))  return false;
	JS_SetPropertyUint32(context, array, 0, JS_NewFloat64(context, vector.x));
	JS_SetPropertyUint32(context, array, 1, JS_NewFloat64(context, vector.y));
	JS_SetPropertyUint32(context, array, 2, JS_NewFloat64(context, vector.z));
	*outValue = array;
	return true;
}


@interface OOJavaScriptEngine: OOObject
+ (OOJavaScriptEngine *) sharedEngine;
- (BOOL) callJSFunction:(JSValueConst)function forObject:(JSValueConst)jsThis argc:(int)argc argv:(JSValueConst *)argv result:(JSValue *)outResult;
@end

@implementation OOJavaScriptEngine

+ (OOJavaScriptEngine *) sharedEngine
{
	static OOJavaScriptEngine *engine = nil;
	if (engine == nil)  engine = [[OOJavaScriptEngine alloc] init];
	return engine;
}


// As the engine's: the call, its result owned by the caller, and an exception reported (here,
// dropped) and cleared.
- (BOOL) callJSFunction:(JSValueConst)function forObject:(JSValueConst)jsThis argc:(int)argc argv:(JSValueConst *)argv result:(JSValue *)outResult
{
	sCalls++;
	JSContext *context = gOOJSMainThreadContext;
	JSValue result = JS_Call(context, function, jsThis, argc, argv);
	if (JS_IsException(result))
	{
		JS_FreeValue(context, JS_GetException(context));
		if (outResult != NULL)  *outResult = JS_UNDEFINED;
		return NO;
	}
	if (outResult != NULL)  *outResult = result;
	else  JS_FreeValue(context, result);
	return YES;
}

@end


// The script stack: the running script (set by the test) and what was pushed.
@interface OOJSScript: OOWeakRefObject
+ (OOJSScript *) currentlyRunningScript;
+ (void) pushScript:(OOJSScript *)script;
+ (void) popScript:(OOJSScript *)script;
@end

namespace {
OOJSScript *sRunningScript = nil;
} // namespace

@implementation OOJSScript
+ (OOJSScript *) currentlyRunningScript  { return sRunningScript; }
+ (void) pushScript:(OOJSScript *)script  { sPushed.push_back([script weakRefUnderlyingObject]); sScriptDepth++; }
+ (void) popScript:(OOJSScript *)script  { (void)script; sScriptDepth--; }
@end


// MARK: The context -------------------------------------------------------------------------------

namespace {

JSContext *Context()
{
	if (gOOJSMainThreadContext == nullptr)
	{
		JSRuntime *runtime = JS_NewRuntime();
		JS_SetMemoryLimit(runtime, 8u * 1024u * 1024u);
		gOOJSMainThreadContext = JS_NewContext(runtime);
	}
	return gOOJSMainThreadContext;
}


// An owned value, freed when it goes: what Evaluate() gives, so that a value handed to the
// definition has no other reference once the statement ends.
class Owned
{
public:
	explicit Owned(JSValue value): _value(value) {}
	~Owned()  { JS_FreeValue(Context(), _value); }
	Owned(const Owned &) = delete;
	Owned &operator=(const Owned &) = delete;
	operator JSValueConst() const  { return _value; }

private:
	JSValue _value;
};


Owned Evaluate(const char *src)
{
	JSValue result = JS_Eval(Context(), src, std::strlen(src), "test.js", JS_EVAL_TYPE_GLOBAL);
	if (JS_IsException(result))
	{
		JS_FreeValue(Context(), JS_GetException(Context()));
		result = JS_UNDEFINED;
	}
	return Owned(result);
}


std::string String(JSValueConst value)
{
	if (JS_IsNull(value) || JS_IsUndefined(value))  return JS_IsNull(value) ? "null" : "undefined";
	std::size_t length = 0;
	const char *chars = JS_ToCStringLen(Context(), &length, value);
	if (chars == nullptr)  return "<none>";
	std::string result(chars, length);
	JS_FreeCString(Context(), chars);
	return result;
}


// Whether an owned value (what -callback and -callbackThis answer) is undefined, or an object;
// the value is freed.
bool IsUndefined(JSValue value)
{
	bool result = JS_IsUndefined(value);
	JS_FreeValue(Context(), value);
	return result;
}


bool IsObject(JSValue value)
{
	bool result = JS_IsObject(value);
	JS_FreeValue(Context(), value);
	return result;
}


void CollectGarbage()
{
	JS_RunGC(JS_GetRuntime(Context()));
}

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(initialState)
{
	@autoreleasepool
	{
		Context();
		OOJSPopulatorDefinition *definition = [[[OOJSPopulatorDefinition alloc] init] autorelease];
		OO_CHECK(definition != nil);
		OO_CHECK(IsUndefined([definition callback]));
		OO_CHECK(!IsObject([definition callbackThis]));
		OO_CHECK([definition isKindOfClass:[OOWeakRefObject class]]);
		OO_CHECK(oo::DescriptionOf(definition).find("OOJSPopulatorDefinition") != std::string::npos);
	}
}


OO_TEST(runCallback)
{
	@autoreleasepool
	{
		OOJSScript *owner = [[[OOJSScript alloc] init] autorelease];
		sRunningScript = owner;
		OOJSPopulatorDefinition *definition = [[[OOJSPopulatorDefinition alloc] init] autorelease];
		sRunningScript = nil;

		// Neither the function nor `this` has another reference: the definition keeps them alive.
		[definition setCallback:Evaluate("(function (where) { globalThis.ran = this.tag + ':' + where.join(); })")];
		[definition setCallbackThis:Evaluate("({ tag: 'me' })")];
		OO_CHECK(IsObject([definition callback]));
		OO_CHECK(IsObject([definition callbackThis]));
		CollectGarbage();

		sPushed.clear();
		sCalls = 0;
		[definition runPopulatorCallback:make_HPvector(1, 2.5, -3)];
		OO_CHECK_EQ(String(Evaluate("globalThis.ran")), "me:1,2.5,-3");
		OO_CHECK_EQ(sCalls, 1);
		OO_CHECK_EQ(sScriptDepth, 0);
		OO_CHECK(sPushed.size() == 1 && sPushed[0] == owner);	// the script that made it

		// Replacing the callback: the new one runs.
		[definition setCallback:Evaluate("(function () { globalThis.ran = 'second'; })")];
		[definition runPopulatorCallback:make_HPvector(0, 0, 0)];
		OO_CHECK_EQ(String(Evaluate("globalThis.ran")), "second");

		// A definition made with no running script pushes nil.
		OOJSPopulatorDefinition *orphan = [[[OOJSPopulatorDefinition alloc] init] autorelease];
		[orphan setCallback:Evaluate("(function () { globalThis.ran = 'orphan'; })")];
		sPushed.clear();
		[orphan runPopulatorCallback:make_HPvector(0, 0, 0)];
		OO_CHECK_EQ(String(Evaluate("globalThis.ran")), "orphan");
		OO_CHECK(sPushed.size() == 1 && sPushed[0] == nil);
	}
}


OO_TEST(engineReset)
{
	@autoreleasepool
	{
		OOJSPopulatorDefinition *definition = [[[OOJSPopulatorDefinition alloc] init] autorelease];
		[definition setCallback:Evaluate("(function () {})")];
		[definition setCallbackThis:Evaluate("({})")];
		oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, [OOJavaScriptEngine sharedEngine]);
		OO_CHECK(IsUndefined([definition callback]));
		OO_CHECK(!IsObject([definition callbackThis]));
	}
	// A definition that is gone no longer observes: another reset is harmless.
	oo::NotificationCenter::defaultCenter().post(kOOJavaScriptEngineWillResetNotificationName, [OOJavaScriptEngine sharedEngine]);
	OO_CHECK(true);
}


OO_TEST(weakReference)
{
	id reference = nil;
	@autoreleasepool
	{
		OOJSPopulatorDefinition *definition = [[OOJSPopulatorDefinition alloc] init];
		reference = [definition weakRetain];
		OO_CHECK([reference weakRefUnderlyingObject] == definition);
		[definition release];
	}
	OO_CHECK([reference weakRefUnderlyingObject] == nil);
	[reference release];
}


OO_TEST(facade)
{
	@autoreleasepool
	{
		OOJSPopulatorDefinition *facade = [[[OOJSPopulatorDefinition alloc] init] autorelease];
		cxx::OOJSPopulatorDefinition *definition = oo::ToCxx(facade);
		OO_CHECK(definition != nullptr);
		OO_CHECK(oo::ToObjC(definition) == facade);
		OO_CHECK(oo::ToCxx(static_cast<OOJSPopulatorDefinition *>(nil)) == nullptr);

		// The facade forwards: what the C++ object holds is what the facade answers.
		definition->setCallback(Evaluate("(function () {})"));
		OO_CHECK(IsObject([facade callback]));
		definition->setCallback(JS_UNDEFINED);
		OO_CHECK(IsUndefined([facade callback]));

		// ToObjC never makes a facade: a C++ definition with none answers nil.
		const oo::Ref<cxx::OOJSPopulatorDefinition> bare = oo::makeRef<cxx::OOJSPopulatorDefinition>();
		OO_CHECK(oo::ToObjC(bare.get()) == nil);
		OO_CHECK(IsUndefined(bare->callback()));
	}
}


OO_TEST_MAIN()
