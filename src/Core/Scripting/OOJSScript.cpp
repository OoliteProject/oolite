/*

OOJSScript.mm

JavaScript support for Oolite
Copyright (C) 2007-2013 David Taylor and Jens Ayton.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#ifndef OO_CACHE_JS_SCRIPTS
#define OO_CACHE_JS_SCRIPTS		1
#endif


#include "OOJSScript.h"
#include "OOJavaScriptEngine.h"
#include "OOJSEngineTimeManagement.h"
#include "oofnd/Notification.hpp"

#include "OOLogging.h"
#include "OOConstToString.h"
#include "Entity.h"
#include "EntityOOJavaScriptExtensions.h"
#include "OOConstToJSString.h"
#include "OOManifestProperties.h"
#include "OOPListParsing.h"
#include "OODebugStandards.h"
#include "oofnd/objc/OOException.h"
#include "oofnd/FileSystem.hpp"
#include "oofnd/Encoding.hpp"
#include "oofnd/objc/OOAssert.h"

#include "ooscript/JSEngine.hpp"
#include "OOJSPrivateObject.h"
#include <cstring>
#include "oofnd/String.hpp"

#if OO_CACHE_JS_SCRIPTS
#include "OOCacheManager.h"
#endif

/*
	Retargeted onto the ooscript façade (JSEngine.hpp) the way OOJSVector.mm does it (bead
	oo-sdz, the sweep exemplar): the class dispatch table becomes a static ooscript::ClassDef
	(the stub hooks are nullptr), the engine's InitClass call becomes ooscript::initClass, and
	the directly spelled engine calls (NewObject, SetPrivate, IsExceptionPending,
	ClearPendingException, ReportPendingException, RemoveObjectRoot, IsInRequest,
	GetMethodById, CallFunctionValue, GetPropertyById, SetPropertyById, StringEqualsAscii) go
	through ooscript:: instead. `this` is renamed to `thisObj` because it is a reserved word
	once this file compiles as Objective-C++ (ADR-0001).

	OOJSAcquireContext, OOJSRelinquishContext, OOJSAddGCObjectRoot, OOJSStartTimeLimiter*,
	OOJSStopTimeLimiter and the OOJS_PROP_* flag macros are OOJS_*-spelled, not directly spelled
	engine calls, so they are untouched and out of scope for this bead (see JSEngine.hpp's own
	header comment and OOJSVector.mm's exemplar comment).

	The class's own defineProperty: method and the compiled-script cache (LoadScriptWithName /
	CompiledScriptData / ScriptWithCompiledData) used to spell out the engine's read-only
	property definition and precompiled-script/XDR calls directly, with no façade equivalent to
	retarget onto. Seam bead oo-1gc.1 (same pattern as oo-whgj for OORegExpMatcher.m/oo-1cl)
	added that equivalent to the façade -- ooscript::definePropertyById, the opaque
	ooscript::Script handle plus compileUCScript/newScriptObject/executeScript/destroyScript,
	and ooscript::serializeScript/deserializeScript wrapping the engine's XDR family (the serialised
	format itself stays backend-private, per ooscript/README.md's "Not in the façade" note) --
	so this rework moves those call sites onto it too, same as everything else in this file.

	toString() (OOJSObjectWrapperToString), the constructor (OOJSUnconstructableConstruct) and
	the finalizer (OOJSObjectWrapperFinalize) are shared natives in OOJavaScriptEngine.mm that
	take the façade signatures directly, so the class tables name them without adapters.
	ScriptAddProperty (the class's addProperty hook, used to warn about the removed tickle()
	handler) is a PropertyGetter in façade terms.
*/

namespace ooscript { }
using ooscript::Context;
using ooscript::Object;
using ooscript::Value;
using ooscript::PropertyId;
using ooscript::CallArgs;
using ooscript::ClassDef;
using ooscript::ClassFlag;
using ooscript::FunctionSpec;
using ooscript::Script;
using ooscript::ByteBuffer;
using ooscript::PropertyFlag;

