/*

MyOpenGLView+Input.m

Oolite

*/

#include <SDL3/SDL_init.h>
#import "MyOpenGLView.h"

#import "GameController.h"
#import "Universe.h"
#import "OOSDLJoystickManager.h"
#import "PlayerEntity.h"
#import "ResourceManager.h"
#import "NSFileManagerOOExtensions.h" // to find savedir

#define kOOLogUnconvertedNSLog @"unclassified.MyOpenGLView"

static NSString * kOOLogKeyUp				= @"input.keyMapping.keyPress.keyUp";
static NSString * kOOLogKeyDown			= @"input.keyMapping.keyPress.keyDown";

@interface MyOpenGLView (InputPrivate)

@end

@implementation MyOpenGLView (Input)

- (void) initKeyMappingData
{
	NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
	// load in our keyboard scancode mappings
#if OOLITE_WINDOWS	
	NSDictionary *kmap = [NSDictionary dictionaryWithDictionary:[ResourceManager dictionaryFromFilesNamed:@"keymappings_windows.plist" inFolder:@"Config" mergeMode:MERGE_BASIC cache:NO]];
#else
	NSDictionary *kmap = [NSDictionary dictionaryWithDictionary:[ResourceManager dictionaryFromFilesNamed:@"keymappings_linux.plist" inFolder:@"Config" mergeMode:MERGE_BASIC cache:NO]];
#endif
	// get the stored keyboard code from preferences
	NSString *kbd = [prefs oo_stringForKey:@"keyboard-code" defaultValue:@"default"];
	NSDictionary *subset = [kmap objectForKey:kbd];

	[keyMappings_normal release];
	keyMappings_normal = [[subset objectForKey:@"mapping_normal"] copy];
	[keyMappings_shifted release];
	keyMappings_shifted = [[subset objectForKey:@"mapping_shifted"] copy];
}
- (void) autoShowMouse
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
- (void) setStringInput: (enum StringInput) value
{
	allowingStringInput = value;
}
- (void) allowStringInput: (BOOL) value
{
	if (value)
		allowingStringInput = gvStringInputAlpha;
	else
		allowingStringInput = gvStringInputNo;
}
-(enum StringInput) allowingStringInput
{
	return allowingStringInput;
}
- (NSString *) typedString
{
	return typedString;
}
- (void) resetTypedString
{
	[typedString setString:@""];
}
- (void) setTypedString:(NSString*) value
{
	[typedString setString:value];
}
- (void) noteMouseInteractionModeChangedFrom:(OOMouseInteractionMode)oldMode to:(OOMouseInteractionMode)newMode
{
	[self autoShowMouse];
	[self setMouseInDeltaMode:OOMouseInteractionModeIsFlightMode(newMode)];
}
- (void) setVirtualJoystick:(double) vmx :(double) vmy
{
	virtualJoystickPosition.x = vmx;
	virtualJoystickPosition.y = vmy;
}
- (NSPoint) virtualJoystickPosition
{
	return virtualJoystickPosition;
}


/////////////////////////////////////////////////////////////
- (void) clearKeys
{
	int i;
	lastKeyShifted = NO;
	for (i = 0; i < [self numKeys]; i++)
		keys[i] = NO;
}
- (void) clearMouse
{
	keys[gvMouseDoubleClick] = NO;
	keys[gvMouseLeftButton] = NO;
	doubleClick = NO;
}
- (void) clearKey: (int)theKey
{
	if (theKey >= 0 && theKey < [self numKeys])
	{
		keys[theKey] = NO;
	}
}
- (void) resetMouse
{
	[self setVirtualJoystick:0.0 :0.0];
	if ([[PlayerEntity sharedPlayer] isMouseControlOn])
	{
		SDL_WarpMouseInWindow(window, viewSize.width / 2, viewSize.height / 2);
		mouseWarped = YES;
	}
}
- (BOOL) isAlphabetKeyDown
{
	return isAlphabetKeyDown = NO;;
}

