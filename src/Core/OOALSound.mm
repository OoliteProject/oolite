/*

OOALSound.m

OOALSound - OpenAL sound implementation for Oolite.

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
#import "OOALBufferedSound.h"
#import "OOALSoundDecoder.h"
#import "OOALSoundMixer.h"
#import "OOALStreamedSound.h"
#import "OOFoundationBridge.h"
#import "OOLogging.h"
#import "OOMaths.h"
#import "OOOpenALController.h"
#import "OOPListView.h"
#import "OOStringBridge.h"
#include "oofnd/Defaults.hpp"
#include <string_view>

static constexpr std::string_view KEY_VOLUME_CONTROL = "volume_control";

static const size_t kMaxBufferedSoundSize = 1 << 20; // 1 MB

static BOOL sIsSetUp = NO;
static BOOL sIsSoundOK = NO;

@implementation OOSound

+ (BOOL)setUp
{
    if (!sIsSetUp) {
        sIsSetUp = YES;
        OOOpenALController* controller = [OOOpenALController sharedController];
        if (controller != nil) {
            sIsSoundOK = YES;
            oo::Defaults& prefs = oo::Defaults::standard();
            float volume = prefs.object(std::string(KEY_VOLUME_CONTROL)).isNull() ? 0.5f : prefs.floatForKey(std::string(KEY_VOLUME_CONTROL));
            [self setMasterVolume:volume];
        }
    }

    return sIsSoundOK;
}

+ (void)setMasterVolume:(float)fraction
{
    if (!sIsSetUp && ![self setUp])
        return;

    fraction = OOClamp_0_1_f(fraction);

    OOOpenALController* controller = [OOOpenALController sharedController];
    if (fraction != [controller masterVolume]) {
        [controller setMasterVolume:fraction];
        oo::Defaults::standard().setFloat(std::string(KEY_VOLUME_CONTROL), [controller masterVolume]);
    }
}

+ (float)masterVolume
{
    if (!sIsSetUp && ![self setUp])
        return 0.0;

    OOOpenALController* controller = [OOOpenALController sharedController];
    return [controller masterVolume];
}

- (id)init
{
    if (!sIsSetUp)
        [OOSound setUp];
    return [super init];
}

- (id)initWithContentsOfFile:(id)path // shared selector (Foundation declares it too)
{
    return [self cxx_initWithContentsOfFile:oo::OptionalString(path)];
}

- (id)cxx_initWithContentsOfFile:(const std::optional<std::string>&)path
{
    if (!sIsSoundOK)
        return nil;

    [self release];
    if (!sIsSetUp && ![OOSound setUp])
        return nil;

    OOALSoundDecoder* decoder;

    decoder = [[OOALSoundDecoder alloc] cxx_initWithPath:path];
    if (nil == decoder)
        return nil;

    if ([decoder sizeAsBuffer] <= kMaxBufferedSoundSize) {
        self = [[OOALBufferedSound alloc] initWithDecoder:decoder];
    } else {
        self = [[OOALStreamedSound alloc] initWithDecoder:decoder];
    }
    [decoder release];

    if (nil != self) {
#ifndef NDEBUG
        OO_LOG(kOOLogSoundLoadingSuccess, "Loaded sound {}", path.value_or("(null)"));
#endif
    } else {
        OO_LOG(kOOLogSoundLoadingError, "Failed to load sound \"{}\"", path.value_or("(null)"));
    }

    return self;
}

- (id)initWithDecoder:(OOALSoundDecoder*)inDecoder
{
    [self release];
    return nil;
}

- (id)name // shared selector (Foundation declares -name too; retires with oo-qps)
{
    return oo::NSStringOrNil([self cxx_name]);
}

- (std::optional<std::string>)cxx_name
{
    OOLogGenericSubclassResponsibility();
    return std::string();
}

+ (void)update
{
    OOSoundMixer* mixer = [OOSoundMixer sharedMixer];
    if (sIsSoundOK && mixer)
        [mixer update];
}

+ (BOOL)isSoundOK
{
    return sIsSoundOK;
}

- (ALuint)soundBuffer
{
    OOLogGenericSubclassResponsibility();
    return 0;
}

- (BOOL)soundIncomplete
{
    return NO;
}

- (void)rewind
{
    // doesn't need to do anything on seekable FDs
}

@end