namespace {
struct RunningStack
{
	RunningStack			*back = nullptr;
	// The running script, held weakly (bead oo-9ht.133: the stack held its Objective-C object, or
	// the weak reference proxy a timer or definition pushed); null for a script-less push.
	oo::WeakRef<OOJSScript>	current;
	bool					scriptless = false;	// pushed with no script, which scriptStack() refuses
};


static ooscript::Object sScriptPrototype;
static RunningStack		*sRunningStack = NULL;


static void AddStackToArrayReversed(std::vector<oo::Ref<OOJSScript>> &array, RunningStack *stack);

static Script LoadScriptWithName(ooscript::Context context, const std::optional<std::string> &path, ooscript::Object object, ooscript::Object *outScriptObject, std::optional<std::string> *outErrorMessage);

#if OO_CACHE_JS_SCRIPTS
static std::optional<oo::Data> CompiledScriptData(ooscript::Context context, Script script);
static Script ScriptWithCompiledData(ooscript::Context context, const oo::Data &data);
#endif

static std::optional<std::string> StrippedName(const std::optional<std::string> &string);

// The value as text (its -description as an object; a string is itself): null stays nullopt.
static std::optional<std::string> DescriptionOrNil(const oo::PList &value);

// -oo_stringForKey: with its nil; a string value for -setObject:forKey:, which raised on nil.
static std::optional<std::string> StringForKey(const oo::PList &dictionary, const std::string &key);
static std::string ValueForKey(const std::optional<std::string> &value, std::string_view key);
} // namespace


namespace {
static bool ScriptAddProperty(Context cx, Object obj, PropertyId propID, Value *value);
static bool ScriptToString(Context context, CallArgs &oojsArgs);
static oo::PList ScriptConverter(ooscript::Context context, ooscript::Object object);


/*	A Script object's private slot (bead oo-9ht.133): a weak reference to its script, as the slot held
	the weak reference proxy the script's facade gave, so the JS object does not keep the script
	alive. The slot retains it once; OOJSCxxObjectWrapperFinalize releases it (it has no JS glue of
	its own: the converter and toString() below ask the script, and answer what a dead reference
	did once it has gone).
*/
class ScriptPrivate final : public oo::RefCounted
{
public:
	explicit ScriptPrivate(OOJSScript *script) : _script(script) {}

	OOJSScript *script() const	{ return _script.get(); }

private:
	oo::WeakRef<OOJSScript> _script;
};


// The script a Script object's slot refers to; null for the prototype or once the script has gone.
static OOJSScript *ScriptOfJSObject(Context context, Object object)
{
	ScriptPrivate *slot = static_cast<ScriptPrivate *>(static_cast<oo::RefCounted *>(ooscript::getPrivate(context, object)));
	return (slot != nullptr) ? slot->script() : nullptr;
}
} // namespace


namespace {
static ClassDef sScriptClass =
{
	"Script",
	ClassFlag::HasPrivate,

	ScriptAddProperty,		// addProperty
	nullptr,				// delProperty (engine default: PropertyStub)
	nullptr,				// getProperty (engine default: PropertyStub)
	nullptr,				// setProperty (engine default: StrictPropertyStub)
	nullptr,				// enumerate (engine default: EnumerateStub)
	nullptr,				// newEnumerate (ooscript::ClassFlag::NewEnumerate not used)
	nullptr,				// resolve (engine default: ResolveStub)
	nullptr,				// convert (engine default: ConvertStub)
	OOJSCxxObjectWrapperFinalize,	// finalize
	nullptr,				// call
	nullptr,				// construct
	nullptr,				// backend: owned by the façade backend, must start null
};
} // namespace


namespace {
static FunctionSpec sScriptMethods[] =
{
	// JS name					Function					min args
	{ "toString",				ScriptToString,				0,			0 },
	{ 0 }
};
} // namespace


// Same flag combination OOJS_PROP_READONLY expands to (ooscript::PropertyFlag::Permanent | ooscript::PropertyFlag::Enumerate |
// ooscript::PropertyFlag::ReadOnly), for the defineProperty:withID:inContext: call site below.
static constexpr PropertyFlag kScriptDefinePropertyFlags = PropertyFlag::Permanent | PropertyFlag::Enumerate | PropertyFlag::ReadOnly;


// +scriptWithPath:properties: (the facade's -initWithPath:properties: after [super init] is
// initWithPath()): a script that cannot be loaded is dropped, which runs the destructor, as
// DESTROY(self) did.
oo::Ref<OOJSScript> OOJSScript::scriptWithPath(const std::optional<std::string> &path, const oo::PList &properties)
{
	oo::Ref<OOJSScript> script = oo::makeRef<OOJSScript>();
	if (!script->initWithPath(path, properties))  return nullptr;
	return script;
}


