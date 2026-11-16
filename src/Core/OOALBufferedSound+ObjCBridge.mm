/*

OOALBufferedSound+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, the Audio module: amendment oo-2en): the Objective-C OOALBufferedSound
facade (see OOALBufferedSound+ObjCBridge.h). Deleted with OOALBufferedSound+ObjCBridge.h.


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

#import "OOALBufferedSound.h"

@implementation OOALBufferedSound

OOALBufferedSound* oo::ToObjC(cxx::OOALBufferedSound* sound)
{
    return static_cast<OOALBufferedSound*>(oo::ToObjC(static_cast<cxx::OOSound*>(sound)));
}

cxx::OOALBufferedSound* oo::ToCxx(OOALBufferedSound* sound)
{
    return static_cast<cxx::OOALBufferedSound*>(oo::ToCxx(static_cast<OOSound*>(sound)));
}

// The class cluster's [[OOALBufferedSound alloc] initWithDecoder:]: a new C++ sound, whose facade (and
// peer) this is; nil (and self released) where the initialiser answered nil.
- (id)initWithDecoder:(OOALSoundDecoder*)inDecoder
{
    const oo::Ref<cxx::OOALBufferedSound> sound = cxx::OOALBufferedSound::initWithDecoder(inDecoder);
    if (!sound) {
        [self release];
        return nil;
    }
    return [self initWithNewCxxSound:sound];
}

@end
