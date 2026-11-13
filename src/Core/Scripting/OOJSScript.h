/*

OOJSScript.h (QuickJS-ng)

JavaScript support for Oolite
Copyright (C) 2007-2013 David Taylor and Jens Ayton.

A subclass of OOScript: the script's identity is the C++ object. Holders keep it
as oo::Ref (the timers and definitions as oo::WeakRef), the stack of running
scripts holds it weakly, and the Script JS object's private slot holds a weak
reference to it (OOJSPrivateObject glue).

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

#pragma once

#include "OOJavaScriptEngine.h"
#include "OOScript.h"
#include "oofnd/Notification.hpp"

// The script property that holds the identifier of the manifest the script was
// loaded under.
inline constexpr char kLocalManifestProperty[] = "oolite_manifest_identifier";

class OOJSScript : public OOScript {
 public:
  // +scriptWithPath:properties:: a new script, null when it could not be
  // loaded. path nullopt is nil (the script is then named after its address);
  // properties may hold live objects.
  static std::shared_ptr<OOJSScript> scriptWithPath(
      const std::optional<std::string>& path, const oo::PList& properties);

  // The old -dealloc's body.
  ~OOJSScript() override;

  // The old -initWithPath:properties: after [super init], run by
  // scriptWithPath(); false: the script could not be loaded, and
  // scriptWithPath() drops it.
  bool initWithPath(const std::optional<std::string>& path,
                    const oo::PList& properties);

  // The running script; null when none runs, for a script-less push, and once a
  // weakly pushed script has gone (a dead weak reference, which answered every
  // message as nil).
  static OOJSScript* currentlyRunningScript();
  // The running scripts, outermost first; an entry is null once a weakly pushed
  // script has gone. Raises, as -addObject: did on nil, if the stack holds a
  // script-less push.
  static std::vector<std::shared_ptr<OOJSScript>> scriptStack();

  /*	External manipulation of acrtive script stack. Used, for instance, by
          timers. Failing to balance these will crash!
          Passing a nil script is valid for cases where JS is used which is not
          attached to a specific script.
          The weak form is for a holder that keeps its script weakly; pop it
     with its get().
  */
  static void pushScript(OOJSScript* script);
  static void pushScript(const std::weak_ptr<OOJSScript>& script);
  static void popScript(OOJSScript* script);

  /*	Call a method.
          outResult may be NULL; if not, it is owned by the caller.
  */
  bool callMethod(JSAtom methodID, JSContext* context, JSValueConst* argv,
                  int argc, JSValue* outResult) override;

  // The property as cxx_OOJSPListFromJSValue() converts it; null when there is
  // no script object or it could not be read.
  oo::PList propertyWithID(JSAtom propID, JSContext* context);
  // Set a property which can be modified or deleted by the script.
  bool setProperty(const oo::PList& value, JSAtom propID, JSContext* context);
  // Set a special property which cannot be modified or deleted by the script.
  bool defineProperty(const oo::PList& value, JSAtom propID,
                      JSContext* context);

  oo::PList propertyNamed(const std::string& name);
  bool setProperty(const oo::PList& value, const std::string& name);
  bool defineProperty(const oo::PList& value, const std::string& name);

  // The JS glue (OOJSPrivateObject; -cxx_oo_jsClassName, -oo_jsValueInContext:
  // and the -cxx_oo_jsDescription toString() answered).
  std::optional<std::string> jsClassName();
  JSValue jsValueInContext(JSContext* context) override;  // owned
  std::optional<std::string> jsDescription() override;

  // OOScript
  std::optional<std::string> descriptionComponents() override;
  std::optional<std::string> name() override;
  std::optional<std::string> scriptDescription() override;
  std::optional<std::string> version() override;
  void runWithTarget(Entity* target) override;

 private:
  void javaScriptEngineWillReset(const oo::Notification& notification);
  std::string scriptNameFromPath(const std::optional<std::string>& path);
  oo::PList::Dict defaultPropertiesFromPath(
      const std::optional<std::string>& path);
  void checkForTickle(JSContext* context);

  JSValue _jsSelf = JS_UNDEFINED;  // Owned.

  std::optional<std::string> _name;
  std::optional<std::string> _description;
  std::optional<std::string> _version;
  std::optional<std::string> _filePath;
};

void InitOOJSScript(JSContext* context, JSValueConst global);
