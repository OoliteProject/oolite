/*

NSUserDefaults+OODefaultsBridge.mm

TRANSITIONAL: see NSUserDefaults+OODefaultsBridge.h. GNUstep's +standardUserDefaults object is
retargeted, once, to OODefaultsBackedUserDefaults, whose preference methods forward to
oo::Defaults.

Oolite
Copyright (C) 2004-2025 Giles C Williams and contributors
GPL v2 or later; see NSUserDefaults+Override.h.

*/

#import "NSUserDefaults+OODefaultsBridge.h"

#import <objc/runtime.h>

#import "GameController.h" // OOScheduleDeferredCall (ADR-0040)
#import "OOFoundationBridge.h"
#include "oofnd/Defaults.hpp"
#include "oofnd/Thread.hpp"

#include <atomic>

namespace {
std::atomic<oo::Defaults*> sStore { nullptr }; // nullptr: oo::Defaults::standard()
std::atomic<bool> sInstalled { false };

/*	gnustep-base's automatic save: its standard defaults object runs a repeating 30-second timer,
        started when the object is made, that sends -synchronize whether or not anything changed
        (probed on gnustep-base 1.31.1, bead oo-xeve: a change 13.1 s after creation was written at
        30.1 s; with -setObject:forKey: overridden so GNUstep's own store never changed, -synchronize
        still arrived at 30.0 s and 60.0 s). That timer lives on the run loop, which the frame loop
        pumps until oo-3rb.58 removes the pump; this deferred call keeps the save when it goes. The
        first change after a save schedules one -synchronize kOODefaultsAutoSaveInterval seconds later
        (a change is written at most that long after it was made, as with GNUstep's timer; the file is
        written only if something changed, ADR-0032 point 3).
*/
constexpr NSTimeInterval kOODefaultsAutoSaveInterval = 30.0;
bool sAutoSaveScheduled = false; // main thread only, as the deferred calls are

oo::Defaults& Store()
{
    oo::Defaults* store = sStore.load();
    return (store != nullptr) ? *store : oo::Defaults::standard();
}
}

void OODefaultsBridgeSetStore(oo::Defaults* store)
{
    sStore.store(store);
}

bool OODefaultsBridgeIsInstalled(void)
{
    return sInstalled.load();
}

// The class GNUstep's standard defaults object is given. No instance variables, so the object
// GNUstep built stays valid; everything not overridden here is GNUstep's.
@interface OODefaultsBackedUserDefaults : NSUserDefaults
@end

@implementation OODefaultsBackedUserDefaults

+ (void)initialize
{
    // Not NSUserDefaults' +initialize again: it already ran for the class GNUstep instantiated.
}

// A key oo::Defaults has no value for is one of GNUstep's own settings, which live in the domains
// oo::Defaults does not model (ADR-0032 point 6): the language domains and GSConfigDomain, then
// GNUstep's registration domain, as GNUstep's search list orders them. The argument domain and
// the persistent domains are oo::Defaults' (the same command line and files).
- (id)oo_gnustepObjectForKey:(NSString*)key
{
    NSArray* names = [super volatileDomainNames];
    for (NSString* name in names) {
        if ([name isEqualToString:NSArgumentDomain] || [name isEqualToString:NSRegistrationDomain])
            continue;
        id value = [[super volatileDomainForName:name] objectForKey:key];
        if (value != nil)
            return value;
    }
    return [[super volatileDomainForName:NSRegistrationDomain] objectForKey:key];
}

- (BOOL)oo_storeHasKey:(NSString*)key
{
    return !Store().object(oo::StdString(key)).isNull();
}

- (void)oo_didChange
{
    [[NSNotificationCenter defaultCenter] postNotificationName:NSUserDefaultsDidChangeNotification object:self];

    // Deferred calls run on the main thread only (a call scheduled elsewhere would never fire).
    if (!sAutoSaveScheduled && oo::thread::isMainThread()) {
        sAutoSaveScheduled = true;
        OOScheduleDeferredCall(self, @selector(oo_autoSave), nil, kOODefaultsAutoSaveInterval);
    }
}

- (void)oo_autoSave
{
    sAutoSaveScheduled = false;
    [self synchronize];
}

// --- reading ------------------------------------------------------------------------------------
// With the key in oo::Defaults, its own getters (NSUserDefaults' coercions, ADR-0032 point 3);
// without, GNUstep's, which read -objectForKey: and so the domains above.

- (id)objectForKey:(NSString*)defaultName
{
    const oo::PList value = Store().object(oo::StdString(defaultName));
    if (!value.isNull())
        return oo::ObjectFromPList(value);
    return [self oo_gnustepObjectForKey:defaultName];
}