// DJS: When entering submenus in the gui, it is not helpful if the
// key down that brought you into the submenu is still registered
// as down when we're in. This makes isDown return NO until a key up
// event has been received from SDL.
- (void) suppressKeysUntilKeyUp
{
	if (keys[gvMouseDoubleClick] == NO)
   	{
   		suppressKeys = YES;
   		[self clearKeys];
   	}
   	else
   	{
   		[self clearMouse];
   	}

}
- (BOOL) isDown: (int) key
{
	if ( suppressKeys )
		return NO;
	if ( key < 0 )
		return NO;
	if ( key >= [self numKeys] )
		return NO;
	return keys[key];
}
- (BOOL) isOptDown
{
	return opt;
}
- (BOOL) isCtrlDown
{
	return ctrl;
}
- (BOOL) isCommandDown
{
	return command;
}
- (BOOL) isShiftDown
{
	return shift;
}
- (BOOL) isCapsLockOn
{
	/* Caps Lock state check - This effectively gives us
	   an alternate keyboard state to play with and, in
	   the future, we could assign different behaviours
	   to existing controls, depending on the state of
	   Caps Lock. - Nikos 20160304
	*/
	return (SDL_GetModState() & SDL_KMOD_CAPS) == SDL_KMOD_CAPS;
}
- (BOOL) lastKeyWasShifted
{
	return lastKeyShifted;
}
- (int) numKeys
{
	return NUM_KEYS;
}
- (int) mouseWheelState
{
	if (_mouseWheelDelta > 0.0f)
		return gvMouseWheelUp;
	else if (_mouseWheelDelta < 0.0f)
		return gvMouseWheelDown;
	else
		return gvMouseWheelNeutral;
}
- (float) mouseWheelDelta
{
	return _mouseWheelDelta / OOMOUSEWHEEL_DELTA;
}
- (void) setMouseWheelDelta: (float) newWheelDelta
{
	_mouseWheelDelta = newWheelDelta * OOMOUSEWHEEL_DELTA;
}
- (BOOL) isCommandQDown
{
	return NO;
}
- (BOOL) isCommandFDown
{
	return NO;
}
- (void) clearCommandF
{
	// SDL stub for the mac function.
}
- (void)pollControls
{
	SDL_Event				event;
	SDL_KeyboardEvent		*kbd_event;
	SDL_MouseButtonEvent	*mbtn_event;
	SDL_MouseMotionEvent	*mmove_event;
	SDL_MouseWheelEvent	*mw_event;
 	float						mxdelta, mydelta;
	float					mouseVirtualStickSensitivityX = viewSize.width * _mouseVirtualStickSensitivityFactor;
	float					mouseVirtualStickSensitivityY = viewSize.height * _mouseVirtualStickSensitivityFactor;
	NSTimeInterval			timeNow = [NSDate timeIntervalSinceReferenceDate];
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
				[(OOSDLJoystickManager*)[OOJoystickManager sharedStickHandler] handleSDLEvent: &event];
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
						[self resetMouse]; // Will set mouseWarped to YES
						break;
					// mousewheel stuff

				}
				break;

			case SDL_EVENT_MOUSE_BUTTON_UP:
				mbtn_event = (SDL_MouseButtonEvent*)&event;
				NSTimeInterval timeBetweenClicks = timeNow - timeIntervalAtLastClick;
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
				NSTimeInterval timeBetweenMouseWheels = timeNow - timeSinceLastMouseWheel;
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

						[self setVirtualJoystick:mx :my];
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
				BOOL modifier_pressed = NO;
				BOOL special_key = NO;

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
						[self toggleScreenMode];
						special_key = YES; 
						break;

					case SDLK_ESCAPE:
						if (shift)
						{
							SDL_DestroyWindow(window);
							[gameController exitAppWithContext:@"Shift-escape pressed"];
						}
						else
						{
							key_id = 27;
							special_key = YES;
						}
						break;
					default:
						//OOLog(@"keys.test", @"Unhandled Keydown scancode with unicode = 0: %d", scan_code);
						;
				}

				// the keyup event doesn't give us the unicode value, so store it here so it can be retrieved on keyup
				// the ctrl key tends to mix up the unicode values, so deal with some special cases
				// we also need (in most cases) to get the character without the impact of caps lock. 

				if (((!special_key && (ctrl || key_id == 0)) || ([self isCapsLockOn] && (!special_key && !allowingStringInput))) && !modifier_pressed) //  
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
					[self handleStringInput:kbd_event keyID:key_id];
				}

				OOLog(kOOLogKeyDown, @"Keydown scancode = %d, unicode = %i", scan_code, key_id);

				if (key_id > 0 && key_id <= [self numKeys]) 
				{
					keys[key_id] = YES;
				}
				else 
				{
					OOLog(@"keys.test", @"Unhandled Keydown scancode/unicode: %d %i", scan_code, key_id);
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
				OOLog(kOOLogKeyUp, @"Keyup scancode = %d, unicode = %i, character = %c, shift = %d, ctrl = %d, alt = %d", scan_code, key_id, key_id, shift, ctrl, opt);
				//OOLog(kOOLogKeyUp, @"Keyup scancode = %d, shift = %d, ctrl = %d, alt = %d", scan_code, shift, ctrl, opt);
				
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
						//OOLog(@"keys.test", @"Unhandled Keyup scancode with unicode = 0: %d", kbd_event->keysym.scancode);
						;
				}

				if (key_id > 0 && key_id <= [self numKeys]) 
				{
					keys[key_id] = NO;
				}
				else 
				{
					//OOLog(@"keys.test", @"Unhandled Keyup scancode: %d", kbd_event->keysym.scancode);
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
				if(grabMouseStatus)  [self grabMouseInsideGameWindow:YES];
				break;
			}

			case SDL_EVENT_WINDOW_FOCUS_GAINED:
			{
				[gameController setEcoQoS:[gameController isGamePaused]];
				break;
			}

			case SDL_EVENT_WINDOW_FOCUS_LOST:
			{
				[gameController setEcoQoS:YES];
				break;
			}
