/*

OORegExpMatcher.mm


Copyright (C) 2010-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#include "OORegExpMatcher.h"
#include "OOJSFunction.h"
#include "OOJavaScriptEngine.h"

#include "ooscript/JSEngine.hpp"
#include "oofnd/Thread.hpp"
#include "oofnd/objc/OOAssert.h"
#include "oofnd/String.hpp"

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) the way OOJSVector.mm was (bead oo-sdz):
	the one directly-spelled engine call this file made — compiling a RegExp object from a
	cached UTF-16 pattern — now goes through the façade's own regexp entry point, engine
	still underneath. Everything else here (OOJSAcquireContext, OOJSRelinquishContext,
	OOJSValue, OOJSFunction) already spoke the façade's older OOJS_* naming and is unchanged.
	A tiny local reinterpret_cast, the same shape as OOJSVector.mm's OOJSFCX/OOJSROBJ, recovers
	the plain engine-context and engine-object pointer locals so the rest of the function body is
	byte for byte what it was.
*/

namespace ooscript { }
using ooscript::Context;
using ooscript::Object;



// Pseudo-singleton: a single instance exists at a given time, but can be released.
namespace {
static OORegExpMatcher *sActiveInstance;
} // namespace


oo::Ref<OORegExpMatcher> OORegExpMatcher::regExpMatcher()
{
	OOCAssert(oo::thread::isMainThread(), "OORegExpMatcher may only be used on the main thread.");
	
	if (sActiveInstance == nullptr)
	{
		oo::Ref<OORegExpMatcher> matcher = oo::makeRef<OORegExpMatcher>();
		if (!matcher->init())  return nullptr;	// [[[self alloc] init] autorelease] was nil
		sActiveInstance = matcher.get();
		return matcher;
	}
	
	return oo::Ref<OORegExpMatcher>(sActiveInstance);
}


bool OORegExpMatcher::init()
{
	const char *argumentNames[2] = { "string", "regexp" };
	unsigned codeLine = __LINE__ + 1;	// NB: should remain line before code.
	const char *code = "return regexp.test(string);";
	
	OOJavaScriptEngine::sharedEngine();	// Summon the beast from the Pit.
	
	ooscript::Context context = OOJSAcquireContext();
	_tester = OOJSFunction::initWithName(std::string("matchesRegExp"),
										 NULL,
										 std::string(code),
										 2,
										 argumentNames,
										 oo::str::lastPathComponent(__FILE__),
										 codeLine,
										 context);
	
	OOJSRelinquishContext(context);
	
	if (_tester == nullptr)  return false;	// was DESTROY(self)
	
	return true;
}


OORegExpMatcher::~OORegExpMatcher()
{
	if (sActiveInstance == this)  sActiveInstance = nullptr;
	
	_tester = nullptr;
	_cachedRegExpObject = nullptr;
}


bool OORegExpMatcher::string(const std::string &string, const std::string &regExp)
{
	return this->string(string, regExp, 0);
}


bool OORegExpMatcher::string(const std::string &string, const std::string &regExp, NSUInteger flags)
{
	OOCAssert(oo::thread::isMainThread(), "OORegExpMatcher may only be used on the main thread.");

	const std::u16string regExpUnits = oo::utf8ToUtf16(regExp);
	size_t expLength = regExpUnits.size();
	if (EXPECT_NOT(expLength == 0))  return false;
	
	ooscript::Context context = OOJSAcquireContext();
	
	// Create new RegExp object if necessary.
	if (flags != _cachedFlags || _cachedRegExpString != regExp)
	{
		_cachedRegExpString.reset();
		_cachedRegExpObject = nullptr;
		
		uint16_t *buffer;
		buffer = static_cast<uint16_t *>(malloc(expLength * sizeof *buffer));
		if (EXPECT_NOT(buffer == NULL))  return false;
		std::copy(regExpUnits.begin(), regExpUnits.end(), buffer);
		
		_cachedRegExpString = regExp;
		Object regExpFacadeObj = ooscript::newUCRegExpObjectNoStatics((context), reinterpret_cast<const ooscript::Char16 *>(buffer), expLength, static_cast<std::uint32_t>(flags));
		ooscript::Object regExpObj = (regExpFacadeObj);
		_cachedRegExpObject = OOJSValue::valueWithJSObject(regExpObj, context);
		_cachedFlags = flags;
		
		free(buffer);
	}
	
	// The arguments converted as -evaluatePredicateWithContext:scope:arguments: converted them (a JS
	// string, as the string's Objective-C string gave; the cached RegExp object), rooted while the
	// function runs, and the result converted to a boolean as it did.
	ooscript::Value argv[2];
	argv[0] = OOJSValueFromPList(context, oo::PList(string));
	OOJSAddGCValueRoot(context, &argv[0], "OORegExpMatcher argv");
	argv[1] = (_cachedRegExpObject != nullptr) ? _cachedRegExpObject->jsValueInContext(context) : ooscript::Value{0};
	OOJSAddGCValueRoot(context, &argv[1], "OORegExpMatcher argv");
	ooscript::Value resultValue;
	bool OK = _tester->evaluateWithContext(context, NULL, 2, argv, &resultValue);
	bool matched = false;
	if (OK)  OK = ooscript::valueToBoolean(context, resultValue, &matched);
	ooscript::removeValueRoot(context, &argv[0]);
	ooscript::removeValueRoot(context, &argv[1]);
	bool result = OK && matched;
	
	OOJSRelinquishContext(context);
	
	return result;
}
