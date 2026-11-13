/*	test_OOJSMissionVariables.mm
	Unit tests for the missionVariables JS binding (src/Core/Scripting/OOJSMissionVariables.h/.mm).

	As the other binding tests do, it runs the JS class in a real QuickJS-ng context, and links the
	game's own objects for the binding, the class registration (OOJSClasses.mm), the engine's
	exception translator (OOJSEngineNativeWrappers.mm) and the number-literal test it calls
	(OOIsNumberLiteral.cpp). It stands in for the player (its mission variables, kept in a
	dictionary) and for the engine functions the binding links against, with the engine headers'
	linkage. The tests pin the JS-visible behaviour: the missionVariables object, reading a variable (a number literal
	as a number, any other string as itself, a missing one as null, a name with a leading underscore
	as nothing), writing one (as its string, null clearing it, a bad name an error), delete,
	enumeration (only mission_ keys, in key order), and a native's exception. Run: bash
	tests/run.sh unit
*/

#include "oofnd/objc/OOObject.h"
#include <quickjs.h>
#include "oofnd/objc/OOException.h"
#include "oofnd/PList.hpp"
#include "oofnd/String.hpp"


// MARK: The player, as far as the binding sees it -------------------------------------------------

/*	Mission variables by key ("mission_" + the JS name). Reading "mission_boom" raises, and reading
	"mission_cxxboom" throws a C++ exception, so the test sees what an exception under a native
	becomes.
*/
// PLAYER: the members the code under test calls, declared as the game headers
// declare them (the test imports none that defines the classes), with the
// stand-in's answers.
class ShipEntity;
class PlayerEntity
{
public:
	oo::PList missionVariables();
	oo::PList missionVariableForKey(const std::string &key);
	void setMissionVariable(const oo::PList &value, const std::string &key);
	void setScriptTarget(::ShipEntity *ship);

	oo::PList::Dict _missionVariables;
	int _sets = {};
	int _scriptTargetSets = {};
};


#include "OOJSMissionVariables.h"
#include "OOJSEngineCore.h"

#include "oo_test.hpp"

#include <cstdarg>
#include <cstring>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>


oo::PList PlayerEntity::missionVariables()  { return oo::PList(_missionVariables); }
oo::PList PlayerEntity::missionVariableForKey(const std::string &key)
{
	if (key == "mission_boom")  OORaiseException(OOInvalidArgumentException, "variable %s", "boom");
	if (key == "mission_cxxboom")  throw std::runtime_error("cxx boom");
	auto it = _missionVariables.find(key);
	return it != _missionVariables.end() ? it->second : oo::PList();
}
void PlayerEntity::setMissionVariable(const oo::PList &value, const std::string &key)
{
	_sets++;
	if (value.isNull())  _missionVariables.erase(key);
	else  _missionVariables[key] = value;
}
void PlayerEntity::setScriptTarget(::ShipEntity *target)
{
	(void)target;
	_scriptTargetSets++;
}


// MARK: What the rest of the engine provides ------------------------------------------------------

JSContext *gOOJSMainThreadContext = NULL;	// the engine's

namespace {
JSContext *sContext;
}


void OOJSReportErrorWithArguments(JSContext *context, const char *format, va_list args)
{
	std::string msg = oo::str::vformat(format, args);
	JS_ThrowPlainError(context, "%s", msg.c_str());
}


void OOJSReportError(JSContext *context, const char *format, ...)
{
	va_list args;
	va_start(args, format);
	OOJSReportErrorWithArguments(context, format, args);
	va_end(args);
}


std::optional<std::string> OOStringFromJSValue(JSContext *context, JSValueConst value)
{
	if (JS_IsNull(value) || JS_IsUndefined(value))  return std::nullopt;
	std::size_t length = 0;
	const char *chars = JS_ToCStringLen(context, &length, value);
	if (chars == NULL)
	{
		JS_FreeValue(context, JS_GetException(context));
		return std::nullopt;
	}
	std::string result(chars, length);
	JS_FreeCString(context, chars);
	return result;
}


// As the engine's: the atom's string value.
std::optional<std::string> OOStringFromJSID(JSAtom propID)
{
	JSValue value = JS_AtomToString(sContext, propID);
	std::optional<std::string> result = OOStringFromJSValue(sContext, value);
	JS_FreeValue(sContext, value);
	return result;
}


