/*

OOCharacter.h

Represents an NPC person (as opposed to an NPC ship).

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

#import "OOFoundation.h"
#import "OOJSPropID.h"
#import "OOTypes.h"
#import "legacy_random.h"
#import "oofnd/objc/OOObject.h"

#include "oofnd/PList.hpp"
#include "oofnd/StdLib.hpp"

@class OOJSScript;

@interface OOCharacter : OOObject {
@private
    std::optional<std::string> _name;
    std::optional<std::string> _shortDescription;
    OOSystemID _originSystem;
    Random_Seed _genSeed;
    int _legalStatus;
    OOCreditsQuantity _insuranceCredits;
    oo::PList _scriptActions; // an array; null: none
    OOJSScript* _script;
}

- (id)initWithRole:(const std::string&)role andOriginalSystem:(OOSystemID)s;

+ (OOCharacter*)characterWithRole:(const std::string&)c_role andOriginalSystem:(OOSystemID)s;
+ (OOCharacter*)randomCharacterWithRole:(const std::string&)c_role andOriginalSystem:(OOSystemID)s;
+ (OOCharacter*)characterWithDictionary:(id)c_dict; // an Objective-C dictionary (JS crew definitions may hold any object)

- (std::optional<std::string>)planetOfOrigin;
- (OOSystemID)planetIDOfOrigin;
- (std::optional<std::string>)species;

- (void)basicSetUp;
- (BOOL)castInRole:(const std::string&)role;

- (id)name; // shared selector (Foundation declares -name too): -cxx_name as an Objective-C string, or nil
- (std::optional<std::string>)cxx_name; // nullopt: none (bead oo-3rb.289.9)
- (void)setName:(id)value; // shared selector (Foundation declares -setName: too): -cxx_setName: with an Objective-C string, or nil
- (void)cxx_setName:(const std::optional<std::string>&)value;

- (std::optional<std::string>)cxx_shortDescription;
- (void)setShortDescription:(id)value; // shared selector: an Objective-C string, or nil

- (int)legalStatus;
- (void)setLegalStatus:(int)value;

- (OOCreditsQuantity)insuranceCredits;
- (void)setInsuranceCredits:(OOCreditsQuantity)value;

- (oo::PList)legacyScript; // an array of script actions; null: none
- (void)setLegacyScript:(const oo::PList&)scriptActions;
- (OOJSScript*)script;
- (void)setCharacterScript:(const std::string&)scriptName;
- (void)doScriptEvent:(OOJSPropID)message;

- (oo::PList)infoForScripting; // a dictionary

@end
