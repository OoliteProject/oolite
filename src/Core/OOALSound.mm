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
#import "OOLogging.h"
#import "OOMaths.h"
#import "OOOpenALController.h"
#include "oofnd/Defaults.hpp"
#include <string_view>

static constexpr std::string_view KEY_VOLUME_CONTROL = "volume_control";

static const size_t kMaxBufferedSoundSize = 1 << 20; // 1 MB

namespace {

bool sIsSetUp = false;
bool sIsSoundOK = false;

} // namespace

namespace cxx {

bool OOSound::setUp()
{
    if (!sIsSetUp) {
        sIsSetUp = true;
        OOOpenALController* controller = OOOpenALController::sharedController();
        if (controller != nullptr) {
            sIsSoundOK = true;
            oo::Defaults& prefs = oo::Defaults::standard();
            float volume = prefs.object(std::string(KEY_VOLUME_CONTROL)).isNull() ? 0.5f : prefs.floatForKey(std::string(KEY_VOLUME_CONTROL));
            setMasterVolume(volume);
        }
    }

    return sIsSoundOK;
}

void OOSound::setMasterVolume(float fraction)
{
    if (!sIsSetUp && !setUp())
        return;

    fraction = OOClamp_0_1_f(fraction);

    // A null controller answers 0, as a message to nil did (sound set up but refused).
    OOOpenALController* controller = OOOpenALController::sharedController();
    if (fraction != (controller != nullptr ? controller->masterVolume() : 0.0f)) {
        if (controller != nullptr)
            controller->setMasterVolume(fraction);
        oo::Defaults::standard().setFloat(std::string(KEY_VOLUME_CONTROL), controller != nullptr ? controller->masterVolume() : 0.0f);
    }
}

float OOSound::masterVolume()
{
    if (!sIsSetUp && !setUp())
        return 0.0;

    OOOpenALController* controller = OOOpenALController::sharedController();
    return controller != nullptr ? controller->masterVolume() : 0.0f;
}

OOSound::OOSound()
{
    if (!sIsSetUp)
        setUp();
}

/*	The receiver that -cxx_initWithContentsOfFile: released (or, when sound was not OK, leaked)
        is the facade's (OOALSound+ObjCBridge.mm); this is the rest of the body, which answers the
        concrete sound it makes.
*/
oo::ObjCRef<::OOSound*> OOSound::initWithContentsOfFile(const std::optional<std::string>& path)
{
    if (!sIsSoundOK)
        return nullptr;

    if (!sIsSetUp && !setUp())
        return nullptr;

    ::OOALSoundDecoder* decoder;
    ::OOSound* self;

    decoder = [[::OOALSoundDecoder alloc] cxx_initWithPath:path];
    if (nil == decoder)
        return nullptr;

    if ([decoder sizeAsBuffer] <= kMaxBufferedSoundSize) {
        // C++ since oo-9ht.83: the new sound's facade is the root's, made as its subclass facade made it.
        const oo::Ref<OOALBufferedSound> sound = OOALBufferedSound::initWithDecoder(decoder);
        self = sound ? [[::OOSound alloc] initWithNewCxxSound:sound] : nil;
    } else {
        // C++ since oo-9ht.84: as the buffered sound above.
        const oo::Ref<OOALStreamedSound> sound = OOALStreamedSound::initWithDecoder(decoder);
        self = sound ? [[::OOSound alloc] initWithNewCxxSound:sound] : nil;
    }
    [decoder release];

    if (nil != self) {
#ifndef NDEBUG
        OO_LOG(kOOLogSoundLoadingSuccess, "Loaded sound {}", path.value_or("(null)"));
#endif
    } else {
        OO_LOG(kOOLogSoundLoadingError, "Failed to load sound \"{}\"", path.value_or("(null)"));
    }

    return oo::ObjCRef<::OOSound*>::adopt(self);
}

std::optional<std::string> OOSound::name()
{
    OOLogGenericSubclassResponsibility();
    return std::string();
}

void OOSound::update()
{
    ::OOSoundMixer* mixer = ::OOSoundMixer::sharedMixer();
    if (sIsSoundOK && mixer)
        mixer->update();
}

bool OOSound::isSoundOK()
{
    return sIsSoundOK;
}

ALuint OOSound::soundBuffer()
{
    OOLogGenericSubclassResponsibility();
    return 0;
}

bool OOSound::soundIncomplete()
{
    return false;
}

void OOSound::rewind()
{
    // doesn't need to do anything on seekable FDs
}

std::optional<std::string> OOSound::descriptionComponents() const
{
    return std::nullopt;
}

} // namespace cxx
