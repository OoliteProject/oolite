/*	test_OORegExpMatcher.mm
	Unit tests for OORegExpMatcher (src/Core/OORegExpMatcher.h): bead oo-ct7c, converted in the
	Phase 3 house style (proposed ADR-0056).

	The matcher compiles a JavaScript function, "return regexp.test(string);", and runs it on a
	RegExp object it caches by pattern and flags. The test links the game's own OORegExpMatcher
	and the QuickJS-ng engine, so every match below is the real engine's answer. The
	Objective-C glue the matcher uses but whose files reach the whole game (the engine singleton,
	OOJSFunction, OOJSValue, the two value converters and the exception reporter;
	OOJavaScriptEngine.mm links everything)
	is replaced by the minimal definitions below (OOJSFunction's C++ members), which count what the matcher asks of them
	(ADR-0056 amendment 1 item 8, amendment oo-z1s4 item 4). The expectations were written against the Objective-C API and
	run on the unconverted class first: what matches, the flags, the empty pattern, the cache
	(one compiled RegExp per pattern and flags), and the pseudo-singleton (one matcher per
	autorelease pool, a new one after the pool drains; nil, and asked again, when the tester does
	not compile). The C++ tests then pinned the same answers through the C++ matcher, and the
	last test the facade's contract (one facade per matcher, nil stays nil). Bead oo-9ht.12 deleted
	the facade: see the note above the tests.
	Run: bash tools/check-core-tests.sh
*/

#import "OORegExpMatcher.h"
#import "OOJSFunction.h"
#include "OOJSEngineCore.h"	// OOJSValue
#import "oofnd/objc/OOObject.h"

#include "oo_test.hpp"
#include "oofnd/PList.hpp"

#include <quickjs.h>

#include <string>


// --- Stand-ins for the engine glue (see the banner) ---------------------------------------------

JSContext *gOOJSMainThreadContext = nullptr;

namespace {

JSValue sGlobal = JS_UNDEFINED;	// owned, for the life of the process
unsigned sEngineCalls = 0;		// +OOJavaScriptEngine::sharedEngine()
unsigned sFunctionsMade = 0;	// OOJSFunction inits: one per matcher
unsigned sRegExpsMade = 0;		// OOJSValue inits: one per RegExp the matcher compiled
unsigned sEvaluations = 0;		// OOJSFunction evaluations: one per match
bool sFailCompile = false;		// make the next OOJSFunction init fail, as a compile error does

}	// namespace


// The engine (OOJavaScriptEngine.h; a C++ class since bead oo-wdqw1 deleted its facade), declared
// with the header's names and signatures but not its class; the stand-in's answers are kept.
class OOJavaScriptEngine
{
public:
	static OOJavaScriptEngine *sharedEngine();
};


OOJavaScriptEngine *OOJavaScriptEngine::sharedEngine()
{
	sEngineCalls++;
	if (gOOJSMainThreadContext == nullptr)
	{
		JSRuntime *runtime = JS_NewRuntime();
		JS_SetMemoryLimit(runtime, 64L * 1024L * 1024L);
		gOOJSMainThreadContext = JS_NewContext(runtime);
		sGlobal = JS_GetGlobalObject(gOOJSMainThreadContext);
	}
	return nullptr;
}


// OOJSFunction (src/Core/Scripting/OOJSFunction.h): the members the matcher calls, defined here in
// place of OOJSFunction.mm. Until the class's Objective-C facade was deleted this was an
// Objective-C stub of the same name; the C++ stand-in does and counts the same. The function is
// compiled as a function expression in the global scope, as OOJSFunction.mm does.
oo::Ref<OOJSFunction> OOJSFunction::initWithName(const std::optional<std::string> &name, JSValueConst scope, const std::optional<std::string> &code, NSUInteger argCount, const char **argNames, const std::optional<std::string> &fileName, NSUInteger lineNumber, JSContext *context)
{
	(void)scope;
	(void)lineNumber;
	sFunctionsMade++;
	if (sFailCompile)  return nullptr;
	std::string source = "(function " + name.value_or(std::string()) + "(";
	for (NSUInteger i = 0; i < argCount; i++)  source += std::string(i != 0 ? "," : "") + argNames[i];
	source += ") {\n" + code.value_or(std::string()) + "\n})";
	JSValue function = JS_Eval(context, source.c_str(), source.size(), fileName ? fileName->c_str() : "<test>", JS_EVAL_TYPE_GLOBAL);
	if (JS_IsException(function))
	{
		JS_FreeValue(context, JS_GetException(context));
		return nullptr;
	}
	oo::Ref<OOJSFunction> result = oo::adopt(new OOJSFunction(function, context));
	JS_FreeValue(context, function);
	return result;
}


