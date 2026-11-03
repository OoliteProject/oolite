/*

OOSoundSourcePool+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, the Audio module: amendment oo-2en): the Objective-C
OOSoundSourcePool facade (see OOSoundSourcePool+ObjCBridge.h). Every method forwards to its C++
member, with the overload its selector names. Deleted with OOSoundSourcePool+ObjCBridge.h.


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

#import "OOSoundSourcePool.h"

#include "oofnd/objc/OOObjCPeer.h"

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

} // namespace

@interface OOSoundSourcePool (OOObjCBridgePrivate)

- (id)initWithCxxPool:(cxx::OOSoundSourcePool*)pool;
- (id)initWithNewCxxPool:(oo::Ref<cxx::OOSoundSourcePool>)pool;

@end

@implementation OOSoundSourcePool

// Inside the @implementation for the private ivar.
OOSoundSourcePool* oo::ToObjC(cxx::OOSoundSourcePool* pool)
{
    return Peers().peerFor(pool, [pool] { return [[OOSoundSourcePool alloc] initWithCxxPool:pool]; });
}

cxx::OOSoundSourcePool* oo::ToCxx(OOSoundSourcePool* pool)
{
    if (pool == nil)
        return nullptr;
    return pool->_cxxPool.get();
}

// The facade oo::ToObjC makes (under the peer table's lock: it only stores the ivar).
- (id)initWithCxxPool:(cxx::OOSoundSourcePool*)pool
{
    self = [super init];
    if (self != nil)
        _cxxPool = oo::Ref<cxx::OOSoundSourcePool>(pool);
    return self;
}

// The facade alloc/init makes: adopts its new C++ pool and records itself as its peer. nil (and
// self released) for a null pool, as the initialiser failed when it could not allocate.
- (id)initWithNewCxxPool:(oo::Ref<cxx::OOSoundSourcePool>)pool
{
    if (pool.get() == nullptr) {
        [self release];
        return nil;
    }

    self = [super init];
    if (self != nil) {
        _cxxPool = std::move(pool);
        @autoreleasepool {
            Peers().peerFor(_cxxPool.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

- (void)dealloc
{
    Peers().forget(_cxxPool.get());
    [super dealloc];
}

+ (instancetype)poolWithCount:(uint8_t)count minRepeatTime:(OOTimeDelta)minRepeat
{
    return oo::ToObjC(cxx::OOSoundSourcePool::poolWithCount(count, minRepeat));
}

- (id)initWithCount:(uint8_t)count minRepeatTime:(OOTimeDelta)minRepeat
{
    return [self initWithNewCxxPool:cxx::OOSoundSourcePool::poolWithCount(count, minRepeat)];
}

- (void)playSoundWithKey:(const std::string&)key
                priority:(float)priority
              expiryTime:(OOTimeDelta)expiryTime
                 overlap:(BOOL)overlap
                position:(Vector)position
{
    _cxxPool->playSoundWithKey(key, priority, expiryTime, static_cast<bool>(overlap), position);
}

- (void)playSoundWithKey:(const std::string&)key
                priority:(float)priority
              expiryTime:(OOTimeDelta)expiryTime
{
    _cxxPool->playSoundWithKey(key, priority, expiryTime);
}

- (void)playSoundWithKey:(const std::string&)key
                priority:(float)priority
{
    _cxxPool->playSoundWithKey(key, priority);
}

- (void)playSoundWithKey:(const std::string&)key
                priority:(float)priority
                position:(Vector)position
{
    _cxxPool->playSoundWithKey(key, priority, position);
}

- (void)playSoundWithKey:(const std::string&)key
                position:(Vector)position
{
    _cxxPool->playSoundWithKey(key, position);
}

- (void)playSoundWithKey:(const std::string&)key
{
    _cxxPool->playSoundWithKey(key);
}

- (void)playSoundWithKey:(const std::string&)key overlap:(BOOL)overlap
{
    _cxxPool->playSoundWithKey(key, static_cast<bool>(overlap));
}

- (void)playSoundWithKey:(const std::string&)key overlap:(BOOL)overlap position:(Vector)position
{
    _cxxPool->playSoundWithKey(key, static_cast<bool>(overlap), position);
}

@end
