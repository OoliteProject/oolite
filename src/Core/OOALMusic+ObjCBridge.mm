/*

OOALMusic+ObjCBridge.mm

TRANSITIONAL (proposed ADR-0056, the Audio module: amendment oo-2en): the Objective-C OOMusic
facade (see OOALMusic+ObjCBridge.h). Every method forwards to its C++ member. Deleted with
OOALMusic+ObjCBridge.h.


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

#import "OOALMusic.h"

@implementation OOMusic

OOMusic* oo::ToObjC(cxx::OOMusic* music)
{
    return static_cast<OOMusic*>(oo::ToObjC(static_cast<cxx::OOSound*>(music)));
}

cxx::OOMusic* oo::ToCxx(OOMusic* music)
{
    return static_cast<cxx::OOMusic*>(oo::ToCxx(static_cast<OOSound*>(music)));
}

+ (id)allocWithZone:(OOZone*)inZone
{
    return class_createInstance([OOMusic class], 0); // zones unused (ADR-0029)
}

// OOSound's designated initializer, overridden: a new C++ music, whose facade (and peer) this is;
// nil (and self released) where the initialiser answered nil.
- (id)cxx_initWithContentsOfFile:(const std::optional<std::string>&)inPath
{
    const oo::Ref<cxx::OOMusic> music = cxx::OOMusic::initWithContentsOfFile(inPath);
    if (!music) {
        [self release];
        return nil;
    }
    return [self initWithNewCxxSound:music];
}

- (void)setMusicGain:(float)newValue
{
    oo::ToCxx(self)->setMusicGain(newValue);
}

- (float)musicGain
{
    return oo::ToCxx(self)->musicGain();
}

- (void)playLooped:(BOOL)inLoop
{
    oo::ToCxx(self)->playLooped(inLoop);
}

- (OOSoundSource*)musicSoundSource
{
    return oo::ToCxx(self)->musicSoundSource();
}

- (BOOL)isPlaying
{
    return oo::ToCxx(self)->isPlaying();
}

- (void)stop
{
    oo::ToCxx(self)->stop();
}

@end