OOJSFunction::OOJSFunction(JSValueConst function, JSContext *context)
{
	_function = JS_DupValue(context, function);	// its own reference
}


OOJSFunction::~OOJSFunction()
{
	JS_FreeValue(gOOJSMainThreadContext, _function);
}


bool OOJSFunction::evaluateWithContext(JSContext *context, JSValueConst jsThis, int argc, JSValueConst *argv, JSValue *result)
{
	sEvaluations++;
	JSValue rval = JS_Call(context, _function, JS_IsObject(jsThis) ? jsThis : sGlobal, argc, argv);
	if (JS_IsException(rval))
	{
		*result = JS_UNDEFINED;
		return NO;	// the exception is left pending
	}
	*result = rval;
	return YES;
}


// The held value (OOJSEngineCore.h; a C++ class since bead oo-wdqw1 deleted its facade): the members
// the matcher calls, defined here with the stand-in's answers.
oo::Ref<OOJSValue> OOJSValue::valueWithJSValue(JSValueConst value, JSContext *context)
{
	oo::Ref<OOJSValue> result = oo::makeRef<OOJSValue>();
	sRegExpsMade++;
	result->_val = JS_DupValue(context, value);	// owned
	return result;
}


OOJSValue::~OOJSValue()
{
	JS_FreeValue(gOOJSMainThreadContext, _val);
}


// Owned, as the engine's.
JSValue OOJSValue::jsValueInContext(JSContext *context)  { return JS_DupValue(context, _val); }
std::string OOJSValue::className() const  { return "OOJSValue"; }
std::string OOJSValue::description() const  { return "<OOJSValue>"; }


// Owned, as the engine's.
JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	const std::string *string = plist.getIf<std::string>();
	if (string == nullptr)  return JS_NULL;
	return JS_NewStringLen(context, string->data(), string->size());
}


// The engine's reporter: the stand-in clears the exception.
void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
}


// --- The tests ------------------------------------------------------------------------------------
// Bead oo-9ht.12 deleted the facade. The cases that asked through its selectors ask the C++ matcher
// with the same expectations; the facade's own contract (facadeContract) and its autorelease-pool
// lifetime (oneMatcherPerAutoreleasePool) were retired with it (ADR-0049, standing approval
// oo-9n5p9). The C++ lifetime is cxxOneMatcherWhileHeld's; matchersHeldAcrossMatches pins what the
// pool gave a caller that holds its matcher.

namespace {

bool Matches(const std::string &string, const std::string &regExp, NSUInteger flags = 0)
{
	oo::Ref<OORegExpMatcher> matcher = OORegExpMatcher::regExpMatcher();
	return matcher != nullptr && matcher->string(string, regExp, flags);
}

}	// namespace


OO_TEST(matches)
{
	@autoreleasepool
	{
		OO_CHECK(Matches("GeForce GTX 1080", "GeForce"));
		OO_CHECK(Matches("GeForce GTX 1080", "^GeForce GTX [0-9]+$"));
		OO_CHECK(!Matches("GeForce GTX 1080", "^GTX"));
		OO_CHECK(!Matches("geforce", "GeForce"));
		OO_CHECK(Matches("geforce", "GeForce", kOORegExpCaseInsensitive));
		OO_CHECK(!Matches("one\ntwo", "^two"));
		OO_CHECK(Matches("one\ntwo", "^two", kOORegExpMultiLine));
		OO_CHECK(Matches("", "^$"));
		OO_CHECK(Matches("caf\xC3\xA9", "\xC3\xA9$"));	// UTF-8 in, and UTF-8 to the engine
		OO_CHECK(OORegExpMatcher::regExpMatcher()->string("abc", "b"));	// flags 0
	}
}


