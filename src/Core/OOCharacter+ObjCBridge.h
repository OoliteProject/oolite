/*

OOCharacter+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, bead oo-8kx7): the Objective-C OOCharacter, a facade over the C++
cxx::OOCharacter (OOCharacter.h), for callers that are not converted yet (ships' crews, the JS Ship
methods, Universe). Its interface is the one OOCharacter.h declared before the conversion, copied
exactly (same selectors, same types), so those callers compile and behave unchanged; each method
forwards to its C++ member. Imported as the last line of OOCharacter.h; do not import it directly.

        a caller that is                       holds / passes                        crosses with
        -------------------------------------  ------------------------------------  -----------------------------
        still Objective-C                      OOCharacter *, oo::ObjCRef<...>       nothing: messages as before
        converted (C++)                        oo::Ref<cxx::OOCharacter>, cxx::OOCharacter *
          handing a character to Objective-C                                         oo::ToObjC(character)
          taking one from Objective-C                                                oo::ToCxx(objcCharacter)

oo::ToObjC gives the character's one live facade (oo::ObjCPeers), so identity survives a round trip:
oo::ToObjC(oo::ToCxx(c)) == c. The facade is also the object a character script sees as its
"character" property. Never add to this file; converted code does not message the facade.
Deleted by its deletion bead once no file outside OOCharacter.* names the Objective-C OOCharacter.

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

#ifndef OOCHARACTER_OBJCBRIDGE_H
#define OOCHARACTER_OBJCBRIDGE_H

#import "OOFoundation.h"
#import "oofnd/objc/OOObject.h"

@interface OOCharacter : OOObject {
@private
    oo::Ref<cxx::OOCharacter> _cxxCharacter;
}

- (id)initWithRole:(const std::string&)role andOriginalSystem:(OOSystemID)s;

+ (OOCharacter*)characterWithRole:(const std::string&)c_role andOriginalSystem:(OOSystemID)s;
+ (OOCharacter*)randomCharacterWithRole:(const std::string&)c_role andOriginalSystem:(OOSystemID)s;
+ (OOCharacter*)characterWithDictionary:(const oo::PList&)c_dict; // a dictionary (JS crew definitions may hold any object, as an Object node)

- (std::optional<std::string>)planetOfOrigin;
- (OOSystemID)planetIDOfOrigin;
- (std::optional<std::string>)species;

- (void)basicSetUp;
- (BOOL)castInRole:(const std::string&)role;

- (std::optional<std::string>)cxx_name; // nullopt: none (bead oo-3rb.289.9)
- (void)cxx_setName:(const std::optional<std::string>&)value;

- (std::optional<std::string>)cxx_shortDescription;
- (void)setShortDescription:(const std::optional<std::string>&)value; // nullopt: none (bead oo-qps.51)

- (int)legalStatus;
- (void)cxx_setLegalStatus:(int)value;

- (OOCreditsQuantity)insuranceCredits;
- (void)setInsuranceCredits:(OOCreditsQuantity)value;

- (oo::PList)legacyScript; // an array of script actions; null: none
- (void)setLegacyScript:(const oo::PList&)scriptActions;
- (OOJSScript*)script;
- (void)setCharacterScript:(const std::string&)scriptName;
- (void)doScriptEvent:(OOJSPropID)message;

- (oo::PList)infoForScripting; // a dictionary

@end

namespace oo {

// The character's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOCharacter* ToObjC(cxx::OOCharacter* character);
inline OOCharacter* ToObjC(const Ref<cxx::OOCharacter>& character) { return ToObjC(character.get()); }

// The C++ character behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOCharacter* ToCxx(OOCharacter* character);

} // namespace oo

#endif // OOCHARACTER_OBJCBRIDGE_H
