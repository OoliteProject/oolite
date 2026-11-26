/*

OOCheckShipDataPListVerifierStage.m


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

#import "OOCheckShipDataPListVerifierStage.h"
#import "OOModelVerifierStage.h"

#if OO_OXP_VERIFIER_ENABLED

#import "OOAIStateMachineVerifierStage.h"
#import "OOFileScannerVerifierStage.h"
#import "OOPListSchemaVerifier.h"
#import "OOStringParsing.h"
#import "ResourceManager.h"

#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"

static const char* const kStageName = "Checking shipdata.plist";

namespace {

// Adding to a set of strings kept as a sorted vector.
void AddString(std::vector<std::string>& set, const std::string& string)
{
    const auto where = std::lower_bound(set.begin(), set.end(), string);
    if (where == set.end() || *where != string)
        set.insert(where, string);
}

bool ContainsString(const std::vector<std::string>& set, const std::string& string)
{
    return std::binary_search(set.begin(), set.end(), string);
}

// The extractors' set-for-key read: the strings of an array value as a set (sorted vector); empty where it was nil.
std::vector<std::string> StringSetForKey(const oo::PList& dictionary, std::string_view key)
{
    std::vector<std::string> result;
    if (const oo::PList* array = dictionary.get<oo::PList::Array>(key)) {
        for (const oo::PList& element : *array->getIf<oo::PList::Array>()) {
            if (const std::string* string = element.getIf<std::string>())
                AddString(result, *string);
        }
    }
    return result;
}

// The extractors' string-for-key read: a string, or a number's string value; nullopt where it answered nil.
std::optional<std::string> OptionalStringForKey(const oo::PList& dictionary, std::string_view key)
{
    const oo::PList* value = dictionary.get<oo::PList>(key);
    if (value == nullptr || !(value->isString() || value->isNumber()))
        return std::nullopt;
    return dictionary.get<std::string>(key);
}

// A %@ argument that was oo::NSStringOrNil(text): "(null)" for nullopt (bead oo-qps.24).
oo::str::FormatArg TextOrNull(const std::optional<std::string>& text)
{
    return text.has_value() ? oo::str::FormatArg(*text) : oo::str::FormatArg::null();
}

} // namespace

@interface OOCheckShipDataPListVerifierStage (OOPrivate)

- (void)verifyShipInfo:(const oo::PList&)info withName:(const std::string&)name;

- (void)reportMessage:(const std::string&)message; // formatted by the caller, oo::str::formatRuntime (was -message:, renamed so AI's -message: could flip; bead oo-3rb.276; bead oo-qps.24)
- (void)verboseMessage:(const std::string&)message;

- (void)getRoles;
- (void)checkKeys;
- (void)checkSchema;
- (void)checkModel;

- (std::vector<std::string>)rolesFromString:(const std::string&)string;

@end

@implementation OOCheckShipDataPListVerifierStage

- (std::optional<std::string>)cxx_name
{
    return kStageName;
}

- (std::optional<std::vector<std::string>>)dependents
{
    std::vector<std::string> result = [super dependents].value_or(std::vector<std::string>());
    for (const std::string& name : { [OOModelVerifierStage nameForReverseDependencyForVerifier:[self verifier]],
             OOAIStateMachineVerifierStage::nameForReverseDependencyForVerifier([self verifier]) }) {
        if (std::find(result.begin(), result.end(), name) == result.end())
            result.push_back(name);
    }
    return result;
}

- (BOOL)shouldRun
{
    OOFileScannerVerifierStage* fileScanner = nil;

    fileScanner = [[self verifier] fileScannerStage];
    return [fileScanner cxx_fileExists:"shipdata.plist" inFolder:"Config" referencedFrom:std::nullopt checkBuiltIn:NO];
}

- (void)run
{
    OOFileScannerVerifierStage* fileScanner = nil;
    std::vector<std::string> ooliteShipData; // the keys of Oolite's own merged shipdata.plist
    oo::PList settings;
    std::vector<std::string> shipList;

    fileScanner = [[self verifier] fileScannerStage];
    _shipdataPList = [fileScanner cxx_plistNamed:"shipdata.plist" inFolder:"Config" referencedFrom:std::nullopt checkBuiltIn:NO];

    if (_shipdataPList.isNull())
        return;

    // Get AI verifier stage (may be null). C++ since bead oo-94qk; the verifier holds it as its facade.
    _aiVerifierStage = static_cast<OOAIStateMachineVerifierStage*>(oo::ToCxx(static_cast<OOOXPVerifierStage*>([[self verifier] cxx_stageWithName:OOAIStateMachineVerifierStage::nameForReverseDependencyForVerifier([self verifier])])));

    const oo::PList ooliteShipDataPList = [ResourceManager cxx_dictionaryFromFilesNamed:"shipdata.plist" inFolder:"Config" andMerge:YES];
    if (const oo::PList::Dict* shipDataDict = ooliteShipDataPList.getIf<oo::PList::Dict>()) {
        for (const auto& [shipKey, shipEntry] : *shipDataDict)
            ooliteShipData.push_back(shipKey); // byte order of the key (hash order before; only used as a set)
    }

    // Check that it's a dictionary
    if (!_shipdataPList.isDict()) {
        OO_LOG("verifyOXP.shipdataPList.notDict", "{}", "***** ERROR: shipdata.plist is not a dictionary.");
        return;
    }

    // Keys that apply to all ships
    for (const std::string& shipName : ooliteShipData)
        AddString(_ooliteShipNames, shipName);
    settings = [[self verifier] cxx_configurationDictionaryForKey:"shipdataPListSettings"];
    _basicKeys = StringSetForKey(settings, "knownShipKeys");

    // Keys that apply to stations/carriers
    _stationKeys = _basicKeys;
    for (const std::string& key : StringSetForKey(settings, "knownStationKeys"))
        AddString(_stationKeys, key);

    // Keys that apply to player ships
    _playerKeys = _basicKeys;
    for (const std::string& key : StringSetForKey(settings, "knownPlayerKeys"))
        AddString(_playerKeys, key);

    // Keys that apply to _any_ ship -- union of the above
    _allKeys = _playerKeys;
    for (const std::string& key : _stationKeys)
        AddString(_allKeys, key);

    _schemaVerifier = [OOPListSchemaVerifier verifierWithSchema:[ResourceManager cxx_dictionaryFromFilesNamed:"shipdataEntrySchema.plist" inFolder:"Schemata" andMerge:NO]];
    [_schemaVerifier setDelegate:self];

    for (const auto& [shipKey, value] : *_shipdataPList.getIf<oo::PList::Dict>())
        shipList.push_back(shipKey);
    std::stable_sort(shipList.begin(), shipList.end(), [](const std::string& a, const std::string& b) {
        return oo::str::caseInsensitiveCompare(a, b) < 0;
    });
    for (const std::string& shipKey : shipList) {
        @autoreleasepool {
            const oo::PList* shipInfo = _shipdataPList.get<oo::PList::Dict>(shipKey);
            if (shipInfo == nullptr) {
                OO_LOG("verifyOXP.shipdata.badType", "***** ERROR: shipdata.plist entry for \"{}\" is not a dictionary.", shipKey);
            } else {
                [self verifyShipInfo:*shipInfo withName:shipKey];
            }
        }
    }

    _shipdataPList = oo::PList();
    _ooliteShipNames.clear();
    _basicKeys.clear();
    _stationKeys.clear();
    _playerKeys.clear();
}

@end

@implementation OOCheckShipDataPListVerifierStage (OOPrivate)

- (void)verifyShipInfo:(const oo::PList&)info withName:(const std::string&)name
{
    _name = name;
    _info = info;
    _havePrintedMessage = NO;
    oo::log::pushIndent();

    [self getRoles];
    [self checkKeys];
    [self checkSchema];
    [self checkModel];

    const std::optional<std::string> aiName = OptionalStringForKey(info, "ai_type");
    if (aiName.has_value()) {
        if (!oo::str::hasSuffix(*aiName, ".js")) {
            if (_aiVerifierStage != nullptr)
                _aiVerifierStage->stateMachineNamed(*aiName, name);
        }
    }

    // Todo: check for pirates with 0 bounty

    oo::log::popIndent();
    if (!_havePrintedMessage) {
        OO_LOG("verifyOXP.verbose.shipData.OK", "- ship \"{}\" OK.", _name);
    }
    _name.clear();
    _info = oo::PList();
    _roles.clear();
}

// Custom log method to group messages by ship.
- (void)reportMessage:(const std::string&)message
{
    if (!_havePrintedMessage) {
        OO_LOG("verifyOXP.shipData.firstMessage", "Ship \"{}\":", _name);
        oo::log::indent();
        _havePrintedMessage = YES;
    }

    if (oo::log::willDisplay("verifyOXP.shipData")) {
        oo::log::logger().write("verifyOXP.shipData", NULL, NULL, 0, message);
    }
}

- (void)verboseMessage:(const std::string&)message
{
    if (!oo::log::willDisplay("verifyOXP.verbose.shipData"))
        return;

    if (!_havePrintedMessage) {
        OO_LOG("verifyOXP.shipData.firstMessage", "Ship \"{}\":", _name);
        oo::log::indent();
        _havePrintedMessage = YES;
    }

    oo::log::logger().write("verifyOXP.verbose.shipData", NULL, NULL, 0, message);
}

- (void)getRoles
{
    std::optional<std::string> rolesString;

    if (const oo::PList* roles = _info.find("roles")) {
        if (const std::string* string = roles->getIf<std::string>())
            rolesString = *string;
    }
    _roles = [self rolesFromString:rolesString.value_or("")];
    _isPlayer = ContainsString(_roles, "player");
    // A nil roles string answered -rangeOfString: with location 0 (found), as messaging nil does.
    _isStation = _info.get<bool>("is_carrier", false) || _info.get<bool>("isCarrier", false) || !rolesString.has_value() || rolesString->find("station") != std::string::npos || rolesString->find("carrier") != std::string::npos;
    // the is_carrier or isCarrier key will be missed when it was insise a like_ship definition.
    _isTemplate = _info.get<bool>("is_template", false);

    if (_isPlayer && _isStation) {
        [self reportMessage:"***** ERROR: ship is both a player ship and a station. Treating as non-station."];
        _isStation = NO;
    }
}

- (void)checkKeys
{
    const std::vector<std::string>* referenceSet = nullptr;

    if (_isPlayer)
        referenceSet = &_playerKeys;
    else if (_isStation)
        referenceSet = &_stationKeys;
    else
        referenceSet = &_basicKeys;

    for (const auto& [key, value] : *_info.getIf<oo::PList::Dict>()) {
        if (!ContainsString(*referenceSet, key)) {
            if (ContainsString(_allKeys, key)) {
                if (!_isTemplate) {
                    // if it's a template, this key might apply to a descendant
                    // as happens in the core files
                    [self reportMessage:oo::str::formatRuntime("----- WARNING: key \"%@\" does not apply to this category of ship.", { key })];
                }
            } else {
                [self reportMessage:oo::str::formatRuntime("----- WARNING: unknown key \"%@\".", { key })];
            }
        }
    }
}

- (void)checkSchema
{
    [_schemaVerifier verifyPropertyList:_info named:_name];
}

- (void)checkModel
{
    const std::optional<std::string> model = OptionalStringForKey(_info, "model");
    const oo::PList* materials = _info.get<oo::PList::Dict>("materials");
    const oo::PList* shaders = _info.get<oo::PList::Dict>("shaders");

    if (model.has_value()) {
        if (![[[self verifier] modelVerifierStage] modelNamed:*model
                                                 usedForEntry:_name
                                                       inFile:"shipdata.plist"
                                                withMaterials:materials != nullptr ? *materials : oo::PList()
                                                   andShaders:shaders != nullptr ? *shaders : oo::PList()]) {
            [self reportMessage:oo::str::formatRuntime("----- WARNING: model \"%@\" could not be found in %@ or in Oolite.", { *model, TextOrNull([[self verifier] cxx_oxpDisplayName]) })];
        }
    } else {
        if (!OptionalStringForKey(_info, "like_ship").has_value()) {
            [self reportMessage:"***** ERROR: ship does not specify model or like_ship."];
        }
    }
}

// Convert a roles string to a set of role names, discarding probabilities.
- (std::vector<std::string>)rolesFromString:(const std::string&)string
{
    std::vector<std::string> result;

    for (std::string role : oo::str::tokens(string)) {
        const std::size_t paren = role.find('(');
        if (paren != std::string::npos) {
            role = role.substr(0, paren);
        }
        AddString(result, role);
    }

    return result;
}

- (BOOL)verifier:(OOPListSchemaVerifier*)verifier
    withPropertyList:(const oo::PList&)rootPList
               named:(const std::string&)name
        testProperty:(const oo::PList&)subPList
              atPath:(const oo::PList&)keyPath
         againstType:(const oo::PList&)typeKey
               error:(std::optional<OOPListSchemaVerifierError>*)outError
{
    [self verboseMessage:oo::str::formatRuntime("- Skipping verification for type %@ at %@.%@.", { oo::DescriptionOf(typeKey), _name, TextOrNull([OOPListSchemaVerifier descriptionForKeyPath:keyPath]) })];
    return YES;
}

- (BOOL)verifier:(OOPListSchemaVerifier*)verifier
     withPropertyList:(const oo::PList&)rootPList
                named:(const std::string&)name
    failedForProperty:(const oo::PList&)subPList
            withError:(const OOPListSchemaVerifierError&)error
         expectedType:(const oo::PList&)localSchema
{
    // FIXME: use fancy new error codes to provide useful error descriptions.
    [self reportMessage:oo::str::formatRuntime("***** ERROR: verification of ship \"%@\" failed at \"%@\": %@", { name, TextOrNull([OOPListSchemaVerifier descriptionForKeyPath:(error.userInfo.find(kPListKeyPathErrorKey) != nullptr) ? *error.userInfo.find(kPListKeyPathErrorKey) : oo::PList()]), TextOrNull(error.failureReason) })];
    return YES;
}

@end

#endif
