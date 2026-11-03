/*

OOScript+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, Amendment 1 of bead oo-cwz; bead oo-604l): the Objective-C
OOScript facade over cxx::OOScript, and the adapter that is an Objective-C subclass's C++ part.
See OOScript+ObjCBridge.h. Deleted with it.

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

#import "OOScript.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

/*	The C++ part of an Objective-C subclass's instance (OOJSScript, the OOPListScript facade): each
        virtual member messages the Objective-C object, so the subclass's override runs, as it did when
        the base class was Objective-C (ADR-0056 Amendment 1 item 3). The Objective-C object owns the
        adapter and is not retained by it; its -dealloc clears the pointer, after which the members
        answer as a message to nil did.
*/
class ObjCScript final : public cxx::OOScript {
public:
    explicit ObjCScript(::OOScript* owner)
        : _owner(owner)
    {
    }

    ::OOScript* owner() { return _owner; }
    void ownerDeallocated() { _owner = nil; }

    std::optional<std::string> descriptionComponents() override
    {
        if (_owner == nil)
            return std::nullopt;
        return [_owner cxx_descriptionComponents];
    }

    std::optional<std::string> name() override
    {
        if (_owner == nil)
            return std::nullopt;
        return [_owner cxx_name];
    }

    std::optional<std::string> scriptDescription() override
    {
        if (_owner == nil)
            return std::nullopt;
        return [_owner scriptDescription];
    }

    std::optional<std::string> version() override
    {
        if (_owner == nil)
            return std::nullopt;
        return [_owner cxx_version];
    }

    bool requiresTickle() override
    {
        return [_owner requiresTickle];
    }

    void runWithTarget(::Entity* target) override
    {
        [_owner runWithTarget:target];
    }

private:
    ::OOScript* _owner = { }; // Not retained.
};

// The adapter, if script is an Objective-C subclass's C++ part; else null (a C++ script, or null).
ObjCScript* AsObjCScript(cxx::OOScript* script)
{
    return dynamic_cast<ObjCScript*>(script);
}

} // namespace

@interface OOScript (OOObjCBridgePrivate)

// For oo::ToObjC, under the peer table's lock: stores the C++ object.
- (id)initWithCxxScript:(cxx::OOScript*)script;

@end

@implementation OOScript

// Inside the @implementation for the private ivar.
::OOScript* oo::ToObjC(cxx::OOScript* script)
{
    if (ObjCScript* objCScript = AsObjCScript(script))
        return [[objCScript->owner() retain] autorelease];
    return Peers().peerFor(script, [script] { return [[::OOScript alloc] initWithCxxScript:script]; });
}

cxx::OOScript* oo::ToCxx(::OOScript* script)
{
    if (script == nil)
        return nullptr;
    return script->_cxxRootScript.get();
}

+ (std::optional<std::vector<oo::ObjCRef<OOScript*>>>)cxx_worldScriptsAtPath:(const std::string&)path
{
    return cxx::OOScript::worldScriptsAtPath(path);
}

+ (std::optional<std::vector<oo::ObjCRef<OOScript*>>>)scriptsFromFileNamed:(const std::string&)fileName
{
    return cxx::OOScript::scriptsFromFileNamed(fileName);
}

+ (std::vector<oo::ObjCRef<OOScript*>>)scriptsFromList:(const std::vector<std::string>&)fileNames
{
    return cxx::OOScript::scriptsFromList(fileNames);
}

+ (std::optional<std::vector<oo::ObjCRef<OOScript*>>>)scriptsFromFileAtPath:(const std::string&)filePath
{
    return cxx::OOScript::scriptsFromFileAtPath(filePath);
}

+ (id)cxx_jsScriptFromFileNamed:(const std::string&)fileName properties:(const oo::PList&)properties
{
    return cxx::OOScript::jsScriptFromFileNamed(fileName, properties);
}

+ (id)cxx_jsAIScriptFromFileNamed:(const std::string&)fileName properties:(const oo::PList&)properties
{
    return cxx::OOScript::jsAIScriptFromFileNamed(fileName, properties);
}

// [[OOScript alloc] init] makes a C++ script with this facade as its peer; a subclass's -init
// makes the adapter.
- (id)init
{
    self = [super init];
    if (self != nil) {
        if ([self class] == [OOScript class]) {
            _cxxRootScript = oo::makeRef<cxx::OOScript>();
            @autoreleasepool {
                Peers().peerFor(_cxxRootScript.get(), [self] { return [self retain]; });
            }
        } else {
            _cxxRootScript = oo::makeRef<ObjCScript>(self);
        }
    }
    return self;
}

- (id)initWithCxxScript:(cxx::OOScript*)script
{
    self = [super init];
    if (self != nil)
        _cxxRootScript = oo::Ref<cxx::OOScript>(script);
    return self;
}

- (void)dealloc
{
    if (ObjCScript* objCScript = AsObjCScript(_cxxRootScript.get()))
        objCScript->ownerDeallocated();
    else
        Peers().forget(_cxxRootScript.get());
    [super dealloc];
}

- (std::optional<std::string>)displayName
{
    return _cxxRootScript->displayName();
}

// The methods a subclass overrides. On a subclass's instance these are reached only when it does
// not override them, or by [super ...]: the base's own member answers. On a C++ script's facade
// the C++ class's (virtual) member answers.

- (std::optional<std::string>)cxx_descriptionComponents
{
    if (AsObjCScript(_cxxRootScript.get()) != nullptr)
        return _cxxRootScript->cxx::OOScript::descriptionComponents();
    return _cxxRootScript->descriptionComponents();
}

- (std::optional<std::string>)cxx_name
{
    if (AsObjCScript(_cxxRootScript.get()) != nullptr)
        return _cxxRootScript->cxx::OOScript::name();
    return _cxxRootScript->name();
}

- (std::optional<std::string>)scriptDescription
{
    if (AsObjCScript(_cxxRootScript.get()) != nullptr)
        return _cxxRootScript->cxx::OOScript::scriptDescription();
    return _cxxRootScript->scriptDescription();
}

- (std::optional<std::string>)cxx_version
{
    if (AsObjCScript(_cxxRootScript.get()) != nullptr)
        return _cxxRootScript->cxx::OOScript::version();
    return _cxxRootScript->version();
}

- (BOOL)requiresTickle
{
    if (AsObjCScript(_cxxRootScript.get()) != nullptr)
        return _cxxRootScript->cxx::OOScript::requiresTickle();
    return _cxxRootScript->requiresTickle();
}

- (void)runWithTarget:(Entity*)target
{
    if (AsObjCScript(_cxxRootScript.get()) != nullptr)
        _cxxRootScript->cxx::OOScript::runWithTarget(target);
    else
        _cxxRootScript->runWithTarget(target);
}

@end
