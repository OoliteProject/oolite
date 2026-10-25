/*

MyOpenGLView+Input.mm

Oolite

*/

#include <SDL3/SDL_init.h>
#include "MyOpenGLView.h"

#include "GameController.h"
#include "Universe.h"
#include "OOSDLJoystickManager.h"
#include "PlayerEntity.h"
#include "ResourceManager.h"
#include "oofnd/Date.hpp"
#include "oofnd/Defaults.hpp"
#include "oofnd/PListGet.hpp"
#include "oofnd/String.hpp"


namespace {

// What -appendFormat:@"%c" appended for a character code 0..255: the Latin-1 character U+0000..U+00FF
// (GNUstep 1.31.1, captured for 32..255 by a throwaway probe, bead oo-3rb.113), as UTF-8.
std::string FormattedCharacter(unsigned code)
{
	return oo::utf16ToUtf8(std::u16string(1, static_cast<char16_t>(code & 0xFFu)));
}

} // namespace

// The input half of MyOpenGLView (ADR-0056 amendments oo-o89 item 4, oo-6rb6 item 1; bead oo-0806):
// the former (Input) category, as members, which other classes call (the facade that forwarded them
// went with bead oo-9ht.153).

void MyOpenGLView::initKeyMappingData()
{
	// load in our keyboard scancode mappings
#if OOLITE_WINDOWS	
	const oo::PList kmap = ResourceManager::dictionaryFromFilesNamed("keymappings_windows.plist", "Config", MERGE_BASIC, NO);
#else
	const oo::PList kmap = ResourceManager::dictionaryFromFilesNamed("keymappings_linux.plist", "Config", MERGE_BASIC, NO);
#endif
	// get the stored keyboard code from preferences (oo_stringForKey:defaultValue: over the value)
	const oo::PList kbdValue = oo::Defaults::standard().object("keyboard-code");
	const std::string kbd = oo::PListGet<std::string>::from(kbdValue.isNull() ? nullptr : &kbdValue, "default");
	const oo::PList *subset = kmap.find(kbd);
	const oo::PList *normal = (subset != nullptr) ? subset->find("mapping_normal") : nullptr;
	const oo::PList *shifted = (subset != nullptr) ? subset->find("mapping_shifted") : nullptr;

	keyMappings_normal = (normal != nullptr) ? *normal : oo::PList();
	keyMappings_shifted = (shifted != nullptr) ? *shifted : oo::PList();
}
void MyOpenGLView::autoShowMouse()
{
	//don't touch the 'please wait...' cursor.
	if (fullScreen)
	{
		if (SDL_CursorVisible())
			SDL_HideCursor();
	}
	else
	{
		if (!SDL_CursorVisible())
			SDL_ShowCursor();
	}
}
void MyOpenGLView::setStringInput(enum StringInput value)
{
	allowingStringInput = value;
}
void MyOpenGLView::allowStringInput(bool value)
{
	if (value)
		allowingStringInput = gvStringInputAlpha;
	else
		allowingStringInput = gvStringInputNo;
}
enum StringInput MyOpenGLView::getAllowingStringInput()
{
	return allowingStringInput;
}
std::optional<std::string> MyOpenGLView::getTypedString()
{
	return typedString;
}
void MyOpenGLView::resetTypedString()
{
	typedString.clear();
}
void MyOpenGLView::setTypedString(const std::string &value)
{
	typedString = value;
}
void MyOpenGLView::noteMouseInteractionModeChangedFrom(OOMouseInteractionMode /*oldMode*/, OOMouseInteractionMode newMode)
{
	autoShowMouse();
	setMouseInDeltaMode(OOMouseInteractionModeIsFlightMode(newMode));
}
void MyOpenGLView::setVirtualJoystick(double vmx, double vmy)
{
	virtualJoystickPosition.x = vmx;
	virtualJoystickPosition.y = vmy;
}
NSPoint MyOpenGLView::getVirtualJoystickPosition()
{
	return virtualJoystickPosition;
}


