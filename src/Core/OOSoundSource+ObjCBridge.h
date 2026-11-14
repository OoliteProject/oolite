/*

OOSoundSource+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, the Audio module: amendment oo-2en): the Objective-C OOSoundSource,
a facade over the C++ cxx::OOSoundSource (OOSoundSource.h), for the code that makes and messages
sound sources and for the channels, which call a playing source back through
-channel:didFinishPlayingSound: (and a stopped one's class through the class method). Its interface
is the one OOSoundSource.h declared before the conversion, copied exactly. A playing source's facade
is kept alive by the source itself, as the old object kept itself (amendment oo-kdyh item 2). The
categories in Universe.h (OOCustomSounds) and OOJSSoundSource+ObjCBridge.mm (the JS glue) stay
categories of this class. Imported as the last line of OOSoundSource.h; do not import it directly.

oo::ToObjC(oo::ToCxx(s)) == s. Never add to this file; converted code does not message the facade.
Deleted by its deletion bead once every caller is C++.


Copyright (C) 2006-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR

*/

#ifndef OOSOUNDSOURCE_OBJCBRIDGE_H
#define OOSOUNDSOURCE_OBJCBRIDGE_H

@interface OOSoundSource : OOObject {
@private
    oo::Ref<cxx::OOSoundSource> _cxxSource;
}

+ (instancetype)sourceWithSound:(OOSound*)inSound;
- (id)initWithSound:(OOSound*)inSound;

// These options should be set before playing. Effect of setting them while playing is undefined.
- (OOSound*)sound;
- (void)setSound:(OOSound*)inSound;
- (BOOL)loop;
- (void)setLoop:(BOOL)inLoop;
- (uint8_t)repeatCount;
- (void)setRepeatCount:(uint8_t)inCount;

- (BOOL)isPlaying;
- (void)play;
- (void)playOrRepeat;
- (void)stop;

+ (void)stopAll;

// Conveniences:
- (void)playOOSound:(OOSound*)inSound;
- (void)playSound:(OOSound*)inSound repeatCount:(uint8_t)inCount;
- (void)playOrRepeatSound:(OOSound*)inSound;

// Positional audio attributes are used in this implementation
- (void)setPositional:(BOOL)inPositional;
- (BOOL)positional;
- (void)setPosition:(Vector)inPosition;
- (Vector)position;
- (void)setGain:(float)gain;
- (float)gain;

// *Advanced* positional audio attributes are ignored in this implementation
- (void)setVelocity:(Vector)inVelocity;
- (void)setOrientation:(Vector)inOrientation;
- (void)setConeAngle:(float)inAngle;
- (void)setGainInsideCone:(float)inInside outsideCone:(float)inOutside;
- (void)positionRelativeTo:(OOSoundReferencePoint*)inPoint;

@end

namespace oo {

// The source's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOSoundSource* ToObjC(cxx::OOSoundSource* source);
inline OOSoundSource* ToObjC(const Ref<cxx::OOSoundSource>& source) { return ToObjC(source.get()); }

// The C++ source behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOSoundSource* ToCxx(OOSoundSource* source);

} // namespace oo

#endif // OOSOUNDSOURCE_OBJCBRIDGE_H
