/*

OORegExpMatcher.cpp


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
#include "oofnd/String.hpp"
#include "oofnd/Thread.hpp"
#include "oofnd/objc/OOAssert.h"

// Pseudo-singleton: a single instance exists at a given time, but can be
// released.
namespace {
static OORegExpMatcher* sActiveInstance;
}  // namespace

oo::Ref<OORegExpMatcher> OORegExpMatcher::regExpMatcher() {
  OOCAssert(oo::thread::isMainThread(),
            "OORegExpMatcher may only be used on the main thread.");

  if (sActiveInstance == nullptr) {
    oo::Ref<OORegExpMatcher> matcher = oo::makeRef<OORegExpMatcher>();
    if (!matcher->init())
      return nullptr;  // [[[self alloc] init] autorelease] was nil
    sActiveInstance = matcher.get();
    return matcher;
  }

  return oo::Ref<OORegExpMatcher>(sActiveInstance);
}

bool OORegExpMatcher::init() {
  const char* argumentNames[2] = {"string", "regexp"};
  unsigned codeLine = __LINE__ + 1;  // NB: should remain line before code.
  const char* code = "return regexp.test(string);";

  OOJavaScriptEngine::sharedEngine();  // Summon the beast from the Pit.

  JSContext* context = OOJSAcquireContext();
  _tester = OOJSFunction::initWithName(
      std::string("matchesRegExp"), JS_UNDEFINED, std::string(code), 2,
      argumentNames, oo::str::lastPathComponent(__FILE__), codeLine, context);

  OOJSRelinquishContext(context);

  if (_tester == nullptr) return false;  // was DESTROY(self)

  return true;
}

OORegExpMatcher::~OORegExpMatcher() {
  if (sActiveInstance == this) sActiveInstance = nullptr;

  _tester = nullptr;
  _cachedRegExpObject = nullptr;
}

bool OORegExpMatcher::string(const std::string& string,
                             const std::string& regExp) {
  return this->string(string, regExp, 0);
}

bool OORegExpMatcher::string(const std::string& string,
                             const std::string& regExp, NSUInteger flags) {
  OOCAssert(oo::thread::isMainThread(),
            "OORegExpMatcher may only be used on the main thread.");

  const std::u16string regExpUnits = oo::utf8ToUtf16(regExp);
  size_t expLength = regExpUnits.size();
  if (EXPECT_NOT(expLength == 0)) return false;

  JSContext* context = OOJSAcquireContext();

  // Create new RegExp object if necessary.
  if (flags != _cachedFlags || _cachedRegExpString != regExp) {
    _cachedRegExpString.reset();
    _cachedRegExpObject = nullptr;

    // QuickJS has no API to create a RegExp directly, so call the RegExp
    // constructor.
    _cachedRegExpString = regExp;
    std::string flagString;
    if (flags & kOORegExpCaseInsensitive) flagString += "i";
    if (flags & kOORegExpMultiLine) flagString += "m";
    JSValue global = JS_GetGlobalObject(context);
    JSValue constructor = JS_GetPropertyStr(context, global, "RegExp");
    JSValue args[2] = {
        JS_NewStringLen(context, regExp.data(), regExp.size()),
        JS_NewStringLen(context, flagString.data(), flagString.size())};
    JSValue regExpObj = JS_CallConstructor(context, constructor, 2, args);
    if (JS_IsException(regExpObj)) {
      OOJSReportPendingException(context);
      regExpObj = JS_NULL;
    }
    _cachedRegExpObject = OOJSValue::valueWithJSValue(regExpObj, context);
    _cachedFlags = flags;

    JS_FreeValue(context, regExpObj);
    JS_FreeValue(context, args[0]);
    JS_FreeValue(context, args[1]);
    JS_FreeValue(context, constructor);
    JS_FreeValue(context, global);
  }

  // The arguments (a JS string; the cached RegExp object), owned while the
  // function runs, and the result converted to a boolean; an uncaught
  // exception, which QuickJS leaves pending, is reported.
  JSValue argv[2];
  argv[0] = OOJSValueFromPList(context, oo::PList(string));
  argv[1] = (_cachedRegExpObject != nullptr)
                ? _cachedRegExpObject->jsValueInContext(context)
                : JSValue{};  // (a message to nil gave the zero value)
  JSValue resultValue = JS_UNDEFINED;
  bool OK = _tester->evaluateWithContext(context, JS_UNDEFINED, 2, argv,
                                         &resultValue);
  int matched = 0;
  if (OK) {
    matched = JS_ToBool(context, resultValue);
    JS_FreeValue(context, resultValue);
    if (matched < 0) OK = false;
  }
  if (!OK && JS_HasException(context)) OOJSReportPendingException(context);
  JS_FreeValue(context, argv[0]);
  JS_FreeValue(context, argv[1]);
  bool result = OK && matched > 0;

  OOJSRelinquishContext(context);

  return result;
}
