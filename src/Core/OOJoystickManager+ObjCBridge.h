/*

OOJoystickManager+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, Amendment 1 of bead oo-cwz; bead oo-6bux): the Objective-C
OOJoystickManager, a facade over the C++ cxx::OOJoystickManager (OOJoystickManager.h). Its
interface is the one OOJoystickManager.h declared before the conversion, copied exactly (same
selectors, same types, same superclass; the ivars are one C++ reference), so its callers compile
and behave unchanged. Imported as the last line of OOJoystickManager.h; do not import it directly.

It is also the superclass of the Objective-C OOSDLJoystickManager (the SDL manager's facade,
amendment oo-o89), so one Objective-C class has two kinds of instance:

        instance                              its C++ part                 made by
        ------------------------------------  ---------------------------  ------------------------------
        an Objective-C subclass's             an adapter, whose virtual    [[Sub alloc] init]
          (OOSDLJoystickManager)              members message it
        the facade of a C++ manager           the manager                  [[OOJoystickManager alloc]
                                                                           init], or oo::ToObjC

The Objective-C object owns its C++ part. On a subclass instance, the methods a subclass overrides
(-joystickCount, -nameOfJoystick:, -getAxisWithStick:axis:) answer with the base's own member, as
[super ...] or a subclass that does not override did. +sharedStickHandler makes the shared handler
from the class +setStickHandlerClass: registered, so it stays here. The event decoders are the SDL
manager's (upstream #742), not this class's: cxx::OOSDLJoystickManager decodes into the state of
the C++ part of its facade.

        a caller that is                       holds / passes                  crosses with
        -------------------------------------  ------------------------------  --------------------------
        still Objective-C                      OOJoystickManager *             nothing: messages as before
        converted (C++)                        cxx::OOJoystickManager *
          handing a manager to Objective-C                                     oo::ToObjC(manager)
          taking one from Objective-C                                          oo::ToCxx(objcManager)

Never add to this file; converted code does not message the facade. Deleted by its deletion bead
once no file outside OOJoystickManager.* names the Objective-C class and the SDL manager derives
from the C++ one.

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

#ifndef OOJOYSTICKMANAGER_OBJCBRIDGE_H
#define OOJOYSTICKMANAGER_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface OOJoystickManager : OOObject {
@private
    oo::Ref<cxx::OOJoystickManager> _cxxJoystickManager;
}

+ (id)sharedStickHandler;
+ (BOOL)setStickHandlerClass:(Class)aClass;

// General.
// Note: handleSDLEvent returns a BOOL (YES we handled it or NO we
// didn't) so in the future when more handler classes are written,
// the GameView event loop can just go through an array of handlers
// until it finds a handler that handles the event.
- (id)init;

// Roll/pitch axis
- (NSPoint)rollPitchAxis;

// View axis
- (NSPoint)viewAxis;

// convert a dictionary into the internal function map
- (void)setFunction:(int)function withDict:(const oo::PList&)stickFn;
- (void)unsetAxisFunction:(int)function;
- (void)unsetButtonFunction:(int)function;
- (void)unsetGuiButtonFunction:(int)function;

// Accessors and discovery about the hardware.
// These work directly on the internal lookup table so to be fast
// since they are likely to be called by the game loop.
- (BOOL)isButtonDown:(int)button stick:(int)stickNum;
- (BOOL)getButtonState:(int)function;
- (double)getAxisState:(int)function;
- (double)getSensitivity;

// Axis profile handling
- (void)setProfile:(OOJoystickAxisProfile*)profile forAxis:(int)axis;
- (OOJoystickAxisProfile*)getProfileForAxis:(int)axis;
- (void)saveProfileForAxis:(int)axis;
- (void)loadProfileForAxis:(int)axis;

// This one just returns a pointer to the entire state array to
// allow for multiple lookups with only one objc_sendMsg
- (const BOOL*)getAllButtonStates;

// Hardware introspection.
- (std::vector<std::string>)listSticks;

// These use property-list dictionaries since they are used outside the game
// loop and are needed for loading/saving defaults. A nil manager answers a null PList.
- (oo::PList)axisFunctions;
- (oo::PList)buttonFunctions;
- (oo::PList)guiButtonFunctions;

// Set a callback for the next moved axis/pressed button. hwflags
// is in the form HW_AXIS | HW_BUTTON (or just one of).
- (void)setCallback:(SEL)selector
             object:(id)obj
           hardware:(char)hwflags;
- (void)clearCallback;

// Methods generally only used by this class.
- (void)setDefaultMapping;
- (void)clearMappings;
- (void)clearStickStates;
- (void)clearStickButtonState:(int)stickButton;
- (void)saveStickSettings;
- (void)loadStickSettings;

// Methods that should be overridden by all subclasses
- (NSUInteger)joystickCount;
- (std::optional<std::string>)nameOfJoystick:(NSUInteger)stickNumber; // nullopt: the device has no name
- (int16_t)getAxisWithStick:(NSUInteger)stickNum axis:(NSUInteger)axisNum;

@end

namespace oo {

// The manager's Objective-C object: an Objective-C subclass's instance itself, else a C++
// manager's live facade (or a new one); autoreleased. nil for null.
OOJoystickManager* ToObjC(cxx::OOJoystickManager* manager);

// The C++ manager behind an Objective-C one, borrowed (the Objective-C object owns it); null for nil.
cxx::OOJoystickManager* ToCxx(OOJoystickManager* manager);

} // namespace oo

#endif // OOJOYSTICKMANAGER_OBJCBRIDGE_H
