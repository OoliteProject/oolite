/*

OOCharacter+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, bead oo-8kx7): the Objective-C OOCharacter facade over
cxx::OOCharacter. Every method forwards to its C++ member; results that were OOCharacter * come
back through oo::ToObjC. Deleted with OOCharacter+ObjCBridge.h.

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

#import "OOCharacter.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

// -intValue as Foundation's number and string classes declared it (an Object node's object may answer
// it; no Foundation header declares it since oo-qps.17).
@protocol OOCharacterIntValue
- (int)intValue;
@end

int oo::SendIntValue(id object)
{
    return [(id<OOCharacterIntValue>)object intValue];
}

@interface OOCharacter (OOObjCBridgePrivate)

- (id)initWithCxxCharacter:(cxx::OOCharacter*)character;

@end

@implementation OOCharacter

// Inside the @implementation for the private ivar.
OOCharacter* oo::ToObjC(cxx::OOCharacter* character)
{
    return Peers().peerFor(character, [character] { return [[OOCharacter alloc] initWithCxxCharacter:character]; });
}

cxx::OOCharacter* oo::ToCxx(OOCharacter* character)
{
    if (character == nil)
        return nullptr;
    return character->_cxxCharacter.get();
}

- (id)initWithCxxCharacter:(cxx::OOCharacter*)character
{
    self = [super init];
    if (self != nil)
        _cxxCharacter = oo::Ref<cxx::OOCharacter>(character);
    return self;
}

// [[OOCharacter alloc] init], as before: a character with every field zero.
- (id)init
{
    oo::Ref<cxx::OOCharacter> character = oo::makeRef<cxx::OOCharacter>();
    self = [self initWithCxxCharacter:character.get()];
    if (self != nil) {
        @autoreleasepool {
            Peers().peerFor(character.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (id)initWithRole:(const std::string&)role andOriginalSystem:(OOSystemID)s
{
    oo::Ref<cxx::OOCharacter> character = oo::makeRef<cxx::OOCharacter>(role, s);
    self = [self initWithCxxCharacter:character.get()];
    if (self != nil) {
        @autoreleasepool {
            Peers().peerFor(character.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxCharacter.get());
    [super dealloc];
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return _cxxCharacter->descriptionComponents();
}

- (std::optional<std::string>)cxx_oo_jsClassName
{
    return _cxxCharacter->oo_jsClassName();
}

+ (OOCharacter*)characterWithRole:(const std::string&)c_role andOriginalSystem:(OOSystemID)s
{
    return oo::ToObjC(cxx::OOCharacter::characterWithRole(c_role, s));
}

+ (OOCharacter*)randomCharacterWithRole:(const std::string&)c_role andOriginalSystem:(OOSystemID)s
{
    return oo::ToObjC(cxx::OOCharacter::randomCharacterWithRole(c_role, s));
}

+ (OOCharacter*)characterWithDictionary:(const oo::PList&)c_dict
{
    return oo::ToObjC(cxx::OOCharacter::characterWithDictionary(c_dict));
}

- (std::optional<std::string>)planetOfOrigin
{
    return _cxxCharacter->planetOfOrigin();
}
- (OOSystemID)planetIDOfOrigin
{
    return _cxxCharacter->planetIDOfOrigin();
}
- (std::optional<std::string>)species
{
    return _cxxCharacter->species();
}

- (void)basicSetUp
{
    _cxxCharacter->basicSetUp();
}
- (BOOL)castInRole:(const std::string&)role
{
    return _cxxCharacter->castInRole(role);
}

- (std::optional<std::string>)cxx_name
{
    return _cxxCharacter->name();
}
- (void)cxx_setName:(const std::optional<std::string>&)value
{
    _cxxCharacter->setName(value);
}

- (std::optional<std::string>)cxx_shortDescription
{
    return _cxxCharacter->shortDescription();
}
- (void)setShortDescription:(const std::optional<std::string>&)value
{
    _cxxCharacter->setShortDescription(value);
}

- (int)legalStatus
{
    return _cxxCharacter->legalStatus();
}
- (void)cxx_setLegalStatus:(int)value
{
    _cxxCharacter->setLegalStatus(value);
}

- (OOCreditsQuantity)insuranceCredits
{
    return _cxxCharacter->insuranceCredits();
}
- (void)setInsuranceCredits:(OOCreditsQuantity)value
{
    _cxxCharacter->setInsuranceCredits(value);
}

- (oo::PList)legacyScript
{
    return _cxxCharacter->legacyScript();
}
- (void)setLegacyScript:(const oo::PList&)scriptActions
{
    _cxxCharacter->setLegacyScript(scriptActions);
}
- (OOJSScript*)script
{
    return _cxxCharacter->script();
}
- (void)setCharacterScript:(const std::string&)scriptName
{
    _cxxCharacter->setCharacterScript(scriptName);
}
- (void)doScriptEvent:(OOJSPropID)message
{
    _cxxCharacter->doScriptEvent(message);
}

- (oo::PList)infoForScripting
{
    return _cxxCharacter->infoForScripting();
}

@end
