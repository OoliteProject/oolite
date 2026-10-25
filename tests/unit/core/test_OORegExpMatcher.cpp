/*	test_OORegExpMatcher.mm
	Unit tests for OORegExpMatcher (src/Core/OORegExpMatcher.h): bead oo-ct7c, converted in the
	Phase 3 house style (proposed ADR-0056).

	The matcher compiles a JavaScript function, "return regexp.test(string);", and runs it on a
	RegExp object it caches by pattern and flags. The test links the game's own OORegExpMatcher
	and the ooscript engine (QuickJS), so every match below is the real engine's answer. The
	Objective-C glue the matcher uses but whose files reach the whole game (the engine singleton,
	OOJSFunction, OOJSValue and the two value converters; OOJavaScriptEngine.mm links everything)
	is replaced by the minimal definitions below (OOJSFunction's C++ members since bead oo-9ht.41), which count what the matcher asks of them
	(ADR-0056 amendment 1 item 8, amendment oo-z1s4 item 4). The expectations were written against the Objective-C API and
	run on the unconverted class first: what matches, the flags, the empty pattern, the cache
	(one compiled RegExp per pattern and flags), and the pseudo-singleton (one matcher per
	autorelease pool, a new one after the pool drains; nil, and asked again, when the tester does
	not compile). The C++ tests then pinned the same answers through the C++ matcher, and the
	last test the facade's contract (one facade per matcher, nil stays nil). Bead oo-9ht.12 deleted
	the facade: see the note above the tests.
	Run: bash tools/check-core-tests.sh
*/

#include "OORegExpMatcher.h"
#include "OOJSFunction.h"
#include "OOJSEngineCore.h"	// OOJSValue
#include "oofnd/objc/OOObject.h"

#include "oo_test.hpp"
#include "oofnd/PList.hpp"
#include "oofnd/Encoding.hpp"

#include <string>


// --- Stand-ins for the engine glue (see the banner) ---------------------------------------------

ooscript::Context gOOJSMainThreadContext = nullptr;

namespace {

ooscript::Object sGlobal = nullptr;
unsigned sEngineCalls = 0;		// +OOJavaScriptEngine::sharedEngine()
unsigned sFunctionsMade = 0;	// OOJSFunction inits: one per matcher
unsigned sRegExpsMade = 0;		// OOJSValue inits: one per RegExp the matcher compiled
unsigned sEvaluations = 0;		// OOJSFunction evaluations: one per match
bool sFailCompile = false;		// make the next OOJSFunction init fail, as a compile error does

ooscript::ClassDef sGlobalClass = { "Global", ooscript::ClassFlag::Global, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr, nullptr };

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
		ooscript::Runtime runtime = ooscript::newRuntime(64L * 1024L * 1024L);
		gOOJSMainThreadContext = ooscript::newContext(runtime, 8192);
		ooscript::beginRequest(gOOJSMainThreadContext);
		sGlobal = ooscript::newGlobalObject(gOOJSMainThreadContext, &sGlobalClass);
		ooscript::setGlobalObject(gOOJSMainThreadContext, sGlobal);
		ooscript::initStandardClasses(gOOJSMainThreadContext, sGlobal);
		ooscript::endRequest(gOOJSMainThreadContext);
	}
	return nullptr;
}


// OOJSFunction (src/Core/Scripting/OOJSFunction.h): the members the matcher calls, defined here in
// place of OOJSFunction.mm. Until bead oo-9ht.41 deleted the class's Objective-C facade this was
// an Objective-C stub of the same name; the C++ stand-in does and counts the same.
oo::Ref<OOJSFunction> OOJSFunction::initWithName(const std::optional<std::string> &name, ooscript::Object scope, const std::optional<std::string> &code, NSUInteger argCount, const char **argNames, const std::optional<std::string> &fileName, NSUInteger lineNumber, ooscript::Context context)
{
	sFunctionsMade++;
	if (sFailCompile)  return nullptr;
	const std::u16string units = oo::utf8ToUtf16(code.value_or(std::string()));
	ooscript::Function function = ooscript::compileUCFunction(context, (scope != nullptr) ? scope : sGlobal, name ? name->c_str() : nullptr, static_cast<unsigned>(argCount), argNames, units.data(), units.size(), fileName ? fileName->c_str() : nullptr, static_cast<unsigned>(lineNumber));
	if (function == nullptr)  return nullptr;
	return oo::adopt(new OOJSFunction(function, context));
}


OOJSFunction::OOJSFunction(ooscript::Function function, ooscript::Context context)
{
	_function = function;
	ooscript::addNamedObjectRoot(context, reinterpret_cast<ooscript::Object *>(&_function), "test OOJSFunction");	// a function is its object, as OOJSFunction.mm roots it
}


OOJSFunction::~OOJSFunction()
{
	if (_function != nullptr)  ooscript::removeObjectRoot(gOOJSMainThreadContext, reinterpret_cast<ooscript::Object *>(&_function));
}


bool OOJSFunction::evaluateWithContext(ooscript::Context context, ooscript::Object jsThis, unsigned argc, ooscript::Value *argv, ooscript::Value *result)
{
	sEvaluations++;
	return ooscript::callFunction(context, (jsThis != nullptr) ? jsThis : sGlobal, _function, argc, argv, result);
}


// The held value (OOJSEngineCore.h; a C++ class since bead oo-wdqw1 deleted its facade): the members
// the matcher calls, defined here with the stand-in's answers.
oo::Ref<OOJSValue> OOJSValue::valueWithJSObject(ooscript::Object object, ooscript::Context context)
{
	oo::Ref<OOJSValue> result = oo::makeRef<OOJSValue>();
	sRegExpsMade++;
	result->_val = ooscript::objectValue(object);
	ooscript::addNamedValueRoot(context, &result->_val, "test OOJSValue");
	return result;
}


OOJSValue::~OOJSValue()
{
	ooscript::removeValueRoot(gOOJSMainThreadContext, &_val);
}


ooscript::Value OOJSValue::jsValueInContext(ooscript::Context)  { return _val; }
std::string OOJSValue::className() const  { return "OOJSValue"; }
std::string OOJSValue::description() const  { return "<OOJSValue>"; }


ooscript::Value OOJSValueFromPList(ooscript::Context context, const oo::PList &plist)
{
	const std::string *string = plist.getIf<std::string>();
	if (string == nullptr)  return ooscript::nullValue();
	const std::u16string units = oo::utf8ToUtf16(*string);
	return ooscript::stringValue(ooscript::newUCStringCopyN(context, units.data(), units.size()));
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
	OO_CHECK(Matches("GeForce GTX 1080", "GeForce"));
	OO_CHECK(Matches("GeForce GTX 1080", "^GeForce GTX [0-9]+$"));
	OO_CHECK(!Matches("GeForce GTX 1080", "^GTX"));
	OO_CHECK(!Matches("geforce", "GeForce"));
	OO_CHECK(Matches("geforce", "GeForce", kOORegExpCaseInsensitive));
	OO_CHECK(!Matches("one\ntwo", "^two"));
	OO_CHECK(Matches("one\ntwo", "^two", kOORegExpMultiLine));
	OO_CHECK(Matches("", "^$"));
	OO_CHECK(Matches("caf\xC3\xA9", "\xC3\xA9$"));	// UTF-8 in, UTF-16 units to the engine
	OO_CHECK(OORegExpMatcher::regExpMatcher()->string("abc", "b"));	// flags 0
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