- (NSString*)stringForKey:(NSString*)defaultName
{
    if (![self oo_storeHasKey:defaultName])
        return [super stringForKey:defaultName];
    return oo::NSStringOrNil(Store().stringForKey(oo::StdString(defaultName)));
}

- (NSArray*)arrayForKey:(NSString*)defaultName
{
    if (![self oo_storeHasKey:defaultName])
        return [super arrayForKey:defaultName];
    return oo::ObjectFromPList(Store().arrayForKey(oo::StdString(defaultName)));
}

- (NSDictionary*)dictionaryForKey:(NSString*)defaultName
{
    if (![self oo_storeHasKey:defaultName])
        return [super dictionaryForKey:defaultName];
    return oo::ObjectFromPList(Store().dictionaryForKey(oo::StdString(defaultName)));
}

- (BOOL)boolForKey:(NSString*)defaultName
{
    if (![self oo_storeHasKey:defaultName])
        return [super boolForKey:defaultName];
    return Store().boolForKey(oo::StdString(defaultName)) ? YES : NO;
}

- (NSInteger)integerForKey:(NSString*)defaultName
{
    if (![self oo_storeHasKey:defaultName])
        return [super integerForKey:defaultName];
    return static_cast<NSInteger>(Store().integerForKey(oo::StdString(defaultName)));
}

- (float)floatForKey:(NSString*)defaultName
{
    if (![self oo_storeHasKey:defaultName])
        return [super floatForKey:defaultName];
    return Store().floatForKey(oo::StdString(defaultName));
}

- (double)doubleForKey:(NSString*)defaultName
{
    if (![self oo_storeHasKey:defaultName])
        return [super doubleForKey:defaultName];
    return Store().doubleForKey(oo::StdString(defaultName));
}

// --- writing (oo::Defaults' application domain; only its synchronize() writes the file) --------

- (void)setObject:(id)value forKey:(NSString*)defaultName
{
    const std::string key = oo::StdString(defaultName);
    oo::PList plist = oo::PListFrom(value);
    // A float NSNumber is remembered as one, so it is written %.7g as GNUstep wrote it.
    if (plist.isSinglePrecision())
        Store().setFloat(key, static_cast<float>(plist.doubleValue()));
    else
        Store().setObject(key, std::move(plist)); // nil (a null PList) removes the key, as in GNUstep
    [self oo_didChange];
}

- (void)setBool:(BOOL)value forKey:(NSString*)defaultName
{
    Store().setBool(oo::StdString(defaultName), value);
    [self oo_didChange];
}

- (void)setInteger:(NSInteger)value forKey:(NSString*)defaultName
{
    Store().setInteger(oo::StdString(defaultName), value);
    [self oo_didChange];
}

- (void)setFloat:(float)value forKey:(NSString*)defaultName
{
    Store().setFloat(oo::StdString(defaultName), value);
    [self oo_didChange];
}

- (void)setDouble:(double)value forKey:(NSString*)defaultName
{
    Store().setDouble(oo::StdString(defaultName), value);
    [self oo_didChange];
}

- (void)removeObjectForKey:(NSString*)defaultName
{
    Store().removeObject(oo::StdString(defaultName));
    [self oo_didChange];
}

- (void)registerDefaults:(NSDictionary*)registrationDictionary
{
    const oo::PList values = oo::PListFrom(registrationDictionary);
    if (const oo::PList::Dict* dict = values.getIf<oo::PList::Dict>())
        Store().registerDefaults(*dict);
}

- (BOOL)synchronize
{
    return Store().synchronize() ? YES : NO;
}

@end

@implementation NSUserDefaults (OODefaultsBridge)

// Exchange +standardUserDefaults with the wrapper below. Runtime calls only: no message is sent,
// so no class is initialised before the process is set up.
+ (void)load
{
    Class meta = objc_getMetaClass("NSUserDefaults");
    Method original = class_getInstanceMethod(meta, @selector(standardUserDefaults));
    Method wrapper = class_getInstanceMethod(meta, @selector(oo_defaultsBridgeStandardUserDefaults));
    if (original != NULL && wrapper != NULL)
        method_exchangeImplementations(original, wrapper);
}

+ (NSUserDefaults*)oo_defaultsBridgeStandardUserDefaults
{
    NSUserDefaults* defaults = [self oo_defaultsBridgeStandardUserDefaults]; // GNUstep's own, since the exchange
    if (defaults != nil && object_getClass(defaults) == objc_getClass("NSUserDefaults")) {
        object_setClass(defaults, [OODefaultsBackedUserDefaults class]);
    }
    if (defaults != nil && object_getClass(defaults) == [OODefaultsBackedUserDefaults class])
        sInstalled.store(true);
    return defaults;
}

@end
