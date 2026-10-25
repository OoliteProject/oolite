/*	test_OOSDLJoystickManager.mm
	Unit tests for OOSDLJoystickManager (src/SDL/OOSDLJoystickManager.h), the OOJoystickManager
	subclass: bead oo-o89, the Phase 3 platform (SDL/) pattern (proposed ADR-0056, amendment
	oo-o89). Its Objective-C facade was deleted by bead oo-9ht.2: the class derives from the C++
	OOJoystickManager and the tests call the same members.

	The SDL joystick layer runs against one SDL virtual joystick (SDL_AttachVirtualJoystick), with
	every hardware driver hinted off so a pad plugged into the machine cannot change the answers.
	The expectations were written against the Objective-C API and run on the unconverted class
	first: the stick is opened and named, SDL ids map to stick indices, the three event makers copy
	the event and translate its id, the axis is read from SDL, and handleSDLEvent: routes an event
	of a known stick to the superclass's decoder (whose state the test reads back) and refuses
	everything else.
	Run: bash tools/check-core-tests.sh
*/

#include "OOSDLJoystickManager.h"

#include "oo_test.hpp"

#include <SDL3/SDL.h>

#include <string>
#include <vector>


namespace {

const char *const kStickName = "oo-o89 virtual stick";


// The virtual stick, attached once before any manager is made (a manager opens the sticks that
// exist when it is initialised), and a handle of the test's own to drive its axes.
struct VirtualStick
{
	SDL_JoystickID	id = 0;
	SDL_Joystick	*handle = nullptr;
};


VirtualStick &Stick()
{
	static VirtualStick *stick = []
	{
		auto *s = new VirtualStick;
		SDL_SetHint(SDL_HINT_JOYSTICK_RAWINPUT, "0");
		SDL_SetHint(SDL_HINT_JOYSTICK_DIRECTINPUT, "0");
		SDL_SetHint(SDL_HINT_XINPUT_ENABLED, "0");
		SDL_SetHint(SDL_HINT_JOYSTICK_HIDAPI, "0");
		SDL_SetHint(SDL_HINT_JOYSTICK_WGI, "0");
		if (!SDL_Init(SDL_INIT_JOYSTICK))  return s;

		SDL_VirtualJoystickDesc desc;
		SDL_INIT_INTERFACE(&desc);
		desc.type = SDL_JOYSTICK_TYPE_GAMEPAD;
		desc.naxes = 2;
		desc.nbuttons = 4;
		desc.nhats = 1;
		desc.name = kStickName;
		s->id = SDL_AttachVirtualJoystick(&desc);
		if (s->id != 0)  s->handle = SDL_OpenJoystick(s->id);
		return s;
	}();
	return *stick;
}


SDL_Event AxisEvent(SDL_JoystickID which, Uint8 axis, Sint16 value)
{
	SDL_Event evt = {};
	evt.jaxis.type = SDL_EVENT_JOYSTICK_AXIS_MOTION;
	evt.jaxis.which = which;
	evt.jaxis.axis = axis;
	evt.jaxis.value = value;
	return evt;
}


SDL_Event ButtonEvent(SDL_JoystickID which, Uint8 button, bool down)
{
	SDL_Event evt = {};
	evt.jbutton.type = down ? SDL_EVENT_JOYSTICK_BUTTON_DOWN : SDL_EVENT_JOYSTICK_BUTTON_UP;
	evt.jbutton.which = which;
	evt.jbutton.button = button;
	evt.jbutton.down = down;
	return evt;
}


SDL_Event HatEvent(SDL_JoystickID which, Uint8 hat, Uint8 value)
{
	SDL_Event evt = {};
	evt.jhat.type = SDL_EVENT_JOYSTICK_HAT_MOTION;
	evt.jhat.which = which;
	evt.jhat.hat = hat;
	evt.jhat.value = value;
	return evt;
}

// As +alloc then -init made it: the SDL constructor, then the superclass's -init body.
oo::Ref<OOSDLJoystickManager> NewManager()
{
	oo::Ref<OOSDLJoystickManager> manager = oo::makeRef<OOSDLJoystickManager>();
	manager->init();
	return manager;
}


// The factory the game registers (MyOpenGLView.mm).
oo::Ref<OOJoystickManager> MakeSDLManager()
{
	return oo::makeRef<OOSDLJoystickManager>();
}

}	// namespace


OO_TEST(opensAndNamesTheSticks)
{
	VirtualStick &vs = Stick();
	OO_CHECK(vs.id != 0 && vs.handle != nullptr);

	{
		oo::Ref<OOSDLJoystickManager> manager = NewManager();
		OO_CHECK(manager != nullptr);
		OO_CHECK(manager->joystickCount() == 1);
		OO_CHECK(manager->nameOfJoystick(0) == std::optional<std::string>(kStickName));
		OO_CHECK(manager->nameOfJoystick(1) == std::optional<std::string>("(unknown joystick)"));
		OO_CHECK(manager->nameOfJoystick(MAX_STICKS) == std::optional<std::string>("(unknown joystick)"));

		// The superclass lists the sticks through the overrides.
		OO_CHECK(manager->listSticks() == std::vector<std::string>({ kStickName }));

		OO_CHECK(manager->getJoystickIndexFromId(vs.id) == 0);
		OO_CHECK(manager->getJoystickIndexFromId(vs.id + 100) == -1);
	}
}


