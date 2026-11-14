/*

OOOpenALController.mm


Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
MA 02110-1301, USA.

*/

#include "OOOpenALController.h"
#include "OOALSoundMixer.h"
#include "OOLogging.h"
#include "oofnd/Log.hpp"
#include "oofnd/Process.hpp"

namespace {

OOOpenALController* sSingleton = nullptr; // +1, never released (the retained singleton)

} // namespace

OOOpenALController* OOOpenALController::sharedController()
{
    if (sSingleton == nullptr) {
        // -init's [self release]; return nil; is init() answering false: the controller is freed.
        oo::Ref<OOOpenALController> controller = oo::makeRef<OOOpenALController>();
        if (controller->init())
            sSingleton = controller.leakRef();
    }

    return sSingleton;
}

bool OOOpenALController::init()
{
    if (oo::process::hasArgument("-nosound") || oo::process::hasArgument("--nosound")) {
        return false;
    }

    ALuint error = AL_NO_ERROR;
    device = alcOpenDevice(NULL); // default device
    if (!device) {
        OO_LOG(kOOLogSoundInitError, "{}", "Failed to open default sound device");
        return false;
    }
    context = alcCreateContext(device, NULL); // default context
    if (!alcMakeContextCurrent(context)) {
        OO_LOG(kOOLogSoundInitError, "{}", "Failed to create default sound context");
        return false;
    }
    error = alGetError(); // out of the condition (clang-tidy bugprone-assignment-in-if-condition)
    if (error != AL_NO_ERROR) {
        OO_LOG(kOOLogSoundInitError, "Error {} creating sound context", error);
    }
    OOAL(alDistanceModel(AL_NONE));
    return true;
}

void OOOpenALController::setMasterVolume(ALfloat fraction)
{
    OOAL(alListenerf(AL_GAIN, fraction));
}

ALfloat OOOpenALController::masterVolume()
{
    ALfloat fraction = 0.0;
    OOAL(alGetListenerf(AL_GAIN, &fraction));
    return fraction;
}

// only to be called at app shutdown
// is there a better way to handle this?
void OOOpenALController::shutdown()
{
    if (OOSoundMixer* mixer = OOSoundMixer::sharedMixer())
        mixer->shutdown();
    OOAL(alcMakeContextCurrent(NULL));
    OOAL(alcDestroyContext(context));
    OOAL(alcCloseDevice(device));
}
