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

#include "OOALSound.h"
#include "OOALBufferedSound.h"
#include "OOALSoundDecoder.h"
#include "OOALSoundMixer.h"
#include "OOALStreamedSound.h"
#include "OOLogging.h"
#include "OOMaths.h"
#include "OOOpenALController.h"
#include "oofnd/Defaults.hpp"
#include "oofnd/String.hpp"

#include <cstdlib>
#include <cxxabi.h>
#include <string_view>
#include <typeinfo>

static constexpr std::string_view KEY_VOLUME_CONTROL = "volume_control";

static const size_t kMaxBufferedSoundSize = 1 << 20; // 1 MB

namespace {

bool sIsSetUp = false;
bool sIsSoundOK = false;

} // namespace

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

/*	The body of -cxx_initWithContentsOfFile: after the receiver's release (the facade's, until bead
        oo-9ht.68): the concrete sound it makes. The decoder is released at the end of the scope, as
        [decoder release] did.
*/
oo::Ref<OOSound> OOSound::initWithContentsOfFile(const std::optional<std::string>& path)
{
    if (!sIsSoundOK)
        return nullptr;

    if (!sIsSetUp && !setUp())
        return nullptr;

    oo::Ref<OOSound> self;

    const oo::Ref<OOALSoundDecoder> decoder = OOALSoundDecoder::initWithPath(path);
    if (nullptr == decoder)
        return nullptr;

    if (decoder->sizeAsBuffer() <= kMaxBufferedSoundSize) {
        self = OOALBufferedSound::initWithDecoder(decoder.get());
    } else {
        self = OOALStreamedSound::initWithDecoder(decoder.get());
    }

    if (nullptr != self) {
#ifndef NDEBUG
        OO_LOG(kOOLogSoundLoadingSuccess, "Loaded sound {}", path.value_or("(null)"));
#endif
    } else {
        OO_LOG(kOOLogSoundLoadingError, "Failed to load sound \"{}\"", path.value_or("(null)"));
    }

    return self;
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

// The facade's -cxx_description (bead oo-9ht.68 deleted it): the C++ class's name, without a
// namespace, its address and its components.
std::string OOSound::description() const
{
    int status = 0;
    char* demangled = abi::__cxa_demangle(typeid(*this).name(), nullptr, nullptr, &status);
    std::string name = (status == 0 && demangled != nullptr) ? demangled : typeid(*this).name();
    std::free(demangled);
    const std::size_t colons = name.rfind("::");
    if (colons != std::string::npos)
        name.erase(0, colons + 2);

    std::string result = oo::str::format("<%s %s>", name.c_str(), oo::str::pointerDescription(this).c_str());
    if (const std::optional<std::string> components = descriptionComponents())
        result += "{" + *components + "}";
    return result;
}
