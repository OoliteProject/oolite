/*

OOALSoundDecoder+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, the Audio module: amendment oo-2en): the Objective-C
OOALSoundDecoder facade (see OOALSoundDecoder+ObjCBridge.h). Every method forwards to its C++
member. Deleted with OOALSoundDecoder+ObjCBridge.h.


OOALSound - OpenAL sound implementation for Oolite.
Copyright (C) 2005-2013 Jens Ayton

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

#import "OOALSoundDecoder.h"
#import "OODescription.h"
#include "oofnd/String.hpp"
#include "oofnd/objc/OOObjCPeer.h"

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

/*	The decoder's class name, as [self class] named it before: the C++ class's, without its
        namespace (the Vorbis codec is private to OOALSoundDecoder.mm, in an anonymous namespace).
*/
std::string ClassName(cxx::OOALSoundDecoder& decoder)
{
    int status = 0;
    char* demangled = abi::__cxa_demangle(typeid(decoder).name(), nullptr, nullptr, &status);
    std::string result = (status == 0 && demangled != nullptr) ? demangled : typeid(decoder).name();
    std::free(demangled);
    const std::size_t colons = result.rfind("::");
    if (colons != std::string::npos)
        result.erase(0, colons + 2);
    return result;
}

} // namespace

@interface OOALSoundDecoder (OOObjCBridgePrivate)

- (id)initWithCxxDecoder:(cxx::OOALSoundDecoder*)decoder;
- (id)initWithNewCxxDecoder:(oo::Ref<cxx::OOALSoundDecoder>)decoder;

@end

@implementation OOALSoundDecoder

// Inside the @implementation for the private ivar.
OOALSoundDecoder* oo::ToObjC(cxx::OOALSoundDecoder* decoder)
{
    return Peers().peerFor(decoder, [decoder] { return [[OOALSoundDecoder alloc] initWithCxxDecoder:decoder]; });
}

cxx::OOALSoundDecoder* oo::ToCxx(OOALSoundDecoder* decoder)
{
    if (decoder == nil)
        return nullptr;
    return decoder->_cxxDecoder.get();
}

// The facade oo::ToObjC makes (under the peer table's lock: it only stores the ivar).
- (id)initWithCxxDecoder:(cxx::OOALSoundDecoder*)decoder
{
    self = [super init];
    if (self != nil)
        _cxxDecoder = oo::Ref<cxx::OOALSoundDecoder>(decoder);
    return self;
}

// The facade alloc/init makes: adopts its new C++ decoder and records itself as its peer. nil (and
// self released) for a null decoder, as the class cluster answered nil.
- (id)initWithNewCxxDecoder:(oo::Ref<cxx::OOALSoundDecoder>)decoder
{
    if (decoder.get() == nullptr) {
        [self release];
        return nil;
    }

    self = [super init];
    if (self != nil) {
        _cxxDecoder = std::move(decoder);
        @autoreleasepool {
            Peers().peerFor(_cxxDecoder.get(), [self] { return [self retain]; });
        }
    }
    return self;
}

// [[OOALSoundDecoder alloc] init]: the public class itself, a decoder of nothing.
- (id)init
{
    return [self initWithNewCxxDecoder:oo::makeRef<cxx::OOALSoundDecoder>()];
}

- (void)dealloc
{
    Peers().forget(_cxxDecoder.get());
    [super dealloc];
}

// The class cluster: the concrete decoder answered in place of the receiver.
- (id)cxx_initWithPath:(const std::optional<std::string>&)inPath
{
    return [self initWithNewCxxDecoder:cxx::OOALSoundDecoder::initWithPath(inPath)];
}

+ (OOALSoundDecoder*)codecWithPath:(const std::string&)inPath
{
    return oo::ToObjC(cxx::OOALSoundDecoder::codecWithPath(inPath));
}

- (BOOL)readCreatingBuffer:(char**)outBuffer withFrameCount:(size_t*)outSize
{
    return _cxxDecoder->readCreatingBuffer(outBuffer, outSize);
}

- (size_t)streamToBuffer:(char*)buffer
{
    return _cxxDecoder->streamToBuffer(buffer);
}

- (size_t)sizeAsBuffer
{
    return _cxxDecoder->sizeAsBuffer();
}

- (BOOL)isStereo
{
    return _cxxDecoder->isStereo();
}

- (long)sampleRate
{
    return _cxxDecoder->sampleRate();
}

- (void)reset
{
    _cxxDecoder->reset();
}

- (std::optional<std::string>)cxx_name
{
    return _cxxDecoder->name();
}

- (std::optional<std::string>)cxx_descriptionComponents
{
    return _cxxDecoder->descriptionComponents();
}

// The decoder describes itself with its C++ class's name (the Vorbis codec's, as before).
- (std::optional<std::string>)cxx_description
{
    std::string result = oo::str::format("<%s %s>", ClassName(*_cxxDecoder).c_str(), oo::str::pointerDescription(self).c_str());
    if (const std::optional<std::string> components = _cxxDecoder->descriptionComponents())
        result += "{" + *components + "}";
    return result;
}

@end