#endif

			// caused by INTR or someone hitting close
			case SDL_EVENT_QUIT:
			{
				SDL_DestroyWindow(window);
				[gameController exitAppWithContext:@"SDL_QUIT event received"];
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

		[self updateGLSize:NSMakeSize(pixelWidth, pixelHeight)];

		if (!fullScreen)
		{
			[self saveWindowSize: viewSize];  // Save the updated window size
		}
		resize_pending = false;
	}
}
// DJS: String input handler. Since for SDL versions we're also handling
// freeform typing this has necessarily got more complex than the non-SDL
// versions.
- (void) handleStringInput: (SDL_KeyboardEvent *) kbd_event keyID:(Uint16)key_id;
{
	SDL_Keycode key=kbd_event->key;

	// Del, Backspace
	if((key == SDLK_BACKSPACE || key == SDLK_DELETE) && [typedString length] > 0)
	{
		// delete
		[typedString deleteCharactersInRange:NSMakeRange([typedString length]-1, 1)];
	}

	isAlphabetKeyDown=NO;

	// TODO: a more flexible mechanism  for max. string length ?
	if([typedString length] < 40)
	{
		lastKeyShifted = shift;
		if (allowingStringInput == gvStringInputAlpha)
		{
			// inputAlpha - limited input for planet find screen
			if(key >= SDLK_A && key <= SDLK_Z)
			{
				isAlphabetKeyDown=YES;
				[typedString appendFormat:@"%c", key];
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
					[typedString appendFormat:@"%c", key_id];
				}
			}
		}
	}
}
- (void) setMouseInDeltaMode: (BOOL) inDelta
{
	mouseInDeltaMode=inDelta;
}
@end
