/*

OOCharacter.m

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

#import "OOFoundationBridge.h"
#import "OOJSScript.h"
#import "OOPListView.h"
#import "OOStringExpander.h"
#import "OOStringParsing.h"
#import "Universe.h"
#include "oofnd/Scanner.hpp"
#include "oofnd/String.hpp"

namespace {

// get<std::string> where the Foundation code read nil: std::nullopt when the key is absent or its
// value is neither a string nor a number.
std::optional<std::string> OptionalStringForKey(const oo::PList& dict, std::string_view key)
{
    const oo::PList* value = dict.find(key);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return dict.get<std::string>(key);
}

} // namespace

@interface OOCharacter (Private)

- (id)initWithGenSeed:(Random_Seed)characterSeed andOriginalSystem:(OOSystemID)systemSeed;
- (void)setCharacterFromDictionary:(const oo::PList&)dict;

- (void)setOriginSystem:(OOSystemID)value;
- (Random_Seed)genSeed;

@end

@implementation OOCharacter

- (std::optional<std::string>)cxx_descriptionComponents
{
    // ("(null)" is what "%@" printed for a missing name or description)
    return oo::str::format("%s, %s. bounty: %i insurance: %zu", _name.value_or("(null)").c_str(), _shortDescription.value_or("(null)").c_str(), [self legalStatus], [self insuranceCredits]);
}

- (std::optional<std::string>)cxx_oo_jsClassName
{
    return std::string("Character");
}

- (void)dealloc
{
    _name.reset();
    _shortDescription.reset();
    _scriptActions = oo::PList();
    DESTROY(_script);

    [super dealloc];
}

- (id)initWithGenSeed:(Random_Seed)characterSeed andOriginalSystem:(OOSystemID)system
{
    if ((self = [super init])) {
        // do character set-up
        _genSeed = characterSeed;
        _originSystem = system;

        [self basicSetUp];
    }
    return self;
}

- (id)initWithRole:(const std::string&)role andOriginalSystem:(OOSystemID)system
{
    Random_Seed seed;
    make_pseudo_random_seed(&seed);

    if ((self = [self initWithGenSeed:seed andOriginalSystem:system])) {
        [self castInRole:role];
    }

    return self;
}

+ (OOCharacter*)characterWithRole:(const std::string&)role andOriginalSystem:(OOSystemID)system
{
    return [[[self alloc] initWithRole:role andOriginalSystem:system] autorelease];
}

+ (OOCharacter*)randomCharacterWithRole:(const std::string&)role andOriginalSystem:(OOSystemID)system
{
    Random_Seed seed;

    seed.a = (Ranrot() & 0xff);
    seed.b = (Ranrot() & 0xff);
    seed.c = (Ranrot() & 0xff);
    seed.d = (Ranrot() & 0xff);
    seed.e = (Ranrot() & 0xff);
    seed.f = (Ranrot() & 0xff);

    OOCharacter* character = [[[OOCharacter alloc] initWithGenSeed:seed andOriginalSystem:system] autorelease];
    [character castInRole:role];

    return character;
}

+ (OOCharacter*)characterWithDictionary:(id)dict
{
    OOCharacter* character = [[[OOCharacter alloc] init] autorelease];
    // (read as an oo::PList, which carries any non-plist values exactly: proposed ADR-0043 Amendment 2)
    [character setCharacterFromDictionary:oo::PListFrom(dict)];

    return character;
}

- (std::optional<std::string>)planetOfOrigin
{
    // determine the planet of origin
    const oo::PList originInfo = [UNIVERSE cxx_generateSystemData:[self planetIDOfOrigin]];
    const oo::PList* name = originInfo.find(std::string(KEY_NAME));
    if (name == nullptr || !name->isString())
        return std::nullopt; // (the value was returned as it stood; it is a string)
    return *name->getIf<std::string>();
}

- (OOSystemID)planetIDOfOrigin
{
    // determine the planet of origin
    return _originSystem;
}

- (std::optional<std::string>)species
{
    // determine the character's species
    int species = [self genSeed].f & 0x03; // 0-1 native to home system, 2 human colonial, 3 other
    std::optional<std::string> speciesString;
    if (species == 3)
        speciesString = [UNIVERSE cxx_getSystemInhabitants:[self genSeed].e plural:NO];
    else
        speciesString = [UNIVERSE cxx_getSystemInhabitants:[self planetIDOfOrigin] plural:NO];

    if (!speciesString.has_value())
        return std::nullopt;

    if (![UNIVERSE cxx_descriptions]->get<bool>("lowercase_ignore")) {
        speciesString = oo::str::lowercase(*speciesString);
    }

    return oo::str::trim(*speciesString, oo::str::CharacterSet::whitespace());
}

- (void)basicSetUp
{
    // save random seeds for restoration later
    RNG_Seed savedRNGSeed = currentRandomSeed();
    RANROTSeed savedRANROTSeed = RANROTGetFullSeed();
    // set RNG to character seed
    Random_Seed genSeed = [self genSeed];
    seed_for_planet_description(genSeed);

    // determine the planet of origin
    const oo::PList originInfo = [UNIVERSE cxx_generateSystemData:[self planetIDOfOrigin]];
    const std::optional<std::string> planet = OptionalStringForKey(originInfo, std::string(KEY_NAME));
    OOGovernmentID government = originInfo.get<int>(std::string(KEY_GOVERNMENT)); // 0 .. 7 (0 anarchic .. 7 most stable)
    int criminalTendency = government ^ 0x07;

    // determine the character's species
    const std::optional<std::string> species = [self species];

    // determine the character's name (each half expanded in turn, as the format's arguments were)
    seed_RNG_only_for_planet_description(genSeed);
    std::string genName;
    if (species.has_value() && oo::str::hasPrefix(*species, "human")) {
        const std::string givenName = cxx_OOExpandWithSeed(genSeed, "%R").value_or("(null)");
        const std::string familyName = cxx_OOExpandKeyWithSeed(genSeed, "nom").value_or("(null)");
        genName = givenName + " " + familyName;
    } else {
        /*	NOTE: we can't use "%R %R" because that will produce the same string
                twice. TODO: is there a reason not to use %N and kOOExpandGoodRNG
                here? Is there some context where we rely on being able to get the
                same name for a given genSeed?
         */
        const std::string givenName = cxx_OOExpandWithSeed(genSeed, "%R").value_or("(null)");
        const std::string familyName = cxx_OOExpandWithSeed(genSeed, "%R").value_or("(null)");
        genName = givenName + " " + familyName;
    }
    _name = genName;

    _shortDescription = cxx_OOExpandKeyWithSeed(genSeed, "character-generic-description", species, planet);

    // determine _legalStatus for a completely random character
    [self setLegalStatus:0]; // clean
    int legalIndex = gen_rnd_number() & gen_rnd_number() & 0x03;
    while (((gen_rnd_number() & 0xf) < criminalTendency) && (legalIndex < 3)) {
        legalIndex++;
    }
    if (legalIndex == 3) {
        // criminal
        [self setLegalStatus:criminalTendency + criminalTendency * (gen_rnd_number() & 0x03) + (gen_rnd_number() & gen_rnd_number() & 0x7f)];
    }
    legalIndex = 0;
    if (_legalStatus > 0)
        legalIndex = (_legalStatus <= 50) ? 1 : 2;

    // if clean - determine insurance level (if any)
    [self setInsuranceCredits:0];
    if (legalIndex == 0) {
        int insuranceIndex = gen_rnd_number() & gen_rnd_number() & 0x03;
        switch (insuranceIndex) {
        case 1:
            [self setInsuranceCredits:125];
            break;
        case 2:
            [self setInsuranceCredits:250];
            break;
        case 3:
            [self setInsuranceCredits:500];
        }
    }

    // restore random seed
    setRandomSeed(savedRNGSeed);
    RANROTSetFullSeed(savedRANROTSeed);
}

