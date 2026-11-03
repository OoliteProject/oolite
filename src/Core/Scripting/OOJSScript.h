/*

OOJSScript.h (QuickJS-ng)

JavaScript support for Oolite
Copyright (C) 2007-2013 David Taylor and Jens Ayton.

C++20 since bead oo-u61e.4 (proposed ADR-0056, the OOColor house style). The script is
cxx::OOJSScript, a subclass of cxx::OOScript (bead oo-604l). Its callers are still Objective-C, and
its JS object, the stack of running scripts and the weak references to it all hold the Objective-C
object, so the Objective-C OOJSScript in OOJSScript+ObjCBridge.h (imported at the end of this header)
is its identity: it makes and owns the C++ object, and oo::ToObjC answers it (amendment oo-3kqi).
-initWithPath:properties: hands the script to JS, so its body is initWithPath(), run by the facade
once it is the object's peer (amendment oo-puw9 item 3).

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

#import "OOJavaScriptEngine.h"
#import "OOScript.h"
#include "oofnd/Notification.hpp"

// The script property that holds the identifier of the manifest the script was loaded under.
inline constexpr char kLocalManifestProperty[] = "oolite_manifest_identifier";

@class OOJSScript, OOWeakReference;

namespace cxx {

class OOJSScript : public OOScript {
public:
    // The old -initWithPath:properties: after [super init] (path nullopt is nil: the script is then
    // named after its address; properties may hold live objects). Run by the facade once it is
    // the peer; false: the script could not be loaded, and the facade releases itself.
    bool initWithPath(const std::optional<std::string>& path, const oo::PList& properties);
    // The old -dealloc before [super dealloc], run by the facade's -dealloc.
    void willDealloc();

    static ::OOJSScript* currentlyRunningScript();
    static std::vector<oo::ObjCRef<::OOJSScript*>> scriptStack();

    /*	External manipulation of acrtive script stack. Used, for instance, by
            timers. Failing to balance these will crash!
            Passing a nil script is valid for cases where JS is used which is not
            attached to a specific script.
    */
    static void pushScript(::OOJSScript* script);
    static void popScript(::OOJSScript* script);

    /*	Call a method.
            outResult may be NULL; if not, it is owned by the caller.
    */
    bool callMethod(JSAtom methodID, JSContext* context, JSValueConst* argv, int argc, JSValue* outResult);

    // The property as cxx_OOJSPListFromJSValue() converts it; null when there is no script object or it could not be read.
    oo::PList propertyWithID(JSAtom propID, JSContext* context);
    // Set a property which can be modified or deleted by the script.
    bool setProperty(const oo::PList& value, JSAtom propID, JSContext* context);
    // Set a special property which cannot be modified or deleted by the script.
    bool defineProperty(const oo::PList& value, JSAtom propID, JSContext* context);

    oo::PList propertyNamed(const std::string& name);
    bool setProperty(const oo::PList& value, const std::string& name);
    bool defineProperty(const oo::PList& value, const std::string& name);

    // OOWeakReferenceSupport and the JS glue of OOObject, forwarded by the facade.
    id weakRetain();
    void weakRefDied(::OOWeakReference* weakRef);
    std::optional<std::string> jsClassName();
    JSValue jsValueInContext(JSContext* context); // owned

    // OOScript
    std::optional<std::string> descriptionComponents() override;
    std::optional<std::string> name() override;
    std::optional<std::string> scriptDescription() override;
    std::optional<std::string> version() override;
    void runWithTarget(::Entity* target) override;

private:
    void javaScriptEngineWillReset(const oo::Notification& notification);
    std::string scriptNameFromPath(const std::optional<std::string>& path);
    oo::PList::Dict defaultPropertiesFromPath(const std::optional<std::string>& path);
    void checkForTickle(JSContext* context);

    JSValue _jsSelf = JS_UNDEFINED; // Owned.

    std::optional<std::string> _name;
    std::optional<std::string> _description;
    std::optional<std::string> _version;
    std::optional<std::string> _filePath;

    ::OOWeakReference* _weakSelf = nil;
};

} // namespace cxx

void InitOOJSScript(JSContext* context, JSValueConst global);

// Transitional: the Objective-C OOJSScript, for callers not yet converted. Deleted, with
// namespace cxx above, by the bridge's deletion bead.
#import "OOJSScript+ObjCBridge.h"

#endif // OOJSSCRIPT_H