// What the class registration (OOJSClasses.mm) asks of the engine.
void OOJSReportPendingException(JSContext *context)
{
	JS_FreeValue(context, JS_GetException(context));
}


JSAtom OOJSIDFromString(const std::string &string)
{
	return JS_NewAtom(OOJSAcquireContext(), string.c_str());
}


std::string OOJSEscapedForJavaScriptLiteral(std::string_view string)
{
	return "<" + std::string(string) + ">";
}


// A property list as JavaScript, as far as the binding hands one over: null, a string or a number.
JSValue OOJSValueFromPList(JSContext *context, const oo::PList &plist)
{
	if (const std::string *str = plist.getIf<std::string>())  return JS_NewStringLen(context, str->data(), str->size());
	if (plist.isNumber())  return JS_NewNumber(context, plist.doubleValue());
	return JS_NULL;
}


namespace {
PlayerEntity *sPlayer = nullptr;
std::map<JSClassID, int> sConverters;
}  // namespace

PlayerEntity *gOOPlayer = nullptr;


PlayerEntity *OOPlayerForScripting(void)
{
	sPlayer->setScriptTarget(nullptr);	// in the game the player's Objective-C object; the stand-in only counts
	return sPlayer;
}


void OOJSRegisterObjectConverter(JSClassID classID, OOJSClassConverterCallback)
{
	sConverters[classID]++;
}


int sLimiterPauses = 0;
int sProfileDepth = 0;

void OOJSProfileEnter(OOJSProfileStackFrame *, const char *)  { sProfileDepth++; }
void OOJSProfileExit(OOJSProfileStackFrame *)  { sProfileDepth--; }

void OOJSPauseTimeLimiter(void)  { sLimiterPauses++; }
void OOJSResumeTimeLimiter(void)  { sLimiterPauses--; }


#ifndef NDEBUG
void OOJSUnreachable(const char *function, const char *, unsigned)
{
	std::printf("unreachable reached in %s\n", function);
	abort();
}
#endif


// MARK: The context -------------------------------------------------------------------------------

namespace {

void SetUpContext()
{
	if (sContext != nullptr)  return;
	sContext = JS_NewContext(JS_NewRuntime());
	gOOJSMainThreadContext = sContext;	// the class registration's runtime

	sPlayer = new PlayerEntity;	// kept for the life of the test
	gOOPlayer = sPlayer;
	JSValue global = JS_GetGlobalObject(sContext);
	InitOOJSMissionVariables(sContext, global);
	JS_FreeValue(sContext, global);
}


void ResetVariables()
{
	sPlayer->_missionVariables.clear();
	sPlayer->_missionVariables["mission_count"] = oo::PList("12");
	sPlayer->_missionVariables["mission_fraction"] = oo::PList("-2.5");
	sPlayer->_missionVariables["mission_name"] = oo::PList("Thargoid Plans");
	sPlayer->_missionVariables["mission_spaced"] = oo::PList(" 7 ");
	sPlayer->_missionVariables["instructions"] = oo::PList("not a mission variable");
	sPlayer->_missionVariables["mission_alpha"] = oo::PList("a");
}


// Evaluates src and gives its result as a string ("undefined", "null", ...), or "threw: <message>".
std::string Eval(const char *src)
{
	SetUpContext();
	std::string wrapped = std::string("(function () { try { return String(") + src + "); } catch (e) { return 'threw: ' + (e && e.message !== undefined ? e.message : e); } })()";
	JSValue result = JS_Eval(sContext, wrapped.c_str(), wrapped.size(), "test.js", JS_EVAL_TYPE_GLOBAL);
	if (JS_IsException(result))
	{
		JS_FreeValue(sContext, JS_GetException(sContext));
		return "<evaluation failed>";
	}
	std::string text = OOStringFromJSValue(sContext, result).value_or("<not a string>");
	JS_FreeValue(sContext, result);
	return text;
}


// Eval, and print what came back when it is not what the check expects.
std::string EvalShown(const char *src, const char *expected)
{
	std::string result = Eval(src);
	if (result != expected)  std::printf("    %s\n    gave: %s\n", src, result.c_str());
	return result;
}
#define OO_CHECK_EVAL(src, expected)  OO_CHECK_EQ(EvalShown(src, expected), expected)

}	// namespace


