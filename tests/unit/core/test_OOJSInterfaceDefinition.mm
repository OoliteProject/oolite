/*	test_OOJSInterfaceDefinition.mm
	Unit tests for OOJSInterfaceDefinition (src/Core/Scripting/OOJSInterfaceDefinition.h/.mm):
	bead oo-8fpc, a Phase 3 conversion in the house style of the OOColor exemplar (proposed
	ADR-0056; amendment oo-o89, as its superclass OOWeakRefObject is still Objective-C).

	An interface definition is a station's F4 interface entry made by a script: a title, category
	and summary, and a JS callback and its `this` that it keeps alive (owned references) and runs with the
	entry's key, pushing the script that made it. The test runs it in a real QuickJS-ng context
	and links the game's own objects for the
	class and its superclass (OOWeakReference.mm and its bridge). What the rest of the engine would
	provide is defined below as the smallest stand-in that does the same thing: the engine object
	(which calls the function), the script stack (OOJSScript) and the property-list converter. The
	engine's and OOJSScript's headers are not imported, because the test defines those classes
	(amendment oo-z1s4 item 4); the class's header names OOJSScript with @class for that (amendment
	oo-fg7i item 5). The expectations were written against the Objective-C class and run on it
	first (they now run through the facade, its forwarding test; the facade's own contract is
	checked last); they pin the initial state and the text properties, the callback and its `this` (kept
	alive across a garbage collection), the run, the sort order (-interfaceCompare:, with its nil
	cases), an engine reset, and the weak reference to a definition.
	Run: bash tools/check-core-tests.sh
*/

#import "OOJSInterfaceDefinition.h"
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


// A property list as JS, as far as the definition hands one over: a string.
JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	const std::string *string = plist.getIf<std::string>();
	if (string == nullptr)  return JS_NULL;
	return JS_NewStringLen(context, string->data(), string->size());
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
		OOJSInterfaceDefinition *definition = [[[OOJSInterfaceDefinition alloc] init] autorelease];
		OO_CHECK(definition != nil);
		OO_CHECK(IsUndefined([definition callback]));
		OO_CHECK(!IsObject([definition callbackThis]));
		OO_CHECK([definition isKindOfClass:[OOWeakRefObject class]]);
		OO_CHECK(oo::DescriptionOf(definition).find("OOJSInterfaceDefinition") != std::string::npos);
		OO_CHECK(![definition cxx_title].has_value());
		OO_CHECK(![definition category].has_value());
		OO_CHECK(![definition summary].has_value());
		[definition cxx_setTitle:std::string("Title")];
		[definition setCategory:"Cat"];
		[definition setSummary:"Sum"];
		OO_CHECK_EQ([definition cxx_title].value_or("<none>"), "Title");
		OO_CHECK_EQ([definition category].value_or("<none>"), "Cat");
		OO_CHECK_EQ([definition summary].value_or("<none>"), "Sum");
		[definition cxx_setTitle:std::nullopt];
		OO_CHECK(![definition cxx_title].has_value());
	}
}


OO_TEST(runCallback)
{
	@autoreleasepool
	{
		OOJSScript *owner = [[[OOJSScript alloc] init] autorelease];
		sRunningScript = owner;
		OOJSInterfaceDefinition *definition = [[[OOJSInterfaceDefinition alloc] init] autorelease];
		sRunningScript = nil;

		// Neither the function nor `this` has another reference: the definition keeps them alive.
		[definition setCallback:Evaluate("(function (key) { globalThis.ran = this.tag + ':' + key + ':' + arguments.length; })")];
		[definition setCallbackThis:Evaluate("({ tag: 'me' })")];
		OO_CHECK(IsObject([definition callback]));
		OO_CHECK(IsObject([definition callbackThis]));
		CollectGarbage();

		sPushed.clear();
		sCalls = 0;
		[definition runCallback:"dock"];
		OO_CHECK_EQ(String(Evaluate("globalThis.ran")), "me:dock:1");
		OO_CHECK_EQ(sCalls, 1);
		OO_CHECK_EQ(sScriptDepth, 0);
		OO_CHECK(sPushed.size() == 1 && sPushed[0] == owner);	// the script that made it

		// Replacing the callback and `this`: the new ones run.
		[definition setCallback:Evaluate("(function (key) { globalThis.ran = 'second ' + key + ' ' + (this === globalThis); })")];
		[definition setCallbackThis:JS_UNDEFINED];
		[definition runCallback:"k"];
		OO_CHECK_EQ(String(Evaluate("globalThis.ran")), "second k true");
	}
}