bool OOJSScript::initWithPath(const std::optional<std::string> &path, const oo::PList &properties)
{
	ooscript::Context context = NULL;
	std::optional<std::string>	problem;	// Acts as error flag.
	Script					script = NULL;
	ooscript::Object scriptObject = NULL;
	ooscript::Value					returnValue = ooscript::undefinedValue();

	{
		context = OOJSAcquireContext();

		if (ooscript::isExceptionPending((context)))
		{
			ooscript::clearPendingException((context));
			OO_LOG_ERR("script.javaScript.load.waitingException", "Prior to loading script {}, there was a pending JavaScript exception, which has been cleared. This is an internal error, please report it.", path.value_or("(null)"));
		}

		// Set up JS object
		if (!problem.has_value())
		{
			_jsSelf = (ooscript::newObject((context), &sScriptClass, (sScriptPrototype), nullptr));
			if (_jsSelf == NULL) problem = "allocation failure";
		}

		if (!problem.has_value() && !OOJSAddGCObjectRoot(context, &_jsSelf, "Script object"))
		{
			problem = "could not add JavaScript root object";
		}

		if (!problem.has_value() && !OOJSAddGCObjectRoot(context, &scriptObject, "Script GC holder"))
		{
			problem = "could not add JavaScript root object";
		}

		if (!problem.has_value())
		{
			// (the slot held the script's weak reference proxy, retained)
			if (!OOJSSetCxxPrivate(context, _jsSelf, oo::makeRef<ScriptPrivate>(this).get()))
			{
				problem = "could not set private backreference";
			}
		}

		// Push self on stack of running scripts.
		RunningStack stackElement =
		{
			.back = sRunningStack,
			.current = oo::WeakRef<OOJSScript>(this)
		};
		sRunningStack = &stackElement;

		_filePath = path;

		if (!problem.has_value())
		{
			OO_LOG("script.javaScript.willLoad", "About to load JavaScript {}", path.value_or("(null)"));
			script = LoadScriptWithName(context, path, _jsSelf, &scriptObject, &problem);
		}
		oo::log::indentIf("script.javaScript.willLoad");

		// Set default properties from manifest.plist
		// Order-sensitive: the properties are set in key order (they were set in hash order).
		const oo::PList::Dict defaultProperties = defaultPropertiesFromPath(path);
		for (const auto &[key, property] : defaultProperties)
		{
			if (key == kLocalManifestProperty)
			{
				// this must not be editable
				defineProperty(property, key);
			}
			else
			{
				// can be overwritten by script itself
				setProperty(property, key);
			}
		}

		// Set properties. (read-only)
		// Order-sensitive: defined in key order (they were defined in hash order).
		if (!problem.has_value() && !properties.isNull())
		{
			if (const oo::PList::Dict *propertyDict = properties.getIf<oo::PList::Dict>())
			{
				for (const auto &[key, property] : *propertyDict)
				{
					defineProperty(property, key);
				}
			}
		}

		/*	Set initial name (in case of script error during initial run).
			The "name" ivar is not set here, so the property can be fetched from JS
			if we fail during setup. However, the "name" ivar is set later so that
			the script object can't be renamed after the initial run. This could
			probably also be achieved by fiddling with JS property attributes.
		*/
		ooscript::PropertyId nameID = OOJSID("name");
		setProperty(oo::PList(scriptNameFromPath(path)), nameID, context);

		// Run the script (allowing it to set up the properties we need, as well as setting up those event handlers)
		if (!problem.has_value())
		{
			OOJSStartTimeLimiterWithTimeLimit(kOOJSLongTimeLimit);
			if (!ooscript::executeScript((context), (_jsSelf), script, (&returnValue)))
			{
				problem = "could not run script";
			}
			OOJSStopTimeLimiter();

			// We don't need the script any more - the event handlers hang around as long as the JS object exists.
			ooscript::destroyScript((context), script);
		}

		ooscript::removeObjectRoot((context), &scriptObject);

		sRunningStack = stackElement.back;

		if (!problem.has_value())
		{
			// Get display attributes from script
			_name.reset();
			_name = StrippedName(DescriptionOrNil(propertyWithID(nameID, context)));
			if (!_name.has_value())
			{
				_name = scriptNameFromPath(path);
				setProperty(oo::PList(*_name), nameID, context);
			}

			_version = DescriptionOrNil(propertyWithID(OOJSID("version"), context));
			_description = DescriptionOrNil(propertyWithID(OOJSID("description"), context));

			OO_LOG("script.javaScript.load.success", "Loaded JavaScript: {} -- {}", displayName().value_or("(null)"), _description.value_or("(no description)"));
		}

		oo::log::outdentIf("script.javaScript.willLoad");

		_filePath.reset();	// Only used for error reporting during startup.
	}

	if (problem.has_value())
	{
		OO_LOG("script.javaScript.load.failed", "***** Error loading JavaScript script {} -- {}", path.value_or("(null)"), *problem);
		ooscript::reportPendingException((context));
		// (was DESTROY(self) here: scriptWithPath() drops the script when this answers false, after
		// the context below is relinquished)
	}

	OOJSRelinquishContext(context);

	if (!problem.has_value())
	{
		oo::NotificationCenter::defaultCenter().addObserver(this, kOOJavaScriptEngineWillResetNotificationName,
															OOJavaScriptEngine::sharedEngine(),
															[this](const oo::Notification &notification) { javaScriptEngineWillReset(notification); });
	}

	return !problem.has_value();
}


