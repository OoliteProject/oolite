/*

OOALSound+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, amendment oo-2en): the Objective-C OOSound facade (see
OOALSound+ObjCBridge.h). Every method forwards to its C++ member. An Objective-C subclass's C++
part is an ObjCSound, whose virtual members message the subclass. Deleted with
OOALSound+ObjCBridge.h.


Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOALSound.h"
#import "OOALSoundDecoder.h"
#import "OODescription.h"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOObjCPeer.h"
#include "oofnd/objc/OORuntime.h"

#include <cstdlib>
#include <cxxabi.h>
#include <typeinfo>

namespace {

// Never destroyed: a facade may be released while the process exits.
oo::ObjCPeers& Peers()
{
    static oo::ObjCPeers* peers = new oo::ObjCPeers;
    return *peers;
}

/*	The C++ part of an Objective-C sound: each virtual member messages the Objective-C object, so
        the subclass's override runs, as it did when the base class was Objective-C. The Objective-C
        object owns this (its _cxxSound) and is not retained by it; its -dealloc clears the pointer,
        after which the members answer as a message to nil did.
*/
class ObjCSound final : public cxx::OOSound {
public:
    explicit ObjCSound(::OOSound* owner)
        : _owner(owner)
    {
    }

    ::OOSound* owner() { return _owner; }
    void ownerDeallocated() { _owner = nil; }

    std::optional<std::string> name() override { return [_owner cxx_name]; }
    ALuint soundBuffer() override { return [_owner soundBuffer]; }
    bool soundIncomplete() override { return [_owner soundIncomplete]; }
    void rewind() override { [_owner rewind]; }
    std::optional<std::string> descriptionComponents() const override { return [_owner cxx_descriptionComponents]; }

private:
    ::OOSound* _owner = { }; // Not retained.
};

ObjCSound* AsObjCSound(cxx::OOSound* sound)
{
    return dynamic_cast<ObjCSound*>(sound);
}

std::string DemangledName(cxx::OOSound& sound)
{
    int status = 0;
    char* demangled = abi::__cxa_demangle(typeid(sound).name(), nullptr, nullptr, &status);
    std::string result = (status == 0 && demangled != nullptr) ? demangled : typeid(sound).name();
    std::free(demangled);
    return result;
}

// The C++ class's name, as [self class] named an Objective-C sound's class ("cxx::" dropped).
std::string ClassName(cxx::OOSound& sound)
{
    std::string result = DemangledName(sound);
    if (result.starts_with("cxx::"))
        result.erase(0, 5);
    return result;
}

/*	The class of a C++ sound's facade: a converted subclass in namespace cxx that its callers make
        by alloc/init has a facade of its own, the Objective-C class of the same name, a subclass of
        this one (cxx::OOALBufferedSound's is OOALBufferedSound; amendment oo-up4b item 3). Any other
        C++ sound (a global class) is an OOSound.
*/
Class FacadeClass(cxx::OOSound& sound)
{
    const std::string name = DemangledName(sound);
    if (name.starts_with("cxx::")) {
        Class facade = OOClassFromName(std::string_view(name).substr(5));
        if (facade != Nil && [facade isSubclassOfClass:[OOSound class]])
            return facade;
    }
    return [OOSound class];
}

} // namespace

@interface OOSound (OOObjCBridgePrivate)

- (id)initWithCxxSound:(cxx::OOSound*)sound;

@end

@implementation OOSound

// Inside the @implementation for the private ivar.
OOSound* oo::ToObjC(cxx::OOSound* sound)
{
    if (ObjCSound* objCSound = AsObjCSound(sound))
        return [[objCSound->owner() retain] autorelease];
    if (sound == nullptr)
        return nil;
    Class facadeClass = FacadeClass(*sound);
    return Peers().peerFor(sound, [sound, facadeClass] { return [[facadeClass alloc] initWithCxxSound:sound]; });
}

cxx::OOSound* oo::ToCxx(OOSound* sound)
{
    if (sound == nil)
        return nullptr;
    return sound->_cxxSound.get();
}