OO_TEST(emptyPatternMatchesNothing)
{
	unsigned evaluations = sEvaluations;
	OO_CHECK(!Matches("abc", ""));
	OO_CHECK(!Matches("", ""));
	OO_CHECK(sEvaluations == evaluations);	// returned before running anything
}


OO_TEST(regExpIsCachedByPatternAndFlags)
{
	oo::Ref<OORegExpMatcher> matcher = OORegExpMatcher::regExpMatcher();
	unsigned made = sRegExpsMade;
	OO_CHECK(matcher->string("abc", "c$", 0));
	OO_CHECK(sRegExpsMade == made + 1);
	OO_CHECK(!matcher->string("abd", "c$", 0));
	OO_CHECK(sRegExpsMade == made + 1);		// same pattern and flags: cached
	OO_CHECK(matcher->string("ABC", "c$", kOORegExpCaseInsensitive));
	OO_CHECK(sRegExpsMade == made + 2);		// new flags
	OO_CHECK(matcher->string("ABD", "d$", kOORegExpCaseInsensitive));
	OO_CHECK(sRegExpsMade == made + 3);		// new pattern
	OO_CHECK(matcher->string("abd", "d$", 0));
	OO_CHECK(sRegExpsMade == made + 4);
}


OO_TEST(matchersHeldAcrossMatches)
{
	unsigned made = sFunctionsMade;
	unsigned engineCalls = sEngineCalls;
	{
		oo::Ref<OORegExpMatcher> first = OORegExpMatcher::regExpMatcher();
		OO_CHECK(first != nullptr);
		OO_CHECK(OORegExpMatcher::regExpMatcher() == first);
		OO_CHECK(Matches("x", "x"));
		OO_CHECK(sFunctionsMade == made + 1);	// one tester compiled for the held matcher
		OO_CHECK(sEngineCalls == engineCalls + 1);	// the engine summoned once, by init()
	}
	{
		OO_CHECK(OORegExpMatcher::regExpMatcher() != nullptr);
		OO_CHECK(sFunctionsMade == made + 2);	// the first matcher went with its last Ref
	}
}


OO_TEST(failedInitGivesNilAndRetries)
{
	sFailCompile = true;
	OO_CHECK(OORegExpMatcher::regExpMatcher() == nullptr);
	sFailCompile = false;
	OO_CHECK(OORegExpMatcher::regExpMatcher() != nullptr);	// nothing was kept: asked again
	OO_CHECK(Matches("abc", "b"));
}


OO_TEST(cxxMatches)
{
	oo::Ref<OORegExpMatcher> matcher = OORegExpMatcher::regExpMatcher();
	OO_CHECK(matcher != nullptr);
	OO_CHECK(matcher->string("GeForce GTX 1080", "^GeForce GTX [0-9]+$"));
	OO_CHECK(!matcher->string("geforce", "GeForce"));
	OO_CHECK(matcher->string("geforce", "GeForce", kOORegExpCaseInsensitive));
	OO_CHECK(matcher->string("one\ntwo", "^two", kOORegExpMultiLine));
	OO_CHECK(!matcher->string("abc", ""));
}


OO_TEST(cxxOneMatcherWhileHeld)
{
	unsigned made = sFunctionsMade;
	{
		oo::Ref<OORegExpMatcher> first = OORegExpMatcher::regExpMatcher();
		OO_CHECK(OORegExpMatcher::regExpMatcher() == first);
		OO_CHECK(sFunctionsMade == made + 1);
	}
	OO_CHECK(OORegExpMatcher::regExpMatcher() != nullptr);	// the first was freed with its last Ref
	OO_CHECK(sFunctionsMade == made + 2);

	sFailCompile = true;
	OO_CHECK(OORegExpMatcher::regExpMatcher() == nullptr);
	sFailCompile = false;
}


OO_TEST_MAIN()