OOJSScript::~OOJSScript()
{
	oo::NotificationCenter::defaultCenter().removeObserver(this, kOOJavaScriptEngineWillResetNotificationName,
															OOJavaScriptEngine::sharedEngine());

	if (_jsSelf != NULL)
	{
		ooscript::Context context = OOJSAcquireContext();

		OOJSCxxObjectWrapperFinalize(context, _jsSelf);	// Release weakref to self
		ooscript::removeObjectRoot((context), &_jsSelf);		// Unroot jsSelf

		OOJSRelinquishContext(context);
	}
}


std::optional<std::string> OOJSScript::jsClassName()
{
	return std::string("Script");
}


std::optional<std::string> OOJSScript::descriptionComponents()
{
	if (_jsSelf != NULL)  return OOScript::descriptionComponents();
	else  return "invalid script";
}


void OOJSScript::javaScriptEngineWillReset(const oo::Notification &)
{
	// All scripts become invalid when the JS engine resets.
	if (_jsSelf != NULL)
	{
		_jsSelf = NULL;
		ooscript::Context context = OOJSAcquireContext();
		ooscript::removeObjectRoot((context), &_jsSelf);
		OOJSRelinquishContext(context);
	}
}


OOJSScript *OOJSScript::currentlyRunningScript()
{
	if (sRunningStack == NULL)  return NULL;
	return sRunningStack->current.get();
}


std::vector<oo::Ref<OOJSScript>> OOJSScript::scriptStack()
{
	std::vector<oo::Ref<OOJSScript>>	result;

	AddStackToArrayReversed(result, sRunningStack);
	return result;
}


std::optional<std::string> OOJSScript::name()
{
	// (the property as text: a string is itself, anything else its -description)
	if (!_name.has_value())  _name = DescriptionOrNil(propertyNamed("name"));
	if (!_name.has_value())  return scriptNameFromPath(_filePath);	// Special case for parse errors during load.
	return _name;
}


std::optional<std::string> OOJSScript::scriptDescription()
{
	return _description;
}


std::optional<std::string> OOJSScript::version()
{
	return _version;
}


void OOJSScript::runWithTarget(Entity *)
{

}


bool OOJSScript::callMethod(ooscript::PropertyId methodID,
							ooscript::Context context,
							ooscript::Value *argv, int argc,
							ooscript::Value *outResult)
{
	OOCParameterAssert(_name.has_value() && (argv != NULL || argc == 0) && context != NULL && ooscript::isInRequest((context)));
	if (_jsSelf == NULL)  return false;

	ooscript::Object root = NULL;
	bool					OK = false;
	ooscript::Value					method = ooscript::undefinedValue();
	ooscript::Value					ignoredResult = ooscript::undefinedValue();

	if (outResult == NULL)  outResult = &ignoredResult;
	OOJSAddGCObjectRoot(context, &root, "OOJSScript method root");

	if (EXPECT(ooscript::getMethodById((context), (_jsSelf), (methodID), &root, (&method)) && !ooscript::isUndefined(method)))
	{
#ifndef NDEBUG
		if (ooscript::isExceptionPending((context)))
		{
			OO_LOG("script.internalBug", "Exception pending on context before calling method in {}, clearing. This is an internal error, please report it.", __PRETTY_FUNCTION__);
			ooscript::clearPendingException((context));
		}

		OO_LOG("script.javaScript.call", "Calling [{}].{}()", name().value_or("(null)"), (cxx_OOStringFromJSID(methodID)).value_or("(null)"));
		oo::log::indentIf("script.javaScript.call");
#endif

		// Push self on stack of running scripts.
		RunningStack stackElement =
		{
			.back = sRunningStack,
			.current = oo::WeakRef<OOJSScript>(this)
		};
		sRunningStack = &stackElement;

		// Call the method.
		OOJSStartTimeLimiter();
		OK = ooscript::callFunctionValue((context), (_jsSelf), (method), argc, (argv), (outResult));
		OOJSStopTimeLimiter();

		if (ooscript::isExceptionPending((context)))
		{
			ooscript::reportPendingException((context));
			OK = false;
		}

		// Pop running scripts stack
		sRunningStack = stackElement.back;

#ifndef NDEBUG
		oo::log::outdentIf("script.javaScript.call");
#endif
	}

	ooscript::removeObjectRoot((context), &root);

	return OK;
}