- (BOOL)castInRole:(const std::string&)roleName
{
    BOOL specialSetUpDone = NO;

    const std::string role = oo::str::lowercase(roleName);
    if (oo::str::hasPrefix(role, "pirate")) {
        // determine _legalStatus for a completely random character
        Random_Seed genSeed = [self genSeed];
        int sins = 0x08 | (genSeed.a & genSeed.b);
        [self setLegalStatus:sins & 0x7f];

        specialSetUpDone = YES;
    } else if (oo::str::hasPrefix(role, "trader")) {
        [self setLegalStatus:0]; // clean

        int insuranceIndex = gen_rnd_number() & 0x03;
        switch (insuranceIndex) {
        case 0:
            [self setInsuranceCredits:0];
            break;
        case 1:
            [self setInsuranceCredits:125];
            break;
        case 2:
            [self setInsuranceCredits:250];
            break;
        case 3:
            [self setInsuranceCredits:500];
        }
        specialSetUpDone = YES;
    } else if (oo::str::hasPrefix(role, "hunter")) {
        [self setLegalStatus:0]; // clean
        int insuranceIndex = gen_rnd_number() & 0x03;
        if (insuranceIndex == 3)
            [self setInsuranceCredits:500];
        specialSetUpDone = YES;
    } else if (oo::str::hasPrefix(role, "police")) {
        [self setLegalStatus:0]; // clean
        [self setInsuranceCredits:125];
        specialSetUpDone = YES;
    } else if (role == "miner") {
        [self setLegalStatus:0]; // clean
        [self setInsuranceCredits:25];
        specialSetUpDone = YES;
    } else if (role == "passenger") {
        [self setLegalStatus:0]; // clean
        int insuranceIndex = gen_rnd_number() & 0x03;
        switch (insuranceIndex) {
        case 0:
            [self setInsuranceCredits:25];
            break;
        case 1:
            [self setInsuranceCredits:125];
            break;
        case 2:
            [self setInsuranceCredits:250];
            break;
        case 3:
            [self setInsuranceCredits:500];
        }
        specialSetUpDone = YES;
    } else if (role == "slave") {
        [self setLegalStatus:0]; // clean
        [self setInsuranceCredits:0];
        specialSetUpDone = YES;
    } else if (role == "thargoid") {
        [self setLegalStatus:100];
        [self setInsuranceCredits:0];
        [self cxx_setName:OO_DESC("character-thargoid-name")];
        [self setShortDescription:oo::NSStringFrom(OO_DESC("character-a-thargoid"))];
        specialSetUpDone = YES;
    }

    // do long description here

    return specialSetUpDone;
}

