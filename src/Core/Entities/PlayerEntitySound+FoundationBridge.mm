/*

PlayerEntitySound+FoundationBridge.mm

TRANSITIONAL: see PlayerEntitySound+FoundationBridge.h. Each method forwards to its cxx_
counterpart (a nil identifier arrives as "", which names no weapon, as nil found no sound).

*/

#import "OOFoundationBridge.h"
#import "PlayerEntitySound.h" // declares the bridge category at its end

@implementation PlayerEntity (SoundFoundationBridge)

- (void)playShieldHit:(Vector)attackVector weaponIdentifier:(NSString*)weaponIdentifier
{
    [self cxx_playShieldHit:attackVector weaponIdentifier:oo::StdString(weaponIdentifier)];
}

- (void)playDirectHit:(Vector)attackVector weaponIdentifier:(NSString*)weaponIdentifier
{
    [self cxx_playDirectHit:attackVector weaponIdentifier:oo::StdString(weaponIdentifier)];
}

- (void)playLaserHit:(BOOL)hit offset:(Vector)weaponOffset weaponIdentifier:(NSString*)weaponIdentifier
{
    [self cxx_playLaserHit:hit offset:weaponOffset weaponIdentifier:oo::StdString(weaponIdentifier)];
}

- (void)playMissileLaunched:(Vector)weaponOffset weaponIdentifier:(NSString*)weaponIdentifier
{
    [self cxx_playMissileLaunched:weaponOffset weaponIdentifier:oo::StdString(weaponIdentifier)];
}

- (void)playMineLaunched:(Vector)weaponOffset weaponIdentifier:(NSString*)weaponIdentifier
{
    [self cxx_playMineLaunched:weaponOffset weaponIdentifier:oo::StdString(weaponIdentifier)];
}

@end
