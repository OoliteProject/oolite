/*	test_OOOpenALController.mm
	Unit tests for OOOpenALController (src/Core/OOOpenALController.h): bead oo-r7m0, a Phase 3
	class conversion (proposed ADR-0056). Its callers were adapted in the bead, so it has no
	Objective-C facade and there is no facade contract to test.

	OpenAL runs on OpenAL Soft's null backend (ALSOFT_DRIVERS=null, set before the first ALC
	call), so the machine's sound hardware cannot change the answers and a machine without any
	still opens a device. The expectations were written against the Objective-C API and run on
	the unconverted class first: -nosound and --nosound refuse the controller, and it is asked
	again on the next call; otherwise the one shared controller opens a device, makes its context
	current with no distance model, reads and writes the listener's gain, and shutdown tells the
	sound mixer and releases the context. OOSoundMixer is this file's stub, which counts the
	shutdown it is sent (the real mixer would drag the whole sound system into the link).
	Run: bash tools/check-core-tests.sh
*/

#import "OOOpenALController.h"
#import "OOALSoundMixer.h"

#include "oo_test.hpp"
#include "oofnd/Process.hpp"

#include <cmath>
#include <cstdlib>


static unsigned sMixerShutdowns = 0;


// The mixer (a C++ stand-in since bead oo-9ht.87 deleted the Objective-C facade this file stubbed):
// one, never released, counting the shutdowns the controller sends it.
OOSoundMixer *OOSoundMixer::sharedMixer()
{
	static OOSoundMixer *mixer = oo::makeRef<OOSoundMixer>().leakRef();
	return mixer;
}


void OOSoundMixer::shutdown()
{
	sMixerShutdowns++;
}


namespace {

void SetArguments(std::initializer_list<const char *> args)
{
	std::vector<const char *> argv(args);
	oo::process::setArguments(static_cast<int>(argv.size()), argv.data());
}


bool Near(float a, float b)
{
	return std::fabs(a - b) < 1e-6f;
}

}	// namespace


OO_TEST(noSoundArgumentsRefuseTheController)
{
	_putenv_s("ALSOFT_DRIVERS", "null");

	SetArguments({ "test_OOOpenALController", "-nosound" });
	OO_CHECK(OOOpenALController::sharedController() == nullptr);
	OO_CHECK(OOOpenALController::sharedController() == nullptr);
	SetArguments({ "test_OOOpenALController", "--nosound" });
	OO_CHECK(OOOpenALController::sharedController() == nullptr);
	OO_CHECK(alcGetCurrentContext() == nullptr);	// no device was opened

	// A refusal is not remembered: the next call asks again.
	SetArguments({ "test_OOOpenALController" });
	OO_CHECK(OOOpenALController::sharedController() != nullptr);
}


OO_TEST(opensTheDefaultDevice)
{
	OOOpenALController *controller = OOOpenALController::sharedController();
	OO_CHECK(controller != nullptr);
	OO_CHECK(OOOpenALController::sharedController() == controller);

	ALCcontext *context = alcGetCurrentContext();
	OO_CHECK(context != nullptr);
	ALCdevice *device = context != nullptr ? alcGetContextsDevice(context) : nullptr;
	OO_CHECK(device != nullptr);
	const ALCchar *name = device != nullptr ? alcGetString(device, ALC_ALL_DEVICES_SPECIFIER) : nullptr;
	OO_CHECK(name != nullptr && std::string(name).find("No Output") != std::string::npos);
	OO_CHECK(alGetInteger(AL_DISTANCE_MODEL) == AL_NONE);
	OO_CHECK(alGetError() == AL_NO_ERROR);
}


OO_TEST(masterVolumeIsTheListenerGain)
{
	OOOpenALController *controller = OOOpenALController::sharedController();
	OO_CHECK(Near(controller->masterVolume(), 1.0f));	// OpenAL's default gain

	controller->setMasterVolume(0.25f);
	OO_CHECK(Near(controller->masterVolume(), 0.25f));
	ALfloat gain = 0.0f;
	alGetListenerf(AL_GAIN, &gain);
	OO_CHECK(Near(gain, 0.25f));

	alListenerf(AL_GAIN, 0.75f);
	OO_CHECK(Near(controller->masterVolume(), 0.75f));

	// An invalid gain leaves the gain alone. OOAL clears the error before the call, not after.
	controller->setMasterVolume(-1.0f);
	OO_CHECK(alGetError() == AL_INVALID_VALUE);
	OO_CHECK(Near(controller->masterVolume(), 0.75f));
	alGetError();
	controller->setMasterVolume(0.5f);
	OO_CHECK(alGetError() == AL_NO_ERROR);
}


// Last: it destroys the shared controller's context.
OO_TEST(shutdownStopsTheMixerAndReleasesTheContext)
{
	OOOpenALController *controller = OOOpenALController::sharedController();
	OO_CHECK(alcGetCurrentContext() != nullptr);
	OO_CHECK(sMixerShutdowns == 0);

	controller->shutdown();
	OO_CHECK(sMixerShutdowns == 1);
	OO_CHECK(alcGetCurrentContext() == nullptr);

	// The shared controller is not replaced.
	OO_CHECK(OOOpenALController::sharedController() == controller);
}


OO_TEST_MAIN()
