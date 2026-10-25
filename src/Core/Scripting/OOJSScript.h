/*

OOJSScript.h

JavaScript support for Oolite
Copyright (C) 2007-2013 David Taylor and Jens Ayton.

C++20 since bead oo-u61e.4 (proposed ADR-0056, the OOColor house style), a subclass of OOScript
(bead oo-604l). Its Objective-C facade was deleted by bead oo-9ht.137, and the OOScript root's
facade, which was then its object, by bead oo-9ht.133 (ADR-0056 amendment oo-9ht.133): the script's
identity is the C++ object. Holders keep it as oo::Ref (the timers and definitions as oo::WeakRef),
the stack of running scripts holds it weakly, and the Script JS object's private slot holds a weak
reference to it (OOJSPrivateObject glue, amendment oo-6symp), as it held the facade's weak
reference proxy.

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

#ifndef OOJSSCRIPT_H
#define OOJSSCRIPT_H

#include "OOScript.h"
#include "OOJavaScriptEngine.h"
#include "oofnd/Notification.hpp"

// The script property that holds the identifier of the manifest the script was loaded under.
inline constexpr char kLocalManifestProperty[] = "oolite_manifest_identifier";


class OOJSScript : public OOScript
{
public:
	// +scriptWithPath:properties:: a new script, null when it could not be loaded. path nullopt is
	// nil (the script is then named after its address); properties may hold live objects.
	static oo::Ref<OOJSScript> scriptWithPath(const std::optional<std::string> &path, const oo::PList &properties);

	// The old -dealloc's body (the facade's, which ran it as willDealloc() until bead oo-9ht.133).
	~OOJSScript() override;

	// The old -initWithPath:properties: after [super init], run by scriptWithPath(); false: the
	// script could not be loaded, and scriptWithPath() drops it.
	bool initWithPath(const std::optional<std::string> &path, const oo::PList &properties);

	// The running script; null when none runs, for a script-less push, and once a weakly pushed
	// script has gone (a dead weak reference, which answered every message as nil).
	static OOJSScript *currentlyRunningScript();
	// The running scripts, outermost first; an entry is null once a weakly pushed script has gone.
	// Raises, as -addObject: did on nil, if the stack holds a script-less push.
	static std::vector<oo::Ref<OOJSScript>> scriptStack();

	/*	External manipulation of acrtive script stack. Used, for instance, by
		timers. Failing to balance these will crash!
		Passing a nil script is valid for cases where JS is used which is not
		attached to a specific script.
		The weak form is for a holder that keeps its script weakly (it pushed the weak reference
		proxy the script's facade gave it); pop it with its get().
	*/
	static void pushScript(OOJSScript *script);
	static void pushScript(const oo::WeakRef<OOJSScript> &script);
	static void popScript(OOJSScript *script);

	/*	Call a method.
		Requires a request on context.
		outResult may be NULL.
	*/
	bool callMethod(ooscript::PropertyId methodID, ooscript::Context context, ooscript::Value *argv, int argc, ooscript::Value *outResult) override;

	// The property as cxx_OOJSPListFromJSValue() converts it; null when there is no script object or it could not be read.
	oo::PList propertyWithID(ooscript::PropertyId propID, ooscript::Context context);
	// Set a property which can be modified or deleted by the script.
	bool setProperty(const oo::PList &value, ooscript::PropertyId propID, ooscript::Context context);
	// Set a special property which cannot be modified or deleted by the script.
	bool defineProperty(const oo::PList &value, ooscript::PropertyId propID, ooscript::Context context);

	oo::PList propertyNamed(const std::string &name);
	bool setProperty(const oo::PList &value, const std::string &name);
	bool defineProperty(const oo::PList &value, const std::string &name);

	// The JS glue (OOJSPrivateObject; -cxx_oo_jsClassName, -oo_jsValueInContext: and the
	// -cxx_oo_jsDescription toString() answered).
	std::optional<std::string> jsClassName();
	ooscript::Value jsValueInContext(ooscript::Context context) override;
	std::optional<std::string> jsDescription() override;

	// OOScript
	std::optional<std::string> descriptionComponents() override;
	std::optional<std::string> name() override;
	std::optional<std::string> scriptDescription() override;
	std::optional<std::string> version() override;
	void runWithTarget(Entity *target) override;

private:
	void javaScriptEngineWillReset(const oo::Notification &notification);
	std::string scriptNameFromPath(const std::optional<std::string> &path);
	oo::PList::Dict defaultPropertiesFromPath(const std::optional<std::string> &path);

	ooscript::Object			_jsSelf = {};

	std::optional<std::string>	_name;
	std::optional<std::string>	_description;
	std::optional<std::string>	_version;
	std::optional<std::string>	_filePath;
};


OOJS_EXTERN_C void InitOOJSScript(ooscript::Context context, ooscript::Object global);


#endif	// OOJSSCRIPT_H
