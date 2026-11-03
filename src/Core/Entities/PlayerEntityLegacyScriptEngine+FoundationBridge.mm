/*

PlayerEntityLegacyScriptEngine+FoundationBridge.mm

TRANSITIONAL: see PlayerEntityLegacyScriptEngine+FoundationBridge.h. Each method forwards to its
cxx_ counterpart and converts the result exactly as the old method produced it (nil for nil).

*/

#import "OOFoundationBridge.h"
#import "PlayerEntityLegacyScriptEngine.h" // declares the bridge category at its end

@implementation PlayerEntity (ScriptingFoundationBridge)

- (void)runScriptActions:(NSArray*)sanitizedActions withContextName:(NSString*)contextName forTarget:(ShipEntity*)target
{
    [self cxx_runScriptActions:oo::PListFrom(sanitizedActions) withContextName:oo::OptionalString(contextName) forTarget:target];
}

- (void)runUnsanitizedScriptActions:(NSArray*)unsanitizedActions allowingAIMethods:(BOOL)allowAIMethods withContextName:(NSString*)contextName forTarget:(ShipEntity*)target
{
    [self cxx_runUnsanitizedScriptActions:oo::PListFrom(unsanitizedActions) allowingAIMethods:allowAIMethods withContextName:oo::OptionalString(contextName) forTarget:target];
}

- (BOOL)scriptTestConditions:(NSArray*)array
{
    return [self cxx_scriptTestConditions:oo::PListFrom(array)];
}

- (NSDictionary*)missionVariables
{
    return mission_variables;
}

- (NSString*)missionVariableForKey:(NSString*)key
{
    if (key == nil)
        return nil;
    return oo::ObjectFromPList([self cxx_missionVariableForKey:oo::StdString(key)]);
}

- (void)setMissionVariable:(NSString*)value forKey:(NSString*)key
{
    if (key == nil)
        return;
    [self cxx_setMissionVariable:oo::PListFrom(value) forKey:oo::StdString(key)];
}

- (NSArray*)missionsList
{
    return oo::ObjectFromPList([self cxx_missionsList]);
}

- (void)setMissionInstructions:(NSString*)text forMission:(NSString*)key
{
    [self cxx_setMissionInstructions:oo::StdString(text) forMission:oo::OptionalString(key)];
}

- (void)setMissionInstructionsList:(NSArray*)list forMission:(NSString*)key
{
    [self cxx_setMissionInstructionsList:oo::PListFrom(list) forMission:oo::OptionalString(key)];
}

- (NSString*)missionTitle
{
    return oo::NSStringOrNil([self cxx_missionTitle]);
}

- (void)setMissionTitle:(NSString*)value
{
    [self cxx_setMissionTitle:oo::OptionalString(value)];
}

- (void)setMissionChoicesDictionary:(NSDictionary*)choicesDict
{
    /* Guard against potential for numeric keys in dictionary, which
     * would cause an unhandled exception in the sorter. See
     * OOJavaScriptEngine::OOJSDictionaryFromJSObject for further
     * thoughts. - CIM 15/2/13
     * An oo::PList Dict is keyed by strings, so a non-string key is logged as before and then
     * stands for its description; the choices are then sorted, where they used to be left in
     * hash order.
     */
    oo::PList::Dict choices;
    for (id key in [choicesDict allKeys]) {
        if (!oo::IsNSString(key)) {
            OOLog(@"test.script.error", @"Choices list in mission screen has non-string value %@", key);
        }
        choices[oo::IsNSString(key) ? oo::StdString(key) : oo::DescriptionOf(key)] = oo::PListFrom([choicesDict objectForKey:key]);
    }
    [self cxx_setMissionChoicesDictionary:oo::PList(std::move(choices))];
}

- (void)setMissionScreenID:(NSString*)msid
{
    [self cxx_setMissionScreenID:oo::OptionalString(msid)];
}

- (NSString*)missionScreenID
{
    return oo::NSStringOrNil([self cxx_missionScreenID]);
}

- (BOOL)addEqScriptForKey:(NSString*)eq_key
{
    if (eq_key == nil)
        return NO;
    return [self cxx_addEqScriptForKey:oo::StdString(eq_key)];
}

- (void)removeEqScriptForKey:(NSString*)eq_key
{
    if (eq_key == nil)
        return;
    [self cxx_removeEqScriptForKey:oo::StdString(eq_key)];
}

- (NSUInteger)eqScriptIndexForKey:(NSString*)eq_key
{
    if (eq_key == nil)
        return eqScripts.size();
    return [self cxx_eqScriptIndexForKey:oo::StdString(eq_key)];
}

- (void)setBackgroundFromDescriptionsKey:(NSString*)d_key
{
    if (d_key == nil)
        return; // (no description has a nil key)
    [self cxx_setBackgroundFromDescriptionsKey:oo::StdString(d_key)];
}

@end

NSString* OOComparisonTypeToString(OOComparisonType type)
{
    return oo::NSStringFrom(cxx_OOComparisonTypeToString(type));
}