- (id)name // shared selector (Foundation declares -name too; retires with oo-qps)
{
    return oo::NSStringOrNil([self cxx_name]);
}

- (std::optional<std::string>)cxx_name
{
    return _name;
}

- (std::optional<std::string>)cxx_shortDescription
{
    return _shortDescription;
}

- (Random_Seed)genSeed
{
    return _genSeed;
}

- (int)legalStatus
{
    return _legalStatus;
}

- (OOCreditsQuantity)insuranceCredits
{
    return _insuranceCredits;
}

- (oo::PList)legacyScript
{
    return _scriptActions;
}

- (oo::PList)infoForScripting
{
    // Every value is worked out first, as the list's arguments were; the list ended at the first
    // nil (a missing name, description or species).
    const std::optional<std::string> species = [self species];
    oo::PList::Dict result;
    if (_name.has_value()) {
        result.emplace("name", oo::PList(*_name));
        if (_shortDescription.has_value()) {
            result.emplace("description", oo::PList(*_shortDescription));
            if (species.has_value()) {
                result.emplace("species", oo::PList(*species));
                result.emplace("legalStatus", oo::PList::signedInteger([self legalStatus]));
                result.emplace("insuranceCredits", oo::PList::unsignedInteger([self insuranceCredits]));
                result.emplace("homeSystem", oo::PList::signedInteger([self planetIDOfOrigin]));
            }
        }
    }
    return oo::PList(std::move(result));
}

- (void)setName:(id)value // shared selector (Foundation declares -setName: too; retires with oo-qps)
{
    [self cxx_setName:oo::OptionalString(value)];
}

- (void)cxx_setName:(const std::optional<std::string>&)value
{
    _name = value;
}

- (void)setShortDescription:(id)value
{
    _shortDescription = oo::OptionalString(value);
}

