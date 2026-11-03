/*

OOJoystickManager+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, Amendment 1 of bead oo-cwz; bead oo-6bux): the Objective-C
OOJoystickManager facade, and the adapter that is an Objective-C subclass's C++ part. See
OOJoystickManager+ObjCBridge.h.

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

#import "OOJoystickManager.h"

#include "oofnd/objc/OOAssert.h"
#include "oofnd/objc/OOObjCPeer.h"

namespace {

Class sStickHandlerClass = Nil;
id sSharedStickHandler = nil;

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

/*	The C++ part of an Objective-C subclass's instance (the SDL manager's facade): each virtual
        member messages the Objective-C object, so the subclass's override runs, as it did when the
        base class was Objective-C (ADR-0056 Amendment 1 item 3). The Objective-C object owns the
        adapter and is not retained by it; its -dealloc clears the pointer, after which the members
        answer as a message to nil did.
*/
class ObjCJoystickManager final : public cxx::OOJoystickManager {
public:
    explicit ObjCJoystickManager(::OOJoystickManager* owner)
        : _owner(owner)
    {
    }

    ::OOJoystickManager* owner() { return _owner; }
    void ownerDeallocated() { _owner = nil; }

    NSUInteger joystickCount() override
    {
        return [_owner joystickCount];
    }

    std::optional<std::string> nameOfJoystick(NSUInteger stickNumber) override
    {
        if (_owner == nil)
            return std::nullopt;
        return [_owner nameOfJoystick:stickNumber];
    }

    int16_t getAxisWithStick(NSUInteger stickNum, NSUInteger axisNum) override
    {
        return [_owner getAxisWithStick:stickNum axis:axisNum];
    }

private:
    ::OOJoystickManager* _owner = { }; // Not retained.
};

// The adapter, if manager is an Objective-C subclass's C++ part; else null (a C++ manager, or null).
ObjCJoystickManager* AsObjCManager(cxx::OOJoystickManager* manager)
{
    return dynamic_cast<ObjCJoystickManager*>(manager);
}

} // namespace

@interface OOJoystickManager (OOObjCBridgePrivate)

// For oo::ToObjC, under the peer table's lock: stores the C++ object.
- (id)initWithCxxJoystickManager:(cxx::OOJoystickManager*)manager;

@end

@implementation OOJoystickManager

// Inside the @implementation for the private ivar.
OOJoystickManager* oo::ToObjC(cxx::OOJoystickManager* manager)
{
    if (ObjCJoystickManager* objCManager = AsObjCManager(manager))
        return [[objCManager->owner() retain] autorelease];
    return Peers().peerFor(manager, [manager] { return [[OOJoystickManager alloc] initWithCxxJoystickManager:manager]; });
}

cxx::OOJoystickManager* oo::ToCxx(OOJoystickManager* manager)
{
    if (manager == nil)
        return nullptr;
    return manager->_cxxJoystickManager.get();
}

+ (id)sharedStickHandler
{
    if (sSharedStickHandler == nil) {
        if (sStickHandlerClass == Nil)
            sStickHandlerClass = [OOJoystickManager class];
        sSharedStickHandler = [[sStickHandlerClass alloc] init];
    }
    return sSharedStickHandler;
}

+ (BOOL)setStickHandlerClass:(Class)aClass
{
    OOAssert(sStickHandlerClass == nil, "Can't set joystick handler class after joystick handler is initialized.");
    OOParameterAssert(aClass == Nil || [aClass isSubclassOfClass:[OOJoystickManager class]]);

    sStickHandlerClass = aClass;
    return YES;
}

// [[OOJoystickManager alloc] init] makes a C++ manager with this facade as its peer; a subclass's
// -init makes the adapter. Either way the old -init body runs once the C++ part exists, so its
// calls of the overridden methods reach the subclass.
- (id)init
{
    self = [super init];
    if (self != nil) {
        if ([self class] == [OOJoystickManager class]) {
            _cxxJoystickManager = oo::makeRef<cxx::OOJoystickManager>();
            @autoreleasepool {
                Peers().peerFor(_cxxJoystickManager.get(), [self] { return [self retain]; });
            }
        } else {
            _cxxJoystickManager = oo::makeRef<ObjCJoystickManager>(self);
        }
        _cxxJoystickManager->init();
    }
    return self;
}

- (id)initWithCxxJoystickManager:(cxx::OOJoystickManager*)manager
{
    self = [super init];
    if (self != nil)
        _cxxJoystickManager = oo::Ref<cxx::OOJoystickManager>(manager);
    return self;
}

