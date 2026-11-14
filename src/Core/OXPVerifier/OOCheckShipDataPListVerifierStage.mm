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
#import "OOFoundationBridge.h"
#import "OOPListSchemaVerifier.h"
#import "OOPListView.h"
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

} // namespace

@interface OOCheckShipDataPListVerifierStage (OOPrivate)

- (void)verifyShipInfo:(const oo::PList&)info withName:(const std::string&)name;

- (void)message:(id)format, ...; // an Objective-C format string. Shared selector (AI; proposed ADR-0043).
- (void)verboseMessage:(const char*)format, ...;

- (void)getRoles;
- (void)checkKeys;
- (void)checkSchema;
- (void)checkModel;

- (std::vector<std::string>)rolesFromString:(const std::string&)string;

@end

@implementation OOCheckShipDataPListVerifierStage

- (id)name // shared selector (proposed ADR-0043)
{
    return oo::NSStringFrom(kStageName);
}

- (id)dependents // shared selector (proposed ADR-0043)
{
    std::vector<std::string> result = oo::StringsFrom([super dependents]);
    for (id reverse : { [OOModelVerifierStage nameForReverseDependencyForVerifier:[self verifier]],
             [OOAIStateMachineVerifierStage nameForReverseDependencyForVerifier:[self verifier]] }) {
        const std::string name = oo::StdString(reverse);
        if (std::find(result.begin(), result.end(), name) == result.end())
            result.push_back(name);
    }
    return oo::NSSetFromStrings(result);
}

- (BOOL)shouldRun
{
    OOFileScannerVerifierStage* fileScanner = nil;

    fileScanner = [[self verifier] fileScannerStage];
    return [fileScanner fileExists:@"shipdata.plist"
                          inFolder:@"Config"
                    referencedFrom:nil
                      checkBuiltIn:NO];
}

- (void)run
{
    OOFileScannerVerifierStage* fileScanner = nil;
    std::vector<std::string> ooliteShipData; // the keys of Oolite's own merged shipdata.plist
    oo::PList settings;
    std::vector<std::string> shipList;

    fileScanner = [[self verifier] fileScannerStage];
    _shipdataPList = oo::PListFrom([fileScanner plistNamed:@"shipdata.plist"
                                                  inFolder:@"Config"
                                            referencedFrom:nil
                                              checkBuiltIn:NO]);

    if (_shipdataPList.isNull())
        return;

    // Get AI verifier stage (may be nil).
    _aiVerifierStage = [[self verifier] stageWithName:[OOAIStateMachineVerifierStage nameForReverseDependencyForVerifier:[self verifier]]];

    ooliteShipData = oo::StringsFrom([ResourceManager dictionaryFromFilesNamed:@"shipdata.plist"
                                                                      inFolder:@"Config"
                                                                      andMerge:YES]);

    // Check that it's a dictionary
    if (!_shipdataPList.isDict()) {
        OOLog(@"verifyOXP.shipdataPList.notDict", @"%@", @"***** ERROR: shipdata.plist is not a dictionary.");
        return;
    }

    // Keys that apply to all ships
    for (const std::string& shipName : ooliteShipData)
        AddString(_ooliteShipNames, shipName);
    settings = oo::PListFrom([[self verifier] configurationDictionaryForKey:@"shipdataPListSettings"]);
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

    _schemaVerifier = [OOPListSchemaVerifier verifierWithSchema:oo::PListFrom([ResourceManager dictionaryFromFilesNamed:@"shipdataEntrySchema.plist" inFolder:@"Schemata" andMerge:NO])];
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
                OOLog(@"verifyOXP.shipdata.badType", @"***** ERROR: shipdata.plist entry for \"%@\" is not a dictionary.", oo::NSStringFrom(shipKey));
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
    OOLogPushIndent();

    [self getRoles];
    [self checkKeys];
    [self checkSchema];
    [self checkModel];

    const std::optional<std::string> aiName = OptionalStringForKey(info, "ai_type");
    if (aiName.has_value()) {
        if (!oo::str::hasSuffix(*aiName, ".js")) {
            [_aiVerifierStage stateMachineNamed:*aiName usedByShip:name];
        }
    }

    // Todo: check for pirates with 0 bounty

    OOLogPopIndent();
    if (!_havePrintedMessage) {
        OOLog(@"verifyOXP.verbose.shipData.OK", @"- ship \"%@\" OK.", oo::NSStringFrom(_name));
    }
    _name.clear();
    _info = oo::PList();
    _roles.clear();
}

// Custom log method to group messages by ship.
- (void)message:(id)format, ...
{
    va_list args;

    if (!_havePrintedMessage) {
        OOLog(@"verifyOXP.shipData.firstMessage", @"Ship \"%@\":", oo::NSStringFrom(_name));
        OOLogIndent();
        _havePrintedMessage = YES;
    }

    va_start(args, format);
    OOLogWithFunctionFileAndLineAndArguments(@"verifyOXP.shipData", NULL, NULL, 0, format, args);
    va_end(args);
}

- (void)verboseMessage:(const char*)format, ...
{
    va_list args;

    if (!OOLogWillDisplayMessagesInClass(@"verifyOXP.verbose.shipData"))
        return;

    if (!_havePrintedMessage) {
        OOLog(@"verifyOXP.shipData.firstMessage", @"Ship \"%@\":", oo::NSStringFrom(_name));
        OOLogIndent();
        _havePrintedMessage = YES;
    }

    va_start(args, format);
    OOLogWithFunctionFileAndLineAndArguments(@"verifyOXP.verbose.shipData", NULL, NULL, 0, oo::NSStringFrom(format), args);
    va_end(args);
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
        [self message:@"***** ERROR: ship is both a player ship and a station. Treating as non-station."];
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
                    [self message:@"----- WARNING: key \"%@\" does not apply to this category of ship.", oo::NSStringFrom(key)];
                }
            } else {
                [self message:@"----- WARNING: unknown key \"%@\".", oo::NSStringFrom(key)];
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
            [self message:@"----- WARNING: model \"%@\" could not be found in %@ or in Oolite.", oo::NSStringFrom(*model), [[self verifier] oxpDisplayName]];
        }
    } else {
        if (!OptionalStringForKey(_info, "like_ship").has_value()) {
            [self message:@"***** ERROR: ship does not specify model or like_ship."];
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
    withPropertyList:(id)rootPList
               named:(id)name
        testProperty:(id)subPList
              atPath:(id)keyPath
         againstType:(id)typeKey
               error:(NSError**)outError // shared selector (OOPListSchemaVerifierDelegate; proposed ADR-0043)
{
    [self verboseMessage:"- Skipping verification for type %@ at %@.%@.", typeKey, oo::NSStringFrom(_name), oo::NSStringOrNil([OOPListSchemaVerifier descriptionForKeyPath:oo::PListFrom(keyPath)])];
    return YES;
}

- (BOOL)verifier:(OOPListSchemaVerifier*)verifier
     withPropertyList:(id)rootPList
                named:(id)name
    failedForProperty:(id)subPList
            withError:(NSError*)error
         expectedType:(id)localSchema // shared selector (OOPListSchemaVerifierDelegate; proposed ADR-0043)
{
    // FIXME: use fancy new error codes to provide useful error descriptions.
    [self message:@"***** ERROR: verification of ship \"%@\" failed at \"%@\": %@", name, oo::NSStringOrNil([OOPListSchemaVerifier descriptionForKeyPath:oo::PListFrom([[error userInfo] objectForKey:oo::NSStringFrom(kPListKeyPathErrorKey)])]), [error localizedFailureReason]];
    return YES;
}

@end

#endif