+ (BOOL)setUp
{
    return cxx::OOSound::setUp();
}

+ (void)setMasterVolume:(float)fraction
{
    cxx::OOSound::setMasterVolume(fraction);
}

+ (float)masterVolume
{
    return cxx::OOSound::masterVolume();
}

// An Objective-C sound: [[X alloc] init] of a subclass (or of this class). Making the C++ part
// sets sound up, as -init did before [super init].
- (id)init
{
    self = [super init];
    if (self != nil)
        _cxxSound = oo::makeRef<ObjCSound>(self);
    return self;
}

// A C++ sound's facade (oo::ToObjC).
- (id)initWithCxxSound:(cxx::OOSound*)sound
{
    self = [super init];
    if (self != nil)
        _cxxSound = oo::Ref<cxx::OOSound>(sound);
    return self;
}

// A converted subclass's facade, made by its initialiser: the new C++ sound, and this is its peer.
- (id)initWithNewCxxSound:(const oo::Ref<cxx::OOSound>&)sound
{
    self = [super init];
    if (self != nil) {
        _cxxSound = sound;
        @autoreleasepool {
            Peers().peerFor(_cxxSound.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

/*	The class cluster: the receiver is released and the concrete sound answered in its place. When
        sound is not OK the receiver is not released, as before (it leaks); the factory's own test of
        that comes first in its body too.
*/
- (id)cxx_initWithContentsOfFile:(const std::optional<std::string>&)path
{
    if (!cxx::OOSound::isSoundOK())
        return nil;

    [self release];
    return cxx::OOSound::initWithContentsOfFile(path).leakRef();
}

// The concrete sounds' designated initialiser, on the root: no sound. Kept as it was; nothing
// sends it to an OOSound.
- (id)initWithDecoder:(OOALSoundDecoder*)inDecoder
{
    [self release];
    return nil;
}

- (void)dealloc
{
    if (ObjCSound* objCSound = AsObjCSound(_cxxSound.get()))
        objCSound->ownerDeallocated();
    else
        Peers().forget(_cxxSound.get());
    [super dealloc];
}

// A C++ sound's facade describes itself with the C++ class's name and components.
- (std::optional<std::string>)cxx_description
{
    if (AsObjCSound(_cxxSound.get()) != nullptr)
        return [super cxx_description];
    std::string result = oo::str::format("<%s %s>", ClassName(*_cxxSound).c_str(), oo::str::pointerDescription(self).c_str());
    if (const std::optional<std::string> components = _cxxSound->descriptionComponents())
        result += "{" + *components + "}";
    return result;
}

+ (void)update
{
    cxx::OOSound::update();
}

+ (BOOL)isSoundOK
{
    return cxx::OOSound::isSoundOK();
}

/*	The overridable methods. On an Objective-C sound these are reached only when the subclass does
        not override them, or by [super ...]: the base class's own member answers. On a C++ sound's
        facade the C++ override answers. (-cxx_descriptionComponents is not forwarded: OOObject's
        answers an Objective-C sound, and -cxx_description above a C++ one.)
*/

- (std::optional<std::string>)cxx_name
{
    if (AsObjCSound(_cxxSound.get()) != nullptr)
        return _cxxSound->cxx::OOSound::name();
    return _cxxSound->name();
}

- (ALuint)soundBuffer
{
    if (AsObjCSound(_cxxSound.get()) != nullptr)
        return _cxxSound->cxx::OOSound::soundBuffer();
    return _cxxSound->soundBuffer();
}

- (BOOL)soundIncomplete
{
    if (AsObjCSound(_cxxSound.get()) != nullptr)
        return _cxxSound->cxx::OOSound::soundIncomplete();
    return _cxxSound->soundIncomplete();
}

- (void)rewind
{
    if (AsObjCSound(_cxxSound.get()) != nullptr)
        _cxxSound->cxx::OOSound::rewind();
    else
        _cxxSound->rewind();
}

@end
