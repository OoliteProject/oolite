/*

OOPlanetEntity+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendments oo-bj8, oo-0mxi and oo-ubjo): the Objective-C
OOPlanetEntity facade (see OOPlanetEntity+ObjCBridge.h). Deleted with OOPlanetEntity+ObjCBridge.h.

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

#import "OOColor.h"
#import "OOGraphicsResetManager.h"
#import "OOJSPlanet.h"
#import "OOPlanetDrawable.h"
#import "OOPlanetEntity.h"

@interface OOPlanetEntity (OOObjCBridgePrivate) <OOGraphicsResetClient>
@end

@implementation OOPlanetEntity

// [[OOPlanetEntity alloc] init]: a C++ planet, which no initialiser has set up (Entity's -init, as
// before: the class did not override it).
- (id)init
{
    if (_cxxEntity != nullptr)
        return [super initWithCxxEntity:_cxxEntity.get()];
    return [super initWithCxxEntity:oo::makeRef<cxx::OOPlanetEntity>().get()];
}

// The initialisers (the universe, the legacy scripts): a C++ planet, then the initialiser's body
// (amendment oo-0mxi item 2). Sent again, they keep the C++ part and run the body again, as the
// Objective-C initialisers did.
- (id)initAsMainPlanetForSystem:(OOSystemID)s
{
    self = [self init];
    if (self != nil)
        oo::ToCxx(self)->initAsMainPlanetForSystem(s);
    return self;
}

- (id)initFromDictionary:(const oo::PList&)dict withAtmosphere:(BOOL)atmosphere andSeed:(Random_Seed)seed forSystem:(OOSystemID)systemID
{
    self = [self init];
    if (self != nil)
        oo::ToCxx(self)->initFromDictionary(dict, atmosphere, seed, systemID);
    return self;
}

// The planet registered its facade as a graphics reset client (oo::ToObjC(this)).
- (void)dealloc
{
    [[OOGraphicsResetManager sharedManager] unregisterClient:self];

    [super dealloc];
}

- (instancetype)miniatureVersion
{
    return (OOPlanetEntity*)oo::NewEntityFacade(oo::ToCxx(self)->miniatureVersion());
}
- (double)rotationalVelocity
{
    return oo::ToCxx(self)->rotationalVelocity();
}
- (void)setRotationalVelocity:(double)v
{
    oo::ToCxx(self)->setRotationalVelocity(v);
}
- (BOOL)planetHasStation
{
    return oo::ToCxx(self)->planetHasStation();
}
- (void)launchShuttle
{
    oo::ToCxx(self)->launchShuttle();
}
- (void)welcomeShuttle:(ShipEntity*)shuttle
{
    oo::ToCxx(self)->welcomeShuttle(shuttle);
}
- (BOOL)hasAtmosphere
{
    return oo::ToCxx(self)->hasAtmosphere();
}
- (std::optional<std::string>)textureFileName
{
    return oo::ToCxx(self)->textureFileName();
}
- (void)setTextureFileName:(const std::optional<std::string>&)textureName
{
    oo::ToCxx(self)->setTextureFileName(textureName);
}
- (BOOL)setUpPlanetFromTexture:(const std::optional<std::string>&)fileName
{
    return oo::ToCxx(self)->setUpPlanetFromTexture(fileName);
}
- (OOMaterial*)material
{
    return oo::ToCxx(self)->material();
}
- (OOMaterial*)atmosphereMaterial
{
    return oo::ToCxx(self)->atmosphereMaterial();
}
- (OOMaterial*)atmosphereShaderMaterial
{
    return oo::ToCxx(self)->atmosphereShaderMaterial();
}
- (BOOL)isFinishedLoading
{
    return oo::ToCxx(self)->isFinishedLoading();
}
- (Vector)airColorAsVector
{
    return oo::ToCxx(self)->airColorAsVector();
}
- (OOColor*)airColor
{
    return oo::ToObjC(oo::ToCxx(self)->airColor());
}
- (void)setAirColor:(OOColor*)newColor
{
    oo::ToCxx(self)->setAirColor(oo::ToCxx(newColor));
}
- (Vector)illuminationColorAsVector
{
    return oo::ToCxx(self)->illuminationColorAsVector();
}
- (OOColor*)illuminationColor
{
    return oo::ToObjC(oo::ToCxx(self)->illuminationColor());
}
- (void)setIlluminationColor:(OOColor*)newColor
{
    oo::ToCxx(self)->setIlluminationColor(oo::ToCxx(newColor));
}
- (float)airColorMixRatio
{
    return oo::ToCxx(self)->airColorMixRatio();
}
- (void)setAirColorMixRatio:(float)newRatio
{
    oo::ToCxx(self)->setAirColorMixRatio(newRatio);
}
- (float)airDensity
{
    return oo::ToCxx(self)->airDensity();
}
- (void)setAirDensity:(float)newDensity
{
    oo::ToCxx(self)->setAirDensity(newDensity);
}
- (void)setTerminatorThresholdVector:(Vector)newTerminatorThresholdVector
{
    oo::ToCxx(self)->setTerminatorThresholdVector(newTerminatorThresholdVector);
}
- (Vector)terminatorThresholdVector
{
    return oo::ToCxx(self)->terminatorThresholdVector();
}

// OOStellarBody
- (double)radius
{
    return oo::ToCxx(self)->radius();
}
- (OOStellarBodyType)planetType
{
    return oo::ToCxx(self)->planetType();
}
- (std::optional<std::string>)cxx_name
{
    return oo::ToCxx(self)->name();
}
- (void)cxx_setName:(const std::optional<std::string>&)name
{
    oo::ToCxx(self)->setName(name);
}

// OOGraphicsResetClient: the facade is the client the planet registered.
- (void)resetGraphicsState
{
    oo::ToCxx(self)->resetGraphicsState();
}

// The JS side, which the engine asks for by selector (Entity (OOJavaScriptExtensions)): the
// binding's category, moved here from the binding's bridge file, which it deletes (bead oo-9ht.92;
// ADR-0056 amendment oo-6ia4 item 3). Each forwards to the OOJSPlanet.mm function that holds its
// old body; they become members of the C++ class with this facade's deletion (oo-9ht.129).
- (JSClassID)oo_jsClassID
{
    return ::JSPlanetClassID();
}
- (std::optional<std::string>)cxx_oo_jsClassName
{
    return ::OOJSPlanetJSClassName(self);
}
- (BOOL)isVisibleToScripts
{
    return ::OOJSPlanetIsVisibleToScripts(self);
}

@end