oo::PList OOJSScript::propertyWithID(ooscript::PropertyId propID, ooscript::Context context)
{
	OOCParameterAssert(context != NULL && ooscript::isInRequest((context)));
	if (_jsSelf == NULL)  return oo::PList();

	ooscript::Value jsValue = ooscript::undefinedValue();
	if (ooscript::getPropertyById((context), (_jsSelf), (propID), (&jsValue)))
	{
		return cxx_OOJSPListFromJSValue(context, jsValue);
	}
	return oo::PList();
}


bool OOJSScript::setProperty(const oo::PList &value, ooscript::PropertyId propID, ooscript::Context context)
{
	OOCParameterAssert(context != NULL && ooscript::isInRequest((context)));
	if (_jsSelf == NULL)  return false;

	ooscript::Value jsValue = OOJSValueFromPList(context, value);
	return ooscript::setPropertyById((context), (_jsSelf), (propID), (&jsValue));
}


bool OOJSScript::defineProperty(const oo::PList &value, ooscript::PropertyId propID, ooscript::Context context)
{
	OOCParameterAssert(context != NULL && ooscript::isInRequest((context)));
	if (_jsSelf == NULL)  return false;

	ooscript::Value jsValue = OOJSValueFromPList(context, value);
	return ooscript::definePropertyById((context), (_jsSelf), (propID), (jsValue), nullptr, nullptr, kScriptDefinePropertyFlags);
}


oo::PList OOJSScript::propertyNamed(const std::string &propName)
{
	if (_jsSelf == NULL)  return oo::PList();

	ooscript::Context context = OOJSAcquireContext();
	oo::PList result = propertyWithID(cxx_OOJSIDFromString(propName), context);
	OOJSRelinquishContext(context);

	return result;
}


bool OOJSScript::setProperty(const oo::PList &value, const std::string &propName)
{
	if (value.isNull())  return false;
	if (_jsSelf == NULL)  return false;

	ooscript::Context context = OOJSAcquireContext();
	bool result = setProperty(value, cxx_OOJSIDFromString(propName), context);
	OOJSRelinquishContext(context);

	return result;
}


bool OOJSScript::defineProperty(const oo::PList &value, const std::string &propName)
{
	if (value.isNull())  return false;
	if (_jsSelf == NULL)  return false;

	ooscript::Context context = OOJSAcquireContext();
	bool result = defineProperty(value, cxx_OOJSIDFromString(propName), context);
	OOJSRelinquishContext(context);

	return result;
}


ooscript::Value OOJSScript::jsValueInContext(ooscript::Context)
{
	if (_jsSelf == NULL)  return ooscript::undefinedValue();
	return ooscript::objectValue(_jsSelf);
}


// -cxx_oo_jsDescription (OOObjectJSDescription), which toString() answered: "[Script <components>]".
std::optional<std::string> OOJSScript::jsDescription()
{
	const std::string className = jsClassName().value_or("Script");
	const std::optional<std::string> components = descriptionComponents();
	if (components.has_value())  return oo::str::format("[%s %s]", className.c_str(), components->c_str());
	return oo::str::format("[object %s]", className.c_str());
}


void OOJSScript::pushScript(OOJSScript *script)
{
	RunningStack			*element = new (std::nothrow) RunningStack;
	if (element == NULL)  exit(EXIT_FAILURE);

	element->back = sRunningStack;
	element->current = script;
	element->scriptless = (script == nullptr);
	sRunningStack = element;
}