// MARK: Tests -------------------------------------------------------------------------------------

OO_TEST(registration)
{
	SetUpContext();
	OO_CHECK_EVAL("typeof missionVariables", "object");
	// #768 tags no class prototype (plan Notes, "Class tags").
	OO_CHECK_EVAL("String(missionVariables)", "[object Object]");
	OO_CHECK_EVAL("(function () { missionVariables = 5; return typeof missionVariables; })()", "object");	// read-only
#ifndef NDEBUG
	OO_CHECK_EQ(sConverters.size(), static_cast<std::size_t>(1));
#else
	OO_CHECK(sConverters.empty());
#endif
}


OO_TEST(reading)
{
	SetUpContext();
	ResetVariables();
	sPlayer->_scriptTargetSets = 0;
	OO_CHECK_EVAL("typeof missionVariables.count + ':' + missionVariables.count", "number:12");
	OO_CHECK_EVAL("missionVariables.fraction", "-2.5");
	OO_CHECK_EVAL("typeof missionVariables.spaced + ':' + missionVariables.spaced", "number:7");	// spaces allowed
	OO_CHECK_EVAL("typeof missionVariables.name + ':' + missionVariables.name", "string:Thargoid Plans");
	OO_CHECK_EVAL("missionVariables.missing", "null");
	OO_CHECK_EVAL("missionVariables._count", "undefined");	// a leading underscore is not a variable
	OO_CHECK_EVAL("missionVariables['instructions']", "null");	// read as mission_instructions
	OO_CHECK(sPlayer->_scriptTargetSets > 0);
}


OO_TEST(enumeration)
{
	SetUpContext();
	ResetVariables();
	// Only mission_ keys, without the prefix, in key order.
	OO_CHECK_EVAL("Object.keys(missionVariables).join()", "alpha,count,fraction,name,spaced");
	OO_CHECK_EVAL("Object.getOwnPropertyNames(missionVariables).join()", "alpha,count,fraction,name,spaced");
	OO_CHECK_EVAL("(function () { var r = []; for (var k in missionVariables) r.push(k + '=' + missionVariables[k]); return r.join(); })()",
				  "alpha=a,count=12,fraction=-2.5,name=Thargoid Plans,spaced=7");
	sPlayer->_missionVariables.clear();
	OO_CHECK_EVAL("Object.keys(missionVariables).length", "0");
	// The keys are a copy: the loop may change the variables.
	ResetVariables();
	OO_CHECK_EVAL("(function () { var n = 0; for (var k in missionVariables) { missionVariables['z' + k] = 1; n++; } return n; })()", "5");
	OO_CHECK(sPlayer->_missionVariables.count("mission_zalpha") == 1 && sPlayer->_missionVariables.count("mission_zspaced") == 1);
}


OO_TEST(writing)
{
	SetUpContext();
	ResetVariables();
	sPlayer->_sets = 0;
	OO_CHECK_EVAL("(function () { missionVariables.stage = 'two'; return missionVariables.stage; })()", "two");
	OO_CHECK(sPlayer->_missionVariables["mission_stage"] == oo::PList("two"));
	OO_CHECK_EVAL("(function () { missionVariables.stage = 3; return typeof missionVariables.stage; })()", "number");
	OO_CHECK(sPlayer->_missionVariables["mission_stage"] == oo::PList("3"));	// kept as its string
	OO_CHECK_EVAL("(function () { missionVariables.flag = true; return missionVariables.flag; })()", "true");
	OO_CHECK(sPlayer->_missionVariables["mission_flag"] == oo::PList("true"));
	OO_CHECK_EVAL("(function () { missionVariables.stage = null; return missionVariables.stage; })()", "null");
	OO_CHECK(sPlayer->_missionVariables.count("mission_stage") == 0);
	OO_CHECK_EVAL("(function () { missionVariables.flag = undefined; return missionVariables.flag; })()", "null");
	OO_CHECK(sPlayer->_missionVariables.count("mission_flag") == 0);
	OO_CHECK_EQ(sPlayer->_sets, 5);
	OO_CHECK_EVAL("(function () { missionVariables._secret = 1; return 'set'; })()", "threw: Invalid mission variable name \"<_secret>\".");
	OO_CHECK_EQ(sPlayer->_sets, 5);
	OO_CHECK(sPlayer->_missionVariables.count("mission__secret") == 0);
}