namespace {
OOJSInterfaceDefinition *Interface(std::optional<std::string> category, std::optional<std::string> title)
{
	OOJSInterfaceDefinition *definition = [[[OOJSInterfaceDefinition alloc] init] autorelease];
	if (category.has_value())  [definition setCategory:*category];
	[definition cxx_setTitle:title];
	return definition;
}
} // namespace


OO_TEST(interfaceCompare)
{
	@autoreleasepool
	{
		// By category, then by title, ignoring case.
		OO_CHECK_EQ([Interface("alpha", "z") interfaceCompare:Interface("Beta", "a")], OOOrderedAscending);
		OO_CHECK_EQ([Interface("beta", "a") interfaceCompare:Interface("ALPHA", "z")], OOOrderedDescending);
		OO_CHECK_EQ([Interface("same", "apple") interfaceCompare:Interface("SAME", "Banana")], OOOrderedAscending);
		OO_CHECK_EQ([Interface("same", "Banana") interfaceCompare:Interface("same", "apple")], OOOrderedDescending);
		OO_CHECK_EQ([Interface("same", "x") interfaceCompare:Interface("same", "X")], OOOrderedSame);
		// No category of its own: the same category as anything (a message to nil); then the titles.
		OO_CHECK_EQ([Interface(std::nullopt, "b") interfaceCompare:Interface("cat", "a")], OOOrderedDescending);
		// The other's missing category or title is the empty string.
		OO_CHECK_EQ([Interface("cat", "a") interfaceCompare:Interface(std::nullopt, "a")], OOOrderedDescending);
		OO_CHECK_EQ([Interface("", "a") interfaceCompare:Interface(std::nullopt, std::nullopt)], OOOrderedDescending);
		OO_CHECK_EQ([Interface("", std::nullopt) interfaceCompare:Interface(std::nullopt, "a")], OOOrderedSame);
		// nil: its category and title are missing.
		OO_CHECK_EQ([Interface("cat", "a") interfaceCompare:nil], OOOrderedDescending);
	}
}


OO_TEST(engineReset)
{
	@autoreleasepool
	{
		OOJSInterfaceDefinition *definition = [[[OOJSInterfaceDefinition alloc] init] autorelease];
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
		OOJSInterfaceDefinition *definition = [[OOJSInterfaceDefinition alloc] init];
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
		OOJSInterfaceDefinition *facade = Interface("cat", "title");
		cxx::OOJSInterfaceDefinition *definition = oo::ToCxx(facade);
		OO_CHECK(definition != nullptr);
		OO_CHECK(oo::ToObjC(definition) == facade);
		OO_CHECK(oo::ToCxx(static_cast<OOJSInterfaceDefinition *>(nil)) == nullptr);

		// The facade forwards: what the C++ object holds is what the facade answers.
		OO_CHECK_EQ(definition->category().value_or("<none>"), "cat");
		definition->setSummary("summary");
		OO_CHECK_EQ([facade summary].value_or("<none>"), "summary");
		OO_CHECK_EQ(definition->interfaceCompare(oo::ToCxx(Interface("cat", "Title"))), OOOrderedSame);
		OO_CHECK_EQ(definition->interfaceCompare(nullptr), OOOrderedDescending);

		// ToObjC never makes a facade: a C++ definition with none answers nil.
		const oo::Ref<cxx::OOJSInterfaceDefinition> bare = oo::makeRef<cxx::OOJSInterfaceDefinition>();
		OO_CHECK(oo::ToObjC(bare.get()) == nil);
		OO_CHECK(!bare->title().has_value());
	}
}


OO_TEST_MAIN()