void OOJSScript::pushScript(const oo::WeakRef<OOJSScript> &script)
{
	RunningStack			*element = new (std::nothrow) RunningStack;
	if (element == NULL)  exit(EXIT_FAILURE);

	element->back = sRunningStack;
	element->current = script;
	sRunningStack = element;
}


void OOJSScript::popScript(OOJSScript *script)
{
	RunningStack			*element = NULL;

	assert(sRunningStack->current.get() == script);
	(void)script;

	element = sRunningStack;
	sRunningStack = sRunningStack->back;
	delete element;
}



/*	Generate default name for script which doesn't set its name property when
	first run.

	The generated name is <name>.anon-script, where <name> is selected as
	follows:
	* If path is nil (futureproofing), use the address of the script object.
	* If the file's name is something other than script.*, use the file name.
	* If the containing directory is something other than Config, use the
	containing directory's name.
	* Otherwise, use the containing directory's parent (which will generally
											be an OXP root directory).
	* If either of the two previous steps results in an empty string, fall
	back on the full path.
*/
std::string OOJSScript::scriptNameFromPath(const std::optional<std::string> &path)
{
	std::string		lastComponent;
	std::string		truncatedPath;
	std::string		theName;

	if (!path.has_value()) theName = oo::str::pointerDescription(this);	// (the script's address, as self's was)
	else
	{
		lastComponent = oo::str::lastPathComponent(*path);
		if (!oo::str::hasPrefix(lastComponent, "script.")) theName = lastComponent;
		else
		{
			truncatedPath = oo::str::deletingLastPathComponent(*path);
			if (0 == oo::str::caseInsensitiveCompare(oo::str::lastPathComponent(truncatedPath), "Config"))
			{
				truncatedPath = oo::str::deletingLastPathComponent(truncatedPath);
			}
			const std::string extension = oo::str::pathExtension(truncatedPath);
			if (0 == oo::str::caseInsensitiveCompare(extension, "oxp"))
			{
				// -stringByDeletingPathExtension: the ".oxp" at the end goes (the path has no trailing
				// separator, having just lost a component).
				truncatedPath.resize(truncatedPath.size() - extension.size() - 1);
			}

			lastComponent = oo::str::lastPathComponent(truncatedPath);
			theName = lastComponent;
		}
	}

	if (theName.empty()) theName = path.value_or("");

	return *StrippedName(theName + ".anon-script");
}


oo::PList::Dict OOJSScript::defaultPropertiesFromPath(const std::optional<std::string> &path)
{
	// remove file name, remove OXP subfolder, add manifest.plist (a nil path messaged nil: no manifest)
	oo::PList manifest = path.has_value() ? cxx_OOPropertyListFromFile(oo::str::appendingPathComponent(oo::str::deletingLastPathComponent(oo::str::deletingLastPathComponent(*path)), "manifest.plist")) : oo::PList();
	if (!manifest.isDict())  manifest = oo::PList();	// a dictionary or nothing, as OODictionaryFromFile answered (its plist.wrongType line, which named the Foundation class, is not kept)
	oo::PList::Dict properties;
	/* __oolite.tmp.* is allocated for OXPs without manifests. Its
	 * values are meaningless and shouldn't be used here */
	const std::optional<std::string> identifier = StringForKey(manifest, std::string(kOOManifestIdentifier));
	if (manifest && !(identifier.has_value() && oo::str::hasPrefix(*identifier, "__oolite.tmp.")))
	{
		if (manifest.get<oo::PList>(std::string(kOOManifestVersion)) != nullptr)
		{
			properties["version"] = ValueForKey(StringForKey(manifest, std::string(kOOManifestVersion)), "version");
		}
		if (manifest.get<oo::PList>(std::string(kOOManifestIdentifier)) != nullptr)
		{
			// used for system info
			properties[kLocalManifestProperty] = ValueForKey(identifier, kLocalManifestProperty);
		}
		if (manifest.get<oo::PList>(std::string(kOOManifestAuthor)) != nullptr)
		{
			properties["author"] = ValueForKey(StringForKey(manifest, std::string(kOOManifestAuthor)), "author");
		}
		if (manifest.get<oo::PList>(std::string(kOOManifestLicense)) != nullptr)
		{
			properties["license"] = ValueForKey(StringForKey(manifest, std::string(kOOManifestLicense)), "license");
		}
	}
	return properties;
}