/////////////////////////////////////////////////////////////
void MyOpenGLView::clearKeys()
{
	int i;
	lastKeyShifted = NO;
	for (i = 0; i < numKeys(); i++)
		keys[i] = NO;
}
void MyOpenGLView::clearMouse()
{
	keys[gvMouseDoubleClick] = NO;
	keys[gvMouseLeftButton] = NO;
	doubleClick = NO;
}
void MyOpenGLView::clearKey(int theKey)
{
	if (theKey >= 0 && theKey < numKeys())
	{
		keys[theKey] = NO;
	}
}
void MyOpenGLView::resetMouse()
{
	setVirtualJoystick(0.0, 0.0);
	if (::PlayerEntity::sharedPlayer()->isMouseControlOn())
	{
		SDL_WarpMouseInWindow(window, viewSize.width / 2, viewSize.height / 2);
		mouseWarped = YES;
	}
}
bool MyOpenGLView::getIsAlphabetKeyDown()
{
	return isAlphabetKeyDown = NO;;
}

// DJS: When entering submenus in the gui, it is not helpful if the
// key down that brought you into the submenu is still registered
// as down when we're in. This makes isDown return NO until a key up
// event has been received from SDL.
void MyOpenGLView::suppressKeysUntilKeyUp()
{
	if (keys[gvMouseDoubleClick] == NO)
   	{
   		suppressKeys = YES;
   		clearKeys();
   	}
   	else
   	{
   		clearMouse();
   	}

}
bool MyOpenGLView::isDown(int key)
{
	if ( suppressKeys )
		return NO;
	if ( key < 0 )
		return NO;
	if ( key >= numKeys() )
		return NO;
	return keys[key];
}
bool MyOpenGLView::isOptDown()
{
	return opt;
}
bool MyOpenGLView::isCtrlDown()
{
	return ctrl;
}
bool MyOpenGLView::isCommandDown()
{
	return command;
}
bool MyOpenGLView::isShiftDown()
{
	return shift;
}
bool MyOpenGLView::isCapsLockOn()
{
	/* Caps Lock state check - This effectively gives us
	   an alternate keyboard state to play with and, in
	   the future, we could assign different behaviours
	   to existing controls, depending on the state of
	   Caps Lock. - Nikos 20160304
	*/
	return (SDL_GetModState() & SDL_KMOD_CAPS) == SDL_KMOD_CAPS;
}
bool MyOpenGLView::lastKeyWasShifted()
{
	return lastKeyShifted;
}
int MyOpenGLView::numKeys()
{
	return NUM_KEYS;
}
int MyOpenGLView::mouseWheelState()
{
	if (_mouseWheelDelta > 0.0f)
		return gvMouseWheelUp;
	else if (_mouseWheelDelta < 0.0f)
		return gvMouseWheelDown;
	else
		return gvMouseWheelNeutral;
}
float MyOpenGLView::mouseWheelDelta()
{
	return _mouseWheelDelta / OOMOUSEWHEEL_DELTA;
}
void MyOpenGLView::setMouseWheelDelta(float newWheelDelta)
{
	_mouseWheelDelta = newWheelDelta * OOMOUSEWHEEL_DELTA;
}
bool MyOpenGLView::isCommandQDown()
{
	return NO;
}
bool MyOpenGLView::isCommandFDown()
{
	return NO;
}
void MyOpenGLView::clearCommandF()
{
	// SDL stub for the mac function.
}
void MyOpenGLView::pollControls()
{
	SDL_Event				event;
	SDL_KeyboardEvent		*kbd_event;
	SDL_MouseButtonEvent	*mbtn_event;
	SDL_MouseMotionEvent	*mmove_event;
	SDL_MouseWheelEvent	*mw_event;
 	float						mxdelta, mydelta;
	float					mouseVirtualStickSensitivityX = viewSize.width * _mouseVirtualStickSensitivityFactor;
	float					mouseVirtualStickSensitivityY = viewSize.height * _mouseVirtualStickSensitivityFactor;
	NSTimeInterval			timeNow = oo::date::monotonicSeconds();	// same clock as MyOpenGLView.mm's -init
	Uint16	 				key_id;
	SDL_Scancode				scan_code;
	float inDelta;
	bool					resize_pending = false;

	while (SDL_PollEvent(&event))
	{
		switch (event.type) {
			case SDL_EVENT_JOYSTICK_AXIS_MOTION:
			case SDL_EVENT_JOYSTICK_BUTTON_UP:
			case SDL_EVENT_JOYSTICK_BUTTON_DOWN:
			case SDL_EVENT_GAMEPAD_AXIS_MOTION:
			case SDL_EVENT_GAMEPAD_BUTTON_UP:
			case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
			case SDL_EVENT_JOYSTICK_HAT_MOTION:
				static_cast<OOSDLJoystickManager *>(OOJoystickManager::sharedStickHandler())->handleSDLEvent(&event);	// the registered SDL handler (was a C cast)
				break;

			case SDL_EVENT_MOUSE_BUTTON_DOWN:
				mbtn_event = (SDL_MouseButtonEvent*)&event;

				switch(mbtn_event->button)
				{
					case SDL_BUTTON_LEFT:
						keys[gvMouseLeftButton] = YES;
						break;
					case SDL_BUTTON_RIGHT:
						// Cocoa version does this in the GameController
						/*
						 The mouseWarped variable is quite important as far as mouse control is concerned. When we
						 reset the virtual joystick (mouse) coordinates, we need to send a WarpMouse call because we
						 must recenter the pointer physically on screen. This goes together with a mouse motion event,
						 so we use mouseWarped to simply ignore handling of motion events in this case. - Nikos 20110721
						*/
						resetMouse(); // Will set mouseWarped to YES
						break;
					// mousewheel stuff

				}
				break;

			case SDL_EVENT_MOUSE_BUTTON_UP:
				mbtn_event = (SDL_MouseButtonEvent*)&event;
				// Timed by the release itself, not by this poll (bugs oo-3rb.333/oo-3rb.336). timeNow is
				// sampled once as the poll starts, so the two releases of one double-click - 50 ms apart -
				// that straddled a poll which stalled (measured: 0.86 s) were timed as 0.9 s apart and the
				// double-click became two single clicks. SDL stamps every event on the SDL_GetTicksNS()
				// clock when it is queued, which is the clock timeIntervalAtLastClick starts on.
				NSTimeInterval timeOfClick; timeOfClick = (NSTimeInterval)mbtn_event->timestamp / 1e9;
				NSTimeInterval timeBetweenClicks; timeBetweenClicks = timeOfClick - timeIntervalAtLastClick;
				timeIntervalAtLastClick += timeBetweenClicks;
				if (mbtn_event->button == SDL_BUTTON_LEFT)
				{
					if (!doubleClick)
					{
						doubleClick = (timeBetweenClicks < MOUSE_DOUBLE_CLICK_INTERVAL);	// One fifth of a second
						keys[gvMouseDoubleClick] = doubleClick;
					}
					keys[gvMouseLeftButton] = NO;
				}
				break;

			case SDL_EVENT_MOUSE_WHEEL:
				mw_event = (SDL_MouseWheelEvent*)&event;

				inDelta = mw_event->y;
				if (inDelta > 0)
				{
					if (_mouseWheelDelta >= 0.0f)
						_mouseWheelDelta += inDelta;
					else
						_mouseWheelDelta = 0.0f;
				}
				else if (inDelta < 0)
				{
					if (_mouseWheelDelta <= 0.0f)
						_mouseWheelDelta += inDelta;
					else
						_mouseWheelDelta = 0.0f;
				}
				/* 
				   Mousewheel handling - just note time since last use here and mark as inactive,
				   if needed, at the end of this method. Note that the mousewheel button up event is 
				   kind of special, as in, it is sent at the same time as its corresponding mousewheel
				   button down one - Nikos 20140809
				*/
				NSTimeInterval timeBetweenMouseWheels; timeBetweenMouseWheels = timeNow - timeSinceLastMouseWheel;
				timeSinceLastMouseWheel += timeBetweenMouseWheels;
				break;

			case SDL_EVENT_MOUSE_MOTION:
			{
				// Delta mode is set when the game is in 'flight' mode.
				// In this mode, the mouse movement delta is used rather
				// than absolute position. This is because if the user
				// clicks the right button to recentre the virtual joystick,
				// if we are using absolute joystick positioning, as soon
				// as the player touches the mouse again, the virtual joystick
				// will snap back to the absolute position (which can be
				// annoyingly fatal in battle).
				if(mouseInDeltaMode)
				{
					// note: virtual stick sensitivity is configurable
					SDL_GetRelativeMouseState(&mxdelta, &mydelta);
					double mxd=(double)mxdelta / mouseVirtualStickSensitivityX;
					double myd=(double)mydelta / mouseVirtualStickSensitivityY;

					if (!mouseWarped) // Standard event, update coordinates
					{
						virtualJoystickPosition.x += mxd;
						virtualJoystickPosition.y += myd;

						// if we excceed the limits, revert changes
						if(fabs(virtualJoystickPosition.x) > MOUSEX_MAXIMUM)
						{
							virtualJoystickPosition.x -= mxd;
						}
						if(fabs(virtualJoystickPosition.y) > MOUSEY_MAXIMUM)
						{
							virtualJoystickPosition.y -= myd;
						}
					}
					else
					{
						// Motion event generated by WarpMouse is ignored and
						// we reset mouseWarped for the next time.
						mouseWarped = NO;
					}
				}
				else
				{
					// Windowed mode. Use the absolute position so the
					// Oolite mouse pointer appears under the X Window System
					// mouse pointer.
					mmove_event = (SDL_MouseMotionEvent*)&event;

					int w=viewSize.width;
					int h=viewSize.height;

					if (!mouseWarped) // standard event, handle it
					{
						double mx = mmove_event->x - w/2.0;
						double my = mmove_event->y - h/2.0;
						if (display_z > 640.0)
						{
							mx /= w * MAIN_GUI_PIXEL_WIDTH / display_z;
							my /= h;
						}
						else
						{
							mx /= MAIN_GUI_PIXEL_WIDTH * w / 640.0;
							my /= MAIN_GUI_PIXEL_HEIGHT * w / 640.0;
						}

						setVirtualJoystick(mx, my);
					}
					else
					{
						// event coming from WarpMouse ignored, get ready for the next
						mouseWarped = NO;
					}
				}
				break;
			}
			case SDL_EVENT_KEY_DOWN:
				kbd_event = (SDL_KeyboardEvent*)&event;
				key_id = SDL_GetKeyFromScancode(kbd_event->scancode, kbd_event->mod, NO);
				scan_code = kbd_event->scancode;

				//char *keychar = SDL_GetKeyName(kbd_event->keysym.sym);
				// deal with modifiers first
				BOOL modifier_pressed; modifier_pressed = NO;
				BOOL special_key; special_key = NO;

				shift = (kbd_event->mod & SDL_KMOD_SHIFT) != 0;
				ctrl = (kbd_event->mod & SDL_KMOD_CTRL) != 0;
				opt = (kbd_event->mod & SDL_KMOD_ALT) != 0;

				// translate scancode to unicode equiv
				switch (kbd_event->key) 
				{
					case SDLK_LSHIFT:
					case SDLK_RSHIFT:
					case SDLK_LCTRL:
					case SDLK_RCTRL:
					case SDLK_LALT:
					case SDLK_RALT:
						modifier_pressed = YES;
						break;

					case SDLK_KP_0: key_id = (!allowingStringInput ? gvNumberPadKey0 : gvNumberKey0); special_key = YES; break;
					case SDLK_KP_1: key_id = (!allowingStringInput ? gvNumberPadKey1 : gvNumberKey1); special_key = YES; break;
					case SDLK_KP_2: key_id = (!allowingStringInput ? gvNumberPadKey2 : gvNumberKey2); special_key = YES; break;
					case SDLK_KP_3: key_id = (!allowingStringInput ? gvNumberPadKey3 : gvNumberKey3); special_key = YES; break;
					case SDLK_KP_4: key_id = (!allowingStringInput ? gvNumberPadKey4 : gvNumberKey4); special_key = YES; break;
					case SDLK_KP_5: key_id = (!allowingStringInput ? gvNumberPadKey5 : gvNumberKey5); special_key = YES; break;
					case SDLK_KP_6: key_id = (!allowingStringInput ? gvNumberPadKey6 : gvNumberKey6); special_key = YES; break;
					case SDLK_KP_7: key_id = (!allowingStringInput ? gvNumberPadKey7 : gvNumberKey7); special_key = YES; break;
					case SDLK_KP_8: key_id = (!allowingStringInput ? gvNumberPadKey8 : gvNumberKey8); special_key = YES; break;
					case SDLK_KP_9: key_id = (!allowingStringInput ? gvNumberPadKey9 : gvNumberKey9); special_key = YES; break;
					case SDLK_KP_PERIOD: key_id = (!allowingStringInput ? gvNumberPadKeyPeriod : 46); special_key = YES; break;
					case SDLK_KP_DIVIDE: key_id = (!allowingStringInput ? gvNumberPadKeyDivide : 47); special_key = YES; break;
					case SDLK_KP_MULTIPLY: key_id = (!allowingStringInput ? gvNumberPadKeyMultiply : 42); special_key = YES; break;
					case SDLK_KP_MINUS: key_id = (!allowingStringInput ? gvNumberPadKeyMinus : 45); special_key = YES; break;
					case SDLK_KP_PLUS: key_id = (!allowingStringInput ? gvNumberPadKeyPlus : 43); special_key = YES; break;
					case SDLK_KP_EQUALS: key_id = (!allowingStringInput ? gvNumberPadKeyEquals : 61); special_key = YES; break;
					case SDLK_KP_ENTER: key_id = gvNumberPadKeyEnter; special_key = YES; break;
					case SDLK_HOME: key_id = gvHomeKey; special_key = YES; break;
					case SDLK_END: key_id = gvEndKey; special_key = YES; break;
					case SDLK_INSERT: key_id = gvInsertKey; special_key = YES; break;
					case SDLK_PAGEUP: key_id = gvPageUpKey; special_key = YES; break;
					case SDLK_PAGEDOWN: key_id = gvPageDownKey; special_key = YES; break;
					case SDLK_SPACE: key_id = 32; special_key = YES; break;
					case SDLK_RETURN: key_id = 13; special_key = YES; break;
					case SDLK_TAB: key_id = 9; special_key = YES; break;
					case SDLK_UP: key_id = gvArrowKeyUp; special_key = YES; break;
					case SDLK_DOWN: key_id = gvArrowKeyDown; special_key = YES; break;
					case SDLK_LEFT: key_id = gvArrowKeyLeft; special_key = YES; break;
					case SDLK_RIGHT: key_id = gvArrowKeyRight; special_key = YES; break;
					case SDLK_PAUSE: key_id = gvPauseKey; special_key = YES; break;
					case SDLK_BACKSPACE: key_id = gvBackspaceKey; special_key = YES; break;
					case SDLK_DELETE: key_id = gvDeleteKey; special_key = YES; break;
					case SDLK_F1: key_id = gvFunctionKey1; special_key = YES; break;
					case SDLK_F2: key_id = gvFunctionKey2; special_key = YES; break;
					case SDLK_F3: key_id = gvFunctionKey3; special_key = YES; break;
					case SDLK_F4: key_id = gvFunctionKey4; special_key = YES; break;
					case SDLK_F5: key_id = gvFunctionKey5; special_key = YES; break;
					case SDLK_F6: key_id = gvFunctionKey6; special_key = YES; break;
					case SDLK_F7: key_id = gvFunctionKey7; special_key = YES; break;
					case SDLK_F8: key_id = gvFunctionKey8; special_key = YES; break;
					case SDLK_F9: key_id = gvFunctionKey9; special_key = YES; break;
					case SDLK_F10: key_id = gvFunctionKey10; special_key = YES; break;
					case SDLK_F11: key_id = gvFunctionKey11; special_key = YES; break;
					case SDLK_F12:
						key_id = 327;
						toggleScreenMode();
						special_key = YES; 
						break;

					case SDLK_ESCAPE:
						if (shift)
						{
							SDL_DestroyWindow(window);
							if (gameController != nullptr)  gameController->exitAppWithContext("Shift-escape pressed");
						}
						else
						{
							key_id = 27;
							special_key = YES;
						}
						break;
					default:
						//OO_LOG("keys.test", "Unhandled Keydown scancode with unicode = 0: {}", static_cast<int>(scan_code));
						;
				}

				// the keyup event doesn't give us the unicode value, so store it here so it can be retrieved on keyup
				// the ctrl key tends to mix up the unicode values, so deal with some special cases
				// we also need (in most cases) to get the character without the impact of caps lock. 

				if (((!special_key && (ctrl || key_id == 0)) || (isCapsLockOn() && (!special_key && !allowingStringInput))) && !modifier_pressed) //  
				{
					// ctrl changes alpha characters to control codes (1-26)
					if (ctrl && key_id >=1 && key_id <= 26) 
					{
						if (shift) 
							key_id += 64; // A-Z is from 65, offset by -1 for the scancode start point
						else
							key_id += 96; // a-z is from 97, offset by -1 for the scancode start point
					} 
					else 
					{
						// SDL3 - the key_id should contain the correct unicode value, so we shouldn't need to run the key mapping
						// - kanthoney
						//key_id = 0; // reset the value here to force a lookup from the keymappings data
					}
				}

				// if we've got the unicode value, we can store it in our array now
				if (key_id > 0) scancode2Unicode[scan_code] = key_id;

				if(allowingStringInput && !modifier_pressed)
				{
					handleStringInput(kbd_event, key_id);
				}

				OO_LOG("input.keyMapping.keyPress.keyDown", "Keydown scancode = {}, unicode = {}", static_cast<int>(scan_code), static_cast<int>(key_id));

				if (key_id > 0 && key_id < numKeys()) 
				{
					keys[key_id] = YES;
				}
				else 
				{
					OO_LOG("keys.test", "Unhandled Keydown scancode/unicode: {} {}", static_cast<int>(scan_code), static_cast<int>(key_id));
				}
				break;

			case SDL_EVENT_KEY_UP:
				suppressKeys = NO;    // DJS
				kbd_event = (SDL_KeyboardEvent*)&event;
				scan_code = kbd_event->scancode;

				shift = kbd_event->mod & SDL_KMOD_SHIFT;
				ctrl = kbd_event->mod & SDL_KMOD_CTRL;
				opt = kbd_event->mod & SDL_KMOD_ALT;

				// all the work should have been down on the keydown event, so all we need to do is get the unicode value from the array
				key_id = scancode2Unicode[scan_code];

				// deal with modifiers first
				switch (kbd_event->key)
				{
					case SDLK_LSHIFT:
					case SDLK_RSHIFT:
						shift = NO;
						break;

					case SDLK_LCTRL:
					case SDLK_RCTRL:
						ctrl = NO;
						break;
						
					case SDLK_LALT:
					case SDLK_RALT:
						opt = NO;
						break;
					default:
						;
				}
				OO_LOG("input.keyMapping.keyPress.keyUp", "Keyup scancode = {}, unicode = {}, character = {}, shift = {}, ctrl = {}, alt = {}", static_cast<int>(scan_code), static_cast<int>(key_id), static_cast<char>(key_id), static_cast<int>(shift), static_cast<int>(ctrl), static_cast<int>(opt));
				//OO_LOG("input.keyMapping.keyPress.keyUp", "Keyup scancode = {}, shift = {}, ctrl = {}, alt = {}", static_cast<int>(scan_code), static_cast<int>(shift), static_cast<int>(ctrl), static_cast<int>(opt));
				
				// translate scancode to unicode equiv
				switch (kbd_event->key) 
				{
					case SDLK_KP_0: key_id = (!allowingStringInput ? gvNumberPadKey0 : gvNumberKey0); break;
					case SDLK_KP_1: key_id = (!allowingStringInput ? gvNumberPadKey1 : gvNumberKey1); break;
					case SDLK_KP_2: key_id = (!allowingStringInput ? gvNumberPadKey2 : gvNumberKey2); break;
					case SDLK_KP_3: key_id = (!allowingStringInput ? gvNumberPadKey3 : gvNumberKey3); break;
					case SDLK_KP_4: key_id = (!allowingStringInput ? gvNumberPadKey4 : gvNumberKey4); break;
					case SDLK_KP_5: key_id = (!allowingStringInput ? gvNumberPadKey5 : gvNumberKey5); break;
					case SDLK_KP_6: key_id = (!allowingStringInput ? gvNumberPadKey6 : gvNumberKey6); break;
					case SDLK_KP_7: key_id = (!allowingStringInput ? gvNumberPadKey7 : gvNumberKey7); break;
					case SDLK_KP_8: key_id = (!allowingStringInput ? gvNumberPadKey8 : gvNumberKey8); break;
					case SDLK_KP_9: key_id = (!allowingStringInput ? gvNumberPadKey9 : gvNumberKey9); break;
					case SDLK_KP_PERIOD: key_id = (!allowingStringInput ? gvNumberPadKeyPeriod : 46); break;
					case SDLK_KP_DIVIDE: key_id = (!allowingStringInput ? gvNumberPadKeyDivide : 47); break;
					case SDLK_KP_MULTIPLY: key_id = (!allowingStringInput ? gvNumberPadKeyMultiply : 42); break;
					case SDLK_KP_MINUS: key_id = (!allowingStringInput ? gvNumberPadKeyMinus : 45); break;
					case SDLK_KP_PLUS: key_id = (!allowingStringInput ? gvNumberPadKeyPlus : 43); break;
					case SDLK_KP_EQUALS: key_id = (!allowingStringInput ? gvNumberPadKeyEquals : 61); break;
					case SDLK_KP_ENTER: key_id = gvNumberPadKeyEnter; break;
					case SDLK_HOME: key_id = gvHomeKey; break;
					case SDLK_END: key_id = gvEndKey; break;
					case SDLK_INSERT: key_id = gvInsertKey; break;
					case SDLK_PAGEUP: key_id = gvPageUpKey; break;
					case SDLK_PAGEDOWN: key_id = gvPageDownKey; break;
					case SDLK_SPACE: key_id = 32; break;
					case SDLK_RETURN: key_id = 13; break;
					case SDLK_TAB: key_id = 9; break;
					case SDLK_ESCAPE: key_id = 27; break;
					case SDLK_UP: key_id = gvArrowKeyUp; break;
					case SDLK_DOWN: key_id = gvArrowKeyDown; break;
					case SDLK_LEFT: key_id = gvArrowKeyLeft; break;
					case SDLK_RIGHT: key_id = gvArrowKeyRight; break;
					case SDLK_PAUSE: key_id = gvPauseKey; break;
					case SDLK_F1: key_id = gvFunctionKey1; break;
					case SDLK_F2: key_id = gvFunctionKey2; break;
					case SDLK_F3: key_id = gvFunctionKey3; break;
					case SDLK_F4: key_id = gvFunctionKey4; break;
					case SDLK_F5: key_id = gvFunctionKey5; break;
					case SDLK_F6: key_id = gvFunctionKey6; break;
					case SDLK_F7: key_id = gvFunctionKey7; break;
					case SDLK_F8: key_id = gvFunctionKey8; break;
					case SDLK_F9: key_id = gvFunctionKey9; break;
					case SDLK_F10: key_id = gvFunctionKey10; break;
					case SDLK_F11: key_id = gvFunctionKey11; break;
					case SDLK_F12: key_id = 327; break;
					case SDLK_BACKSPACE: key_id = gvBackspaceKey; break;
					case SDLK_DELETE: key_id = gvDeleteKey; break;

					default:
						//OO_LOG("keys.test", "Unhandled Keyup scancode with unicode = 0: {}", static_cast<int>(kbd_event->keysym.scancode));
						;
				}

				if (key_id > 0 && key_id < numKeys()) 
				{
					keys[key_id] = NO;
				}
				else 
				{
					//OO_LOG("keys.test", "Unhandled Keyup scancode: {}", static_cast<int>(kbd_event->keysym.scancode));
				}
				break;

			case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
			{
                resize_pending = true;
				break;
			}

#if OOLITE_WINDOWS
			case SDL_EVENT_WINDOW_MOVED:
			{
				if(grabMouseStatus)  grabMouseInsideGameWindow(YES);
				break;
			}

			case SDL_EVENT_WINDOW_FOCUS_GAINED:
			{
				if (gameController != nullptr)  gameController->setEcoQoS((gameController != nullptr ? gameController->isGamePaused() : false));
				break;
			}

			case SDL_EVENT_WINDOW_FOCUS_LOST:
			{
				if (gameController != nullptr)  gameController->setEcoQoS(YES);
				break;
			}
#endif

			// caused by INTR or someone hitting close
			case SDL_EVENT_QUIT:
			{
				SDL_DestroyWindow(window);
				if (gameController != nullptr)  gameController->exitAppWithContext("SDL_QUIT event received");
			}
		}
	}
	// check if enough time has passed since last use of the mousewheel and act
	// if needed
	if (timeNow >= timeSinceLastMouseWheel + OOMOUSEWHEEL_EVENTS_DELAY_INTERVAL)
	{
		_mouseWheelDelta = 0.0f;
	}
	if (resize_pending)
	{
		int pixelWidth, pixelHeight;
		// Fetch actual pixel bounds back from SDL
		SDL_GetWindowSizeInPixels(window, &pixelWidth, &pixelHeight);

		updateGLSize(NSMakeSize(pixelWidth, pixelHeight));

		if (!fullScreen)
		{
			saveWindowSize(viewSize);  // Save the updated window size
		}
		resize_pending = false;
	}
}
// DJS: String input handler. Since for SDL versions we're also handling
// freeform typing this has necessarily got more complex than the non-SDL
// versions.
void MyOpenGLView::handleStringInput(SDL_KeyboardEvent *kbd_event, Uint16 key_id)
{
	SDL_Keycode key=kbd_event->key;

	// Del, Backspace
	// lengths in UTF-16 units, as the old mutable-string buffer counted them
	const std::size_t typedLength = oo::utf8ToUtf16(typedString).size();
	if((key == SDLK_BACKSPACE || key == SDLK_DELETE) && typedLength > 0)
	{
		// delete
		oo::str::deleteUnitAt(typedString, typedLength - 1);
	}

	isAlphabetKeyDown=NO;

	// TODO: a more flexible mechanism  for max. string length ?
	if(oo::utf8ToUtf16(typedString).size() < 40)
	{
		lastKeyShifted = shift;
		if (allowingStringInput == gvStringInputAlpha)
		{
			// inputAlpha - limited input for planet find screen
			if(key >= SDLK_A && key <= SDLK_Z)
			{
				isAlphabetKeyDown=YES;
				typedString += FormattedCharacter(key);
				// if in inputAlpha, keep in lower case.
			}
		}
		else
		{
			//Uint16 unicode = kbd_event->keysym.unicode;
			// printable range
			if (key_id >= 32 && key_id <= 255) // 126
			{
				if ((char)key_id != '/' || allowingStringInput == gvStringInputAll)
				{
					isAlphabetKeyDown=YES;
					typedString += FormattedCharacter(key_id);
				}
			}
		}
	}
}
void MyOpenGLView::setMouseInDeltaMode(bool inDelta)
{
	mouseInDeltaMode=inDelta;
}