- (void)setOriginSystem:(OOSystemID)value
{
    _originSystem = value;
}

- (void)setGenSeed:(Random_Seed)value
{
    _genSeed = value;
}

- (void)setLegalStatus:(int)value
{
    _legalStatus = value;
}

- (void)setInsuranceCredits:(OOCreditsQuantity)value
{
    _insuranceCredits = value;
}

- (void)setLegacyScript:(const oo::PList&)some_actions
{
    _scriptActions = some_actions;
}

- (OOJSScript*)script
{
    return _script;
}

- (void)setCharacterScript:(const std::string&)scriptName
{
    [_script autorelease];
    _script = [OOScript cxx_jsScriptFromFileNamed:scriptName
                                       properties:oo::PList(oo::PList::Dict { { "character", oo::PListObject(self) } })];
    [_script retain];
}

- (void)doScriptEvent:(OOJSPropID)message
{
    JSContext* context = OOJSAcquireContext();
    [_script callMethod:message inContext:context withArguments:NULL count:0 result:NULL];
    OOJSRelinquishContext(context);
}

- (void)setCharacterFromDictionary:(const oo::PList&)dict
{
    const oo::PList* origin = nullptr;
    Random_Seed seed;

    origin = dict.find("origin");
    // (a string, a number, or another object that answers -intValue: an Object node)
    const std::string* originName = (origin != nullptr) ? origin->getIf<std::string>() : nullptr;
    id originObject = (origin != nullptr) ? oo::ObjectIn(*origin) : nil;
    const int originValue = (originObject != nil) ? ([originObject respondsToSelector:@selector(intValue)] ? [originObject intValue] : 0) : dict.get<int>("origin");
    if ((origin != nullptr && origin->isNumber()) || (((originName != nullptr) || [originObject respondsToSelector:@selector(intValue)]) && (originValue != 0 || (originName != nullptr && *originName == "0")))) {
        // Number or numerical string
        [self setOriginSystem:originValue];
    } else if (originName != nullptr) {
        OOSystemID sys = [UNIVERSE cxx_findSystemFromName:*originName];
        if (sys < 0) {
            OO_LOG_ERR("character.load.unknownSystem", "could not find a system named '{}' in this galaxy.", *originName);
            [self setOriginSystem:(ranrot_rand() & 0xff)];
        } else {
            [self setOriginSystem:sys];
        }
    } else {
        // no origin defined, select one at random.
        [self setOriginSystem:(ranrot_rand() & 0xff)];
    }

    if (dict.find("random_seed") != nullptr) {
        seed = cxx_RandomSeedFromString(OptionalStringForKey(dict, "random_seed")); // returns kNilRandomSeed on failure
    } else {
        seed.a = (ranrot_rand() & 0xff);
        seed.b = (ranrot_rand() & 0xff);
        seed.c = (ranrot_rand() & 0xff);
        seed.d = (ranrot_rand() & 0xff);
        seed.e = (ranrot_rand() & 0xff);
        seed.f = (ranrot_rand() & 0xff);
    }
    [self setGenSeed:seed];
    [self basicSetUp];

    if (const std::optional<std::string> role = OptionalStringForKey(dict, "role"))
        [self castInRole:*role];
    if (const std::optional<std::string> name = OptionalStringForKey(dict, "name"))
        _name = name;
    if (const std::optional<std::string> shortDescription = OptionalStringForKey(dict, "short_description"))
        _shortDescription = shortDescription;
    if (dict.find("legal_status") != nullptr)
        [self setLegalStatus:dict.get<int>("legal_status")];
    if (dict.find("bounty") != nullptr)
        [self setLegalStatus:dict.get<int>("bounty")];
    if (dict.find("insurance") != nullptr)
        [self setInsuranceCredits:dict.get<unsigned long long>("insurance")];
    if (const std::optional<std::string> script = OptionalStringForKey(dict, "script"))
        [self setCharacterScript:*script];
    if (const oo::PList* scriptActions = dict.get<oo::PList::Array>("script_actions"))
        [self setLegacyScript:*scriptActions];
}

@end