OO_TEST(deleting)
{
	SetUpContext();
	ResetVariables();
	sPlayer->_sets = 0;
	// A variable the script has set (which the scripting layer keeps as a property
  // of the object, as test_OOJSManifest.mm sees): delete clears it. (Only
  // variables the object does not report yet: assigning to one it does report
  // is a fault of the backend, not of the binding.)
	OO_CHECK_EVAL("(function () { missionVariables.added = 'x'; return delete missionVariables.added; })()", "true");
	OO_CHECK(sPlayer->_missionVariables.count("mission_added") == 0);
	OO_CHECK_EVAL("missionVariables.added", "null");
	OO_CHECK_EQ(sPlayer->_sets, 2);
	OO_CHECK_EVAL("(function () { missionVariables._name = 'x'; })()", "threw: Invalid mission variable name \"<_name>\".");
	OO_CHECK_EVAL("delete missionVariables._name", "true");	// nothing to clear
	OO_CHECK_EQ(sPlayer->_sets, 2);
}


// A variable the script never touched (loaded from a saved game, or set by a legacy script) has no
// property on the object, only the player's value: delete still clears it, because SpiderMonkey ran
// the class's delProperty hook whether or not the object had an own property of that name.
OO_TEST(deletingAVariableTheScriptNeverSet)
{
	SetUpContext();
	ResetVariables();
	sPlayer->_sets = 0;
	sPlayer->_missionVariables["mission_fromSave"] = oo::PList("loaded");
	OO_CHECK_EVAL("missionVariables.fromSave", "loaded");
	OO_CHECK_EVAL("delete missionVariables.fromSave", "true");
	OO_CHECK(sPlayer->_missionVariables.count("mission_fromSave") == 0);
	OO_CHECK_EVAL("missionVariables.fromSave", "null");
	OO_CHECK_EQ(sPlayer->_sets, 1);
}


// A variable the object already reports (here, after an enumeration listed it)
// is still written through the class's setter, as SpiderMonkey's assignment
// did, and is not shadowed by a read-only property; delete on it then clears
// it.
OO_TEST(overwritingAReportedVariable)
{
	SetUpContext();
	ResetVariables();
	sPlayer->_sets = 0;
	// (Earlier tests leave their own names on the object; what matters is that count is listed.)
	OO_CHECK_EVAL("Object.keys(missionVariables).indexOf('count') >= 0", "true");
	OO_CHECK_EVAL("(function () { missionVariables.count = 5; return missionVariables.count; })()", "5");
	OO_CHECK(sPlayer->_missionVariables["mission_count"] == oo::PList("5"));
	OO_CHECK_EQ(sPlayer->_sets, 1);
	OO_CHECK_EVAL("(function () { var d = Object.getOwnPropertyDescriptor(missionVariables, 'count'); return d.writable + ',' + d.configurable; })()", "true,true");
	// The player's variable is what reads give, not a value frozen on the object.
	sPlayer->_missionVariables["mission_count"] = oo::PList("6");
	OO_CHECK_EVAL("missionVariables.count", "6");
	OO_CHECK_EVAL("(function () { missionVariables.name = 'Plans'; return missionVariables.name; })()", "Plans");
	OO_CHECK(sPlayer->_missionVariables["mission_name"] == oo::PList("Plans"));
	OO_CHECK_EQ(sPlayer->_sets, 2);
	OO_CHECK_EVAL("delete missionVariables.count", "true");
	OO_CHECK(sPlayer->_missionVariables.count("mission_count") == 0);
	OO_CHECK_EVAL("missionVariables.count", "null");
	OO_CHECK_EQ(sPlayer->_sets, 3);
}


OO_TEST(nativeExceptions)
{
	SetUpContext();
	ResetVariables();
	OO_CHECK_EVAL("missionVariables.boom", "threw: Native exception: variable boom");
	OO_CHECK_EVAL("missionVariables.cxxboom", "threw: Native exception: cxx boom");
	OO_CHECK_EVAL("missionVariables.count", "12");
	OO_CHECK_EQ(sLimiterPauses, 0);
	OO_CHECK_EQ(sProfileDepth, 0);
}


OO_TEST_MAIN()
