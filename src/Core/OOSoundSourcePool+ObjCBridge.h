/*

OOSoundSourcePool+ObjCBridge.h

TRANSITIONAL (proposed ADR-0056, the Audio module: amendment oo-2en): the Objective-C
OOSoundSourcePool, a facade over the C++ cxx::OOSoundSourcePool (OOSoundSourcePool.h), for the
player's sound category (PlayerEntitySound.mm), which makes five pools and sends them about forty
messages. Its interface is the one OOSoundSourcePool.h declared before the conversion, copied
exactly. Imported as the last line of OOSoundSourcePool.h; do not import it directly.

oo::ToObjC(oo::ToCxx(p)) == p. Never add to this file; converted code does not message the facade.
Deleted by its deletion bead once the player is C++.


Copyright (C) 2008-2013 Jens Ayton

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
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#ifndef OOSOUNDSOURCEPOOL_OBJCBRIDGE_H
#define OOSOUNDSOURCEPOOL_OBJCBRIDGE_H

@interface OOSoundSourcePool : OOObject {
@private
    oo::Ref<cxx::OOSoundSourcePool> _cxxPool;
}

+ (instancetype)poolWithCount:(uint8_t)count minRepeatTime:(OOTimeDelta)minRepeat;
- (id)initWithCount:(uint8_t)count minRepeatTime:(OOTimeDelta)minRepeat;

- (void)playSoundWithKey:(const std::string&)key
                priority:(float)priority
              expiryTime:(OOTimeDelta)expiryTime
                 overlap:(BOOL)overlap
                position:(Vector)position;

- (void)playSoundWithKey:(const std::string&)key
                priority:(float)priority
              expiryTime:(OOTimeDelta)expiryTime;

- (void)playSoundWithKey:(const std::string&)key
                priority:(float)priority; // expiryTime:0.1 +/- 0.5

- (void)playSoundWithKey:(const std::string&)key
                priority:(float)priority
                position:(Vector)position; // expiryTime:0.1 +/- 0.5

- (void)playSoundWithKey:(const std::string&)key
                position:(Vector)position; // expiryTime:0.1 +/- 0.5

- (void)playSoundWithKey:(const std::string&)key; // priority: 1.0, expiryTime:0.1 +/- 0.5

- (void)playSoundWithKey:(const std::string&)key overlap:(BOOL)overlap; // if overlap == NO it waits for key to finish before playing key again
- (void)playSoundWithKey:(const std::string&)key overlap:(BOOL)overlap position:(Vector)position;

@end

namespace oo {

// The pool's Objective-C facade: its live one, else a new one; autoreleased. nil for null.
OOSoundSourcePool* ToObjC(cxx::OOSoundSourcePool* pool);
inline OOSoundSourcePool* ToObjC(const Ref<cxx::OOSoundSourcePool>& pool) { return ToObjC(pool.get()); }

// The C++ pool behind a facade, borrowed (the facade retains it); null for nil.
cxx::OOSoundSourcePool* ToCxx(OOSoundSourcePool* pool);

} // namespace oo

#endif // OOSOUNDSOURCEPOOL_OBJCBRIDGE_H
