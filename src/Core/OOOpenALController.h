/*

OOOpenALController.h

Singleton controller for Open AL interfaces

C++20 since bead oo-r7m0 (proposed ADR-0056). Every caller was adapted in that bead, so there is
no Objective-C facade and the class is global.

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

#ifndef OOOPENALCONTROLLER_H
#define OOOPENALCONTROLLER_H

#include "OOOpenAL.h"

#include "oofnd/Ref.hpp"
#include "oofnd/StdLib.hpp"

// Log message classes, UTF-8 (Foundation sweep, proposed ADR-0043): an OOLog call passes
// oo::NSStringFrom(kOOLogSound...) until it is converted to OO_LOG.
static constexpr const char* kOOLogSoundInitError = "sound.initialization.error";
static constexpr const char* kOOLogSoundLoadingSuccess = "sound.load.success";
static constexpr const char* kOOLogSoundLoadingError = "sound.load.error";

class OOOpenALController : public oo::RefCounted {
public:
    /*	The shared controller, made on first use; borrowed (it is never released). Null when
            init() refused it, and then the next call makes and asks a new one.
    */
    static OOOpenALController* sharedController();

    void setMasterVolume(ALfloat fraction);
    ALfloat masterVolume();

    void shutdown();

    /**
     * \ingroup cli
     * Scans the command line for -nosound or --nosound arguments.
     *
     * @return returns true if sound shall be played and can be played,
     *         otherwise false (the controller is then discarded)
     */
    bool init();

private:
    ALCdevice* device = { };
    ALCcontext* context = { };
};

#endif // OOOPENALCONTROLLER_H