OO_TEST(makesEvents)
{
	VirtualStick &vs = Stick();
	{
		oo::Ref<OOSDLJoystickManager> manager = NewManager();

		SDL_Event axis = AxisEvent(vs.id, 1, -1234);
		JoyAxisEvent a = manager->makeJoyAxisEvent(&axis.jaxis);
		OO_CHECK(a.type == SDL_EVENT_JOYSTICK_AXIS_MOTION && a.which == 0 && a.axis == 1 && a.value == -1234);

		SDL_Event button = ButtonEvent(vs.id, 3, true);
		JoyButtonEvent b = manager->makeJoyButtonEvent(&button.jbutton);
		OO_CHECK(b.type == SDL_EVENT_JOYSTICK_BUTTON_DOWN && b.which == 0 && b.button == 3 && b.down);

		SDL_Event hat = HatEvent(vs.id, 0, SDL_HAT_UP);
		JoyHatEvent h = manager->makeJoyHatEvent(&hat.jhat);
		OO_CHECK(h.type == SDL_EVENT_JOYSTICK_HAT_MOTION && h.which == 0 && h.hat == 0 && h.value == SDL_HAT_UP);

		// An unknown stick's id becomes -1 (as an SDL_JoystickID, which is what the caller tests).
		SDL_Event stray = AxisEvent(vs.id + 100, 0, 1);
		OO_CHECK((int)manager->makeJoyAxisEvent(&stray.jaxis).which == -1);
	}
}


OO_TEST(readsAxesFromSDL)
{
	VirtualStick &vs = Stick();
	{
		oo::Ref<OOSDLJoystickManager> manager = NewManager();
		SDL_SetJoystickVirtualAxis(vs.handle, 0, 5000);
		SDL_SetJoystickVirtualAxis(vs.handle, 1, -300);
		SDL_UpdateJoysticks();
		OO_CHECK(manager->getAxisWithStick(0, 0) == 5000);
		OO_CHECK(manager->getAxisWithStick(0, 1) == -300);
	}
}


OO_TEST(handlesEventsThroughTheSuperclass)
{
	VirtualStick &vs = Stick();
	{
		// As the game makes it: the SDL class registered with the superclass, which creates it.
		OO_CHECK(OOJoystickManager::setStickHandlerFactory(MakeSDLManager));
		OOSDLJoystickManager *manager = dynamic_cast<OOSDLJoystickManager *>(OOJoystickManager::sharedStickHandler());
		OO_CHECK(manager != nullptr);
		OO_CHECK(manager->joystickCount() == 1);

		SDL_Event down = ButtonEvent(vs.id, 2, true);
		OO_CHECK(manager->handleSDLEvent(&down));
		OO_CHECK(manager->isButtonDown(2, 0));
		SDL_Event up = ButtonEvent(vs.id, 2, false);
		OO_CHECK(manager->handleSDLEvent(&up));
		OO_CHECK(!manager->isButtonDown(2, 0));

		// A hat is decoded as four buttons past the real ones.
		SDL_Event hat = HatEvent(vs.id, 0, SDL_HAT_UP);
		OO_CHECK(manager->handleSDLEvent(&hat));
		OO_CHECK(manager->isButtonDown(MAX_REAL_BUTTONS, 0));
		SDL_Event centred = HatEvent(vs.id, 0, SDL_HAT_CENTERED);
		OO_CHECK(manager->handleSDLEvent(&centred));
		OO_CHECK(!manager->isButtonDown(MAX_REAL_BUTTONS, 0));

		SDL_Event axis = AxisEvent(vs.id, 0, 100);
		OO_CHECK(manager->handleSDLEvent(&axis));

		// An event it does not handle is refused. (Not pinned: an event of a stick it did not open.
		// Its index is -1 in an unsigned SDL_JoystickID, so the `which >= 0` guard lets it through
		// to the decoder, which indexes its tables with it; bead oo-o89's report.)
		SDL_Event key = {};
		key.type = SDL_EVENT_KEY_DOWN;
		OO_CHECK(!manager->handleSDLEvent(&key));
	}
}


// An event of a stick the manager did not open (one hot-plugged after it was made) is refused and
// leaves the superclass's state alone (bead oo-9ht.3). Its index, -1, used to be stored in the
// unsigned SDL_JoystickID, so the `which >= 0` guard let it through to the decoder, which indexed
// its per-stick tables with it.
OO_TEST(refusesEventsOfAStickItDidNotOpen)
{
	VirtualStick &vs = Stick();
	const SDL_JoystickID stray = vs.id + 100;
	{
		oo::Ref<OOSDLJoystickManager> manager = NewManager();
		OO_CHECK(manager->getJoystickIndexFromId(stray) == -1);

		SDL_Event down = ButtonEvent(vs.id, 0, true);
		OO_CHECK(manager->handleSDLEvent(&down));
		OO_CHECK(manager->isButtonDown(0, 0));

		SDL_Event strayUp = ButtonEvent(stray, 0, false);
		OO_CHECK(!manager->handleSDLEvent(&strayUp));
		OO_CHECK(manager->isButtonDown(0, 0));

		SDL_Event strayHat = HatEvent(stray, 0, SDL_HAT_UP);
		OO_CHECK(!manager->handleSDLEvent(&strayHat));
		OO_CHECK(!manager->isButtonDown(MAX_REAL_BUTTONS, 0));

		SDL_Event strayAxis = AxisEvent(stray, 0, 100);
		OO_CHECK(!manager->handleSDLEvent(&strayAxis));

		SDL_Event up = ButtonEvent(vs.id, 0, false);
		OO_CHECK(manager->handleSDLEvent(&up));
		OO_CHECK(!manager->isButtonDown(0, 0));
	}
}


OO_TEST_MAIN()
