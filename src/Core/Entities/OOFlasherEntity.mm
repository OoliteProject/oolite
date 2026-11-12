/*

OOFlasherEntity.m


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

#import "OOFlasherEntity.h"
#import "OOColor.h"
#import "OOFoundationBridge.h"
#import "PlayerEntity.h"
#import "Universe.h"

#include "oofnd/PListGet.hpp"

@interface OOFlasherEntity (Internal)

- (id)initWithFlasherConfiguration:(const oo::PList&)dictionary;
- (void)setUpColors:(const oo::PList*)colorSpecifiers; // an array node, or nullptr
- (void)getCurrentColorComponents;

@end

@implementation OOFlasherEntity

+ (instancetype)flasherWithDictionary:(const oo::PList&)dictionary
{
    return [[[OOFlasherEntity alloc] initWithFlasherConfiguration:dictionary] autorelease];
}

- (id)initWithDictionary:(id)dictionary
{
    return [self initWithFlasherConfiguration:oo::PListFrom(dictionary)];
}

- (id)initWithFlasherConfiguration:(const oo::PList&)dictionary
{
    float size = dictionary.get<float>("size", 1.0f);

    if ((self = [super initWithDiameter:size])) {
        _frequency = dictionary.get<float>("frequency", 1.0f) * 2.0f;
        _phase = dictionary.get<float>("phase", 0.0f);
        _brightfraction = dictionary.get<float>("bright_fraction", 0.5f);

        [self setUpColors:dictionary.get<oo::PList::Array>("colors")];
        [self getCurrentColorComponents];

        [self setActive:dictionary.get<bool>("initially_on", YES)];
    }
    return self;
}

- (void)setUpColors:(const oo::PList*)colorSpecifiers
{
    std::vector<oo::ObjCRef<OOColor*>> colors;
    if (colorSpecifiers != nullptr) {
        for (const oo::PList& specifier : *colorSpecifiers->getIf<oo::PList::Array>()) {
            colors.emplace_back([OOColor colorWithDescription:oo::ObjectFromPList(specifier) saturationFactor:0.75f]);
        }
    }

    _colors = std::move(colors);
}

// The colour at index; nil past the end (-objectAtIndex: raised there).
- (OOColor*)flasherColorAtIndex:(NSUInteger)index
{
    return index < _colors.size() ? _colors[index].get() : nil;
}

- (void)getCurrentColorComponents
{
    [self setColor:[self flasherColorAtIndex:_activeColor] alpha:_colorComponents[3]];
}

- (BOOL)isActive
{
    return _active;
}

- (void)setActive:(BOOL)active
{
    _active = !!active;
}

- (OOColor*)color
{
    return [OOColor colorWithRed:_colorComponents[0]
                           green:_colorComponents[1]
                            blue:_colorComponents[2]
                           alpha:_colorComponents[3]];
}

- (float)frequency
{
    return _frequency;
}

- (void)setFrequency:(float)frequency
{
    _frequency = frequency;
}

- (float)phase
{
    return _phase;
}

- (void)setPhase:(float)phase
{
    _phase = phase;
}

- (float)fraction
{
    return _brightfraction;
}

- (void)setFraction:(float)fraction
{
    _brightfraction = fraction;
}

- (void)update:(OOTimeDelta)delta_t
{
    [super update:delta_t];

    _time += delta_t;

    if (_frequency != 0) {
        float wave = sinf(_frequency * M_PI * (_time + _phase));
        NSUInteger count = _colors.size();
        if (count > 1 && wave < 0) {
            if (!_justSwitched && wave > _wave) // don't test for wave >= _wave - could give wrong results with very low frequencies
            {
                _justSwitched = YES;
                ++_activeColor;
                _activeColor %= count; //_activeColor = ++_activeColor % count; is potentially undefined operation
                [self setColor:[self flasherColorAtIndex:_activeColor]];
            }
        } else if (_justSwitched) {
            _justSwitched = NO;
        }

        float threshold = cosf(_brightfraction * M_PI);

        float brightness = _brightfraction;
        if (wave > threshold) {
            brightness = _brightfraction + (((1 - _brightfraction) / (1 - threshold)) * (wave - threshold));
        } else if (wave < threshold) {
            brightness = _brightfraction + ((_brightfraction / (threshold + 1)) * (wave - threshold));
        }

        _colorComponents[3] = brightness;

        _wave = wave;
    } else {
        _colorComponents[3] = 1.0;
    }
}

- (void)drawImmediate:(bool)immediate translucent:(bool)translucent
{
    if (_active) {
        [super drawImmediate:immediate translucent:translucent];
    }
}

- (void)drawSubEntityImmediate:(bool)immediate translucent:(bool)translucent
{
    if (_active) {
        [super drawSubEntityImmediate:immediate translucent:translucent];
    }
}

- (BOOL)isFlasher
{
    return YES;
}

- (double)findCollisionRadius
{
    return [self diameter] / 2.0;
}

- (void)rescaleBy:(GLfloat)factor
{
    [self setDiameter:[self diameter] * factor];
}

- (void)rescaleBy:(GLfloat)factor writeToCache:(BOOL)writeToCache
{
    /* Do nothing; this is only needed because of OOEntityWithDrawable
       implementation requirements */
}

@end

@implementation Entity (OOFlasherEntityExtensions)

- (BOOL)isFlasher
{
    return NO;
}

@end