void InitOOJSScript(ooscript::Context context, ooscript::Object global)
{
	Object proto = ooscript::initClass((context), (global), nullptr, &sScriptClass, OOJSUnconstructableConstruct, 0, nullptr, sScriptMethods, nullptr, nullptr);
	sScriptPrototype = (proto);
	OOJSRegisterObjectConverter(&sScriptClass, ScriptConverter);
}


namespace {
// OOJSBasicPrivateObjectConverter for the slot's weak reference: the script's node, null once it
// has gone (as the dead reference's referent was nil) or for the prototype.
static oo::PList ScriptConverter(ooscript::Context context, ooscript::Object object)
{
	return OOScriptObjectNode(ScriptOfJSObject(context, object));
}


// OOJSObjectWrapperToString for the slot's weak reference, as OOJSCxxObjectWrapperToString answers
// for a slot that is its own glue: the script's jsDescription(), else "[object Script]" (once it
// has gone, as for nil, and for the prototype); a `this` of another class as before.
static bool ScriptToString(Context context, CallArgs &oojsArgs)
{
	OOJS_NATIVE_ENTER(context)

	ooscript::Object thisObj = OOJS_THIS;
	if (thisObj == nullptr || !OOJSIsSubclass(OOJSGetClass(context, thisObj), &sScriptClass))
	{
		return OOJSObjectWrapperToString(context, oojsArgs);
	}

	OOJSScript *script = ScriptOfJSObject(context, thisObj);
	std::optional<std::string> description = (script != nullptr) ? script->jsDescription() : std::nullopt;
	if (!description.has_value())  description = oo::str::format("[object %s]", OOJSGetClass(context, thisObj)->name);

	const std::u16string units = oo::utf8ToUtf16(*description);
	OOJS_RETURN(ooscript::stringValue(ooscript::newUCStringCopyN(context, reinterpret_cast<const ooscript::Char16 *>(units.data()), units.size())));

	OOJS_NATIVE_EXIT
}


static bool ScriptAddProperty(Context cx, Object obj, PropertyId propID, Value * /*value*/)
{
	// Complain about attempts to set the property tickle.
	if (ooscript::isStringId(propID))
	{
		ooscript::Context context = (cx);
		ooscript::Object thisObj = (obj);
		ooscript::String propNameStr = ooscript::idToString(propID);
		bool match = false;
		if (ooscript::stringEqualsAscii(cx, propNameStr, "tickle", &match) && match)
		{
			// A Script object's private slot refers to its script weakly (null once it has gone, or for
			// the prototype: a message to nil).
			OOJSScript *thisScript = ScriptOfJSObject(context, thisObj);
			cxx_OOJSReportWarning(context, "Script %s appears to use the tickle() event handler, which is no longer supported.", ((thisScript != nullptr) ? thisScript->name() : std::nullopt).value_or("(null)").c_str());
		}
	}
	
	return YES;
}
} // namespace


namespace {
static void AddStackToArrayReversed(std::vector<oo::Ref<OOJSScript>> &array, RunningStack *stack)
{
	if (stack != NULL)
	{
		AddStackToArrayReversed(array, stack->back);
		// -addObject: raised on the nil a script-less push leaves (GNUstep 1.31.1's text). A weak
		// push whose script has gone was a dead weak reference proxy, not nil: it is a null entry.
		if (stack->scriptless)  OORaiseException(OOInvalidArgumentException, "Tried to add nil to array");
		array.emplace_back(stack->current.get());
	}
}
} // namespace