- (void)dealloc
{
    if (ObjCJoystickManager* objCManager = AsObjCManager(_cxxJoystickManager.get()))
        objCManager->ownerDeallocated();
    else
        Peers().forget(_cxxJoystickManager.get());
    [super dealloc];
}

- (NSPoint)rollPitchAxis
{
    return _cxxJoystickManager->rollPitchAxis();
}
- (NSPoint)viewAxis
{
    return _cxxJoystickManager->viewAxis();
}
- (void)setFunction:(int)function withDict:(const oo::PList&)stickFn
{
    _cxxJoystickManager->setFunction(function, stickFn);
}
- (void)unsetAxisFunction:(int)function
{
    _cxxJoystickManager->unsetAxisFunction(function);
}
- (void)unsetButtonFunction:(int)function
{
    _cxxJoystickManager->unsetButtonFunction(function);
}
- (BOOL)isButtonDown:(int)button stick:(int)stickNum
{
    return _cxxJoystickManager->isButtonDown(button, stickNum);
}
- (BOOL)getButtonState:(int)function
{
    return _cxxJoystickManager->getButtonState(function);
}
- (double)getAxisState:(int)function
{
    return _cxxJoystickManager->getAxisState(function);
}
- (double)getSensitivity
{
    return _cxxJoystickManager->getSensitivity();
}

- (void)setProfile:(OOJoystickAxisProfile*)profile forAxis:(int)axis
{
    _cxxJoystickManager->setProfile(oo::ToCxx(profile), axis);
}
- (OOJoystickAxisProfile*)getProfileForAxis:(int)axis
{
    return oo::ToObjC(_cxxJoystickManager->getProfileForAxis(axis));
}
- (void)saveProfileForAxis:(int)axis
{
    _cxxJoystickManager->saveProfileForAxis(axis);
}
- (void)loadProfileForAxis:(int)axis
{
    _cxxJoystickManager->loadProfileForAxis(axis);
}

- (const BOOL*)getAllButtonStates
{
    return _cxxJoystickManager->getAllButtonStates();
}
- (std::vector<std::string>)listSticks
{
    return _cxxJoystickManager->listSticks();
}
- (oo::PList)axisFunctions
{
    return _cxxJoystickManager->axisFunctions();
}
- (oo::PList)buttonFunctions
{
    return _cxxJoystickManager->buttonFunctions();
}

- (void)setCallback:(SEL)selector object:(id)obj hardware:(char)hwflags
{
    _cxxJoystickManager->setCallback(selector, obj, hwflags);
}
- (void)clearCallback
{
    _cxxJoystickManager->clearCallback();
}

- (void)setDefaultMapping
{
    _cxxJoystickManager->setDefaultMapping();
}
- (void)clearMappings
{
    _cxxJoystickManager->clearMappings();
}
- (void)clearStickStates
{
    _cxxJoystickManager->clearStickStates();
}
- (void)clearStickButtonState:(int)stickButton
{
    _cxxJoystickManager->clearStickButtonState(stickButton);
}
- (void)saveStickSettings
{
    _cxxJoystickManager->saveStickSettings();
}
- (void)loadStickSettings
{
    _cxxJoystickManager->loadStickSettings();
}

// The methods a subclass overrides. On a subclass's instance these are reached only when it does
// not override them, or by [super ...]: the base's own member answers. On a C++ manager's facade
// the C++ class's (virtual) member answers.

- (NSUInteger)joystickCount
{
    if (AsObjCManager(_cxxJoystickManager.get()) != nullptr)
        return _cxxJoystickManager->cxx::OOJoystickManager::joystickCount();
    return _cxxJoystickManager->joystickCount();
}

- (std::optional<std::string>)nameOfJoystick:(NSUInteger)stickNumber
{
    if (AsObjCManager(_cxxJoystickManager.get()) != nullptr)
        return _cxxJoystickManager->cxx::OOJoystickManager::nameOfJoystick(stickNumber);
    return _cxxJoystickManager->nameOfJoystick(stickNumber);
}

- (int16_t)getAxisWithStick:(NSUInteger)stickNum axis:(NSUInteger)axisNum
{
    if (AsObjCManager(_cxxJoystickManager.get()) != nullptr)
        return _cxxJoystickManager->cxx::OOJoystickManager::getAxisWithStick(stickNum, axisNum);
    return _cxxJoystickManager->getAxisWithStick(stickNum, axisNum);
}

@end
