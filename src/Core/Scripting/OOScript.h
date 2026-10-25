/*

OOScript.h

Abstract base class for scripts.
Currently, Oolite supports two types of script: the original property list
scripts and JavaScript scripts. OOS, a format that translated into plist
scripts, was supported until 1.69.1, but never used. OOScript unifies the
interfaces to the script types and abstracts loading. Additionally, it falls
back to a more "primitive" script if loading of one type fails; specifically,
the order of precedence is:
	script.js		(JavaScript)
//	script.oos		(OOS)
	script.plist	(property list)

C++20 since bead oo-604l (proposed ADR-0056, Amendment 1 of bead oo-cwz: a hierarchy root, as
amendment oo-6bux's OOJoystickManager). The methods a subclass overrides (name, scriptDescription,
version, requiresTickle, runWithTarget, and the description's components) are virtual. Bead
oo-9ht.133 deleted its Objective-C facade (ADR-0056 amendment oo-9ht.133), the last script facade:
the class is global, a script is held as oo::Ref<OOScript> (weakly as oo::WeakRef), the class
methods that load scripts answer oo::Ref, and what the facade answered for every script is a member
here: -callMethod:... (OOScript (JavaScriptEvents); false but for a JS script), the plist payload
(oo::PListForeign: a script travels in plist data as a PList::Object node) and the JS glue
(OOJSPrivateObject: a JS script's Script object, undefined for any other script, as OOObject
answered).

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#ifndef OOSCRIPT_H
#define OOSCRIPT_H

#include "OOCocoa.h"
#include "oofnd/StdLib.hpp"
#include "oofnd/Ref.hpp"
#include "oofnd/PList.hpp"
#include "OOJSPrivateObject.h"
#include "ooscript/JSEngine.hpp"

#include <optional>
#include <string>
#include <vector>

class Entity;


class OOScript : public oo::PListForeign, public ::OOJSPrivateObject
{
public:
	/*	Looks for path/world-scripts.plist, path/script.js, then path/script.plist.
		May return zero or more scripts; nullopt (was nil) when none could be loaded.
	*/
	static std::optional<std::vector<oo::Ref<OOScript>>> worldScriptsAtPath(const std::string &path);

	//	Load named scripts from Scripts folders. nullopt where these returned nil.
	static std::optional<std::vector<oo::Ref<OOScript>>> scriptsFromFileNamed(const std::string &fileName);
	static std::vector<oo::Ref<OOScript>> scriptsFromList(const std::vector<std::string> &fileNames);

	static std::optional<std::vector<oo::Ref<OOScript>>> scriptsFromFileAtPath(const std::string &filePath);

	//	Load a single JavaScript script (an OOJSScript; null where it answered nil). The properties may hold live objects (oo::PList Object nodes).
	static oo::Ref<OOScript> jsScriptFromFileNamed(const std::string &fileName, const oo::PList &properties);
	//  As above, but load from the "AIs" directory
	static oo::Ref<OOScript> jsAIScriptFromFileNamed(const std::string &fileName, const oo::PList &properties);

	// The subclass responsibilities (Amendment 1 item 2). The root's own answer none, logging an error.
	virtual std::optional<std::string> descriptionComponents();
	virtual std::optional<std::string> name();				// nullopt: none (bead oo-3rb.289.6)
	virtual std::optional<std::string> scriptDescription();	// nullopt: none
	virtual std::optional<std::string> version();			// nullopt: none (bead oo-3rb.291.1)
	virtual bool requiresTickle();
	virtual void runWithTarget(Entity *target);	// the C++ entity (bead oo-w9pi2; was its object)

	std::optional<std::string> displayName();	// flipped with its family (bead oo-3rb.267): "name version" if version is defined, otherwise just "name".

	/*	OOScript (JavaScriptEvents), which every script answered: call a method. For simplicity,
		calling methods on non-JS scripts works but does nothing (false). Requires a request on
		context; outResult may be NULL.
	*/
	virtual bool callMethod(ooscript::PropertyId methodID, ooscript::Context context, ooscript::Value *argv, int argc, ooscript::Value *outResult);

	// oo::PListForeign: the facade's class name, and its -description ("<C++ class address>{components}").
	std::string className() const override;
	std::string description() const override;

	// OOJSPrivateObject: undefined (OOObject's -oo_jsValueInContext:); a JS script answers its Script object.
	ooscript::Value jsValueInContext(ooscript::Context context) override;
	void clearJSSelf(ooscript::Object selfVal) override;
};


/*	[script autorelease], which the deleted facade answered (bead oo-9ht.133): keeps the script
	until the current autorelease pool drains, so a script a holder lets go of (replaced, or the
	holder deallocated) or a caller does not keep lives exactly as long as its autoreleased object
	did. Nothing for null.
*/
void OOScriptAutorelease(oo::Ref<OOScript> script);


/*	A script carried through plist data as a PList::Object node (proposed ADR-0043 Amendment 2), as
	oo::PListObject() and oo::ObjectIn() carried the facade (bead oo-9ht.133).
*/
inline oo::PList OOScriptObjectNode(OOScript *script)	// null script -> null PList
{
	if (script == nullptr)  return oo::PList();
	return oo::PList(oo::PList::Object(oo::Ref<oo::PListForeign>(script)));
}

inline OOScript *OOScriptInObjectNode(const oo::PList &plist)	// null for any other node
{
	const oo::PList::Object *node = plist.getIf<oo::PList::Object>();
	return (node != nullptr) ? dynamic_cast<OOScript *>(node->get()) : nullptr;
}

#endif	// OOSCRIPT_H