namespace {
static Script LoadScriptWithName(ooscript::Context context, const std::optional<std::string> &path, ooscript::Object object, ooscript::Object *outScriptObject, std::optional<std::string> *outErrorMessage)
{
#if OO_CACHE_JS_SCRIPTS
	OOCacheManager				*cache = nullptr;
#endif
	std::optional<std::string>	fileContents;
	std::optional<std::u16string>	data;	// the script's UTF-16 units
	Script						script = NULL;
	
	OOCParameterAssert(outScriptObject != NULL && outErrorMessage != NULL);
	outErrorMessage->reset();
	
#if OO_CACHE_JS_SCRIPTS
	// Look for cached compiled script (a nil path is the key "", as the cache read it)
	cache = OOCacheManager::sharedCache();
	const oo::PList cached = cache->pListForKey(path.value_or(""), "compiled JavaScript scripts");
	if (const oo::Data *cachedData = cached.getIf<oo::PList::Data>())
	{
		script = ScriptWithCompiledData(context, *cachedData);
	}
#endif
	
	if (script == NULL)
	{
		// decodeUnicodeText (it read through .oxz archives)
		if (path.has_value())
		{
			if (const std::optional<oo::Data> bytes = OODataFromOXZFile(*path))  fileContents = oo::str::decodeUnicodeText(bytes->stringView());
		}

		if (fileContents.has_value())
		{
#ifndef NDEBUG
		/* FIXME: this isn't strictly the right test, since strict
		 * mode can be enabled with this string within a function
		 * definition, but it seems unlikely anyone is actually doing
		 * that here. */
		if (fileContents->find("\"use strict\";") == std::string::npos && fileContents->find("'use strict';") == std::string::npos)
		{
			cxx_OOStandardsDeprecated("Script " + path.value_or("(null)") + " does not \"use strict\";");	// "%@" of the path
			if (OOEnforceStandards())
			{
				// prepend it anyway
				// TODO: some time after 1.82, make this required
				fileContents = "\"use strict\";\n" + *fileContents;
			}
		}
#endif
			data = oo::utf8ToUtf16(*fileContents);
		}
		if (!data.has_value())  *outErrorMessage = "could not load file";
		else
		{
			script = ooscript::compileUCScript((context), (object), reinterpret_cast<const ooscript::Char16*>(data->data()), data->size(), path.has_value() ? path->c_str() : NULL, 1);
			if (script != NULL)  *outScriptObject = (ooscript::newScriptObject((context), script));
			else  *outErrorMessage = "compilation failed";
		}
		
#if OO_CACHE_JS_SCRIPTS
		if (script != NULL)
		{
			// Write compiled script to cache
			const std::optional<oo::Data> compiled = CompiledScriptData(context, script);
			cache->setPList((compiled.has_value() ? oo::PList(*compiled) : oo::PList()), path.value_or(""), "compiled JavaScript scripts");	// (null asserts, as nil did)
		}
#endif
	}
	
	return script;
}


#if OO_CACHE_JS_SCRIPTS
static std::optional<oo::Data> CompiledScriptData(ooscript::Context context, Script script)
{
	std::optional<oo::Data>		result;
	ByteBuffer					buffer = { NULL, 0 };
	
	if (ooscript::serializeScript((context), script, &buffer))
	{
		result = oo::Data(buffer.data, buffer.length);
	}
	ooscript::destroyByteBuffer(&buffer);
	
	return result;
}


static Script ScriptWithCompiledData(ooscript::Context context, const oo::Data &data)
{
	std::size_t length = data.length();
	if (EXPECT_NOT(length > UINT32_MAX))  return NULL;
	
	return ooscript::deserializeScript((context), static_cast<const std::uint8_t*>(data.bytes()), length);
}
#endif


// -stringByTrimmingCharactersInSet: of "_", space, tab, LF, CR and VT (all ASCII, so UTF-8 bytes).
static std::optional<std::string> StrippedName(const std::optional<std::string> &string)
{
	if (!string.has_value())  return std::nullopt;
	static constexpr std::string_view kInvalid = "_ \t\n\r\v";
	const std::size_t first = string->find_first_not_of(kInvalid);
	if (first == std::string::npos)  return std::string();
	const std::size_t last = string->find_last_not_of(kInvalid);
	return string->substr(first, last - first + 1);
}


static std::optional<std::string> DescriptionOrNil(const oo::PList &value)
{
	if (value.isNull())  return std::nullopt;
	if (const std::string *string = value.getIf<std::string>())  return *string;	// a string's -description is itself
	// Anything else prints as the object form did (cxx_OOJSPListFromJSValue() is oo::PListFrom() of it).
	return oo::DescriptionOf(value);
}


// -oo_stringForKey: with its nil: the string, a number's -stringValue, or nothing.
static std::optional<std::string> StringForKey(const oo::PList &dictionary, const std::string &key)
{
	const oo::PList *value = dictionary.get<oo::PList>(key);
	if (value == nullptr || !(value->isString() || value->isNumber()))  return std::nullopt;
	return dictionary.get<std::string>(key);
}


// A string value for -setObject:forKey:, which raised on nil (GNUstep 1.31.1's text).
static std::string ValueForKey(const std::optional<std::string> &value, std::string_view key)
{
	if (!value.has_value())  OORaiseException(OOInvalidArgumentException, "Tried to add nil value for key '%s' to dictionary", std::string(key).c_str());
	return *value;
}
} // namespace
