/*

OOMacJoystickManager.m
By Alex Smith and Jens Ayton

Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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

#import "OOMacJoystickManager.h"
#import "OOLogging.h"
#import "OOCollectionExtractors.h"


@interface OOMacJoystickManager ()

- (void) handleInputEvent:(IOHIDValueRef)value;
- (void) handleJoystickAttach:(IOHIDDeviceRef)device;
- (void) handleDeviceRemoval:(IOHIDDeviceRef)device;

@end


static void HandleDeviceMatchingCallback(void * inContext, IOReturn inResult, void* inSender, IOHIDDeviceRef  inIOHIDDeviceRef);
static void HandleInputValueCallback(void * inContext, IOReturn inResult, void* inSender, IOHIDValueRef  inIOHIDValueRef);
static void HandleDeviceRemovalCallback(void * inContext, IOReturn inResult, void* inSender, IOHIDDeviceRef  inIOHIDDeviceRef);


@implementation OOMacJoystickManager

- (id) init
{
	if ((self = [super init]))
	{
		// Initialise gamma table
		int i;
		for (i = 0; i< kJoystickGammaTableSize; i++)
		{
			double x = ((double) i - 128.0) / 128.0;
			double sign = x>=0 ? 1.0 : -1.0;
			double y = sign * floor(32767.0 * pow (fabs(x), STICK_GAMMA)); 
			gammaTable[i] = (int) y;
		}
		
		hidManager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
		IOHIDManagerSetDeviceMatching(hidManager, NULL);
		
		IOHIDManagerRegisterDeviceMatchingCallback(hidManager, HandleDeviceMatchingCallback, self);
		IOHIDManagerRegisterDeviceRemovalCallback(hidManager, HandleDeviceRemovalCallback, self);
		
		IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
		IOReturn iores = IOHIDManagerOpen( hidManager, kIOHIDOptionsTypeNone );
		if (iores != kIOReturnSuccess)
		{
			OOLog(@"joystick.error.init", @"Cannot open HID manager; joystick support will not function.");
		}
		
		devices = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
	}
	return self;
}


- (void) dealloc
{
	if (hidManager != NULL)  CFRelease(hidManager);
	if (devices != NULL)  CFRelease(devices);
	
	[super dealloc];
}


- (OOUInteger) joystickCount
{
	return CFArrayGetCount(devices);
}


- (void) handleDeviceAttach:(IOHIDDeviceRef)device
{
	NSArray *usagePairs = (NSArray *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDDeviceUsagePairsKey));
	
	for (NSDictionary *pair in usagePairs)
	{
		if ([pair oo_unsignedIntForKey:@kIOHIDDeviceUsagePageKey] == kHIDPage_GenericDesktop)
		{
			unsigned usage = [pair oo_unsignedIntForKey:@kIOHIDDeviceUsageKey];
			if (usage == kHIDUsage_GD_Joystick || usage == kHIDUsage_GD_GamePad)
			{
				[self handleJoystickAttach:device];
				return;
			}
		}
	}
	
	if (OOLogWillDisplayMessagesInClass(@"joystick.reject"))
	{
		NSString *product = (NSString *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
		unsigned usagePage = [(NSNumber *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDPrimaryUsagePageKey)) unsignedIntValue];
		unsigned usage = [(NSNumber *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDPrimaryUsageKey)) unsignedIntValue];
		OOLog(@"joystick.reject", @"Ignoring HID device: %@ (primary usage %u:%u)", product, usagePage, usage);
	}
}


- (void) handleJoystickAttach:(IOHIDDeviceRef)device
{
	OOLog(@"joystick.connect", @"Joystick connected: %@", IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey)));
	
	CFArrayAppendValue(devices, device);
	IOHIDDeviceRegisterInputValueCallback(device, HandleInputValueCallback, self);
	
	if (OOLogWillDisplayMessagesInClass(@"joystick.connect.element"))
	{
		// Print out elements of new device
		CFArrayRef elementList = IOHIDDeviceCopyMatchingElements(device, NULL, 0L);
		if (elementList != NULL)
		{
			OOLogIndent();
			
			CFIndex idx, count = CFArrayGetCount(elementList);
			
			for (idx = 0; idx < count; idx++)
			{
				IOHIDElementRef element = (IOHIDElementRef)CFArrayGetValueAtIndex(elementList, idx);
				IOHIDElementType elementType = IOHIDElementGetType(element);
				if (elementType > kIOHIDElementTypeInput_ScanCodes)
				{
					continue;
				}
				IOHIDElementCookie elementCookie = IOHIDElementGetCookie(element);
				uint32_t usagePage = IOHIDElementGetUsagePage(element);
				uint32_t usage = IOHIDElementGetUsage(element);
				uint32_t min = (uint32_t)IOHIDElementGetPhysicalMin(element);
				uint32_t max = (uint32_t)IOHIDElementGetPhysicalMax(element);
				NSString *name = (NSString *)IOHIDElementGetProperty(element, CFSTR(kIOHIDElementNameKey)) ?: @"unnamed";
				OOLog(@"joystick.connect.element", @"%@ - usage %d:%d, cookie %d, range %d-%d", name, usagePage, usage, (int) elementCookie, min, max);
			}
			
			OOLogOutdent();
			CFRelease(elementList);
		}
	}
}


- (void) handleDeviceRemoval:(IOHIDDeviceRef)device
{
	OOLog(@"joystick.remove", @"Joystick removed: %@", IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey)));
	
	CFIndex index = CFArrayGetFirstIndexOfValue(devices, CFRangeMake(0, CFArrayGetCount(devices)), device);
	if (index != kCFNotFound)  CFArrayRemoveValueAtIndex(devices, index);
}


static int AxisIndex(uint32_t page, uint32_t usage)
{
	/*
		Map axis-like HID usages to SDL-like axis indices. These are all the
		commonly used joystick axes according to Microsoft's DirectInput
		documentation (hey, you've got to get your info somewhere).
		
		GD_Slider, GD_Dial, DG_Wheel and Sim_Throttle are actually distinct;
		unlike the others, they're uncentered. (By implication,
		IOHIDElementHasPreferredState() should be false.) This should, in
		particular, be considered when mapping to the throttle: centered axes
		should provide relative input (for gamepads), while uncentered ones
		should provide absolute input. Since that festering pool of pus, SDL,
		can't make this distinction, OOJoystickManager can't either (yet).
		-- Ahruman 2011-01-04
	*/
	
	switch (page)
	{
		case kHIDPage_GenericDesktop:
			switch (usage)
			{
				case kHIDUsage_GD_X: return 0;
				case kHIDUsage_GD_Y: return 1;
				case kHIDUsage_GD_Z: return 2;
				case kHIDUsage_GD_Rx: return 3;
				case kHIDUsage_GD_Ry: return 4;
				case kHIDUsage_GD_Rz: return 5;
				case kHIDUsage_GD_Slider: return 6;
				case kHIDUsage_GD_Dial: return 7;
				case kHIDUsage_GD_Wheel: return 8;
			}
			break;
		
		case kHIDPage_Simulation:
			switch (usage)
		{
			case kHIDUsage_Sim_Throttle:
				return 9;
		}
	}
	
	// Negative numbers indicate non-axis.
	return -1;
}


static uint8_t MapHatValue(CFIndex value, CFIndex max)
{
	/*
		A hat switch has four or eight values, indicating directions. 0
		is straight up/forwards, and subsequent values increase clockwise.
		Out-of-range values are nulls, indicating no direction is pressed.
	*/
	
	if (0 <= value && value <= max)
	{
		if (max == 3)
		{
			const uint8_t valueMap4[4] = { JOYHAT_UP, JOYHAT_RIGHT, JOYHAT_DOWN, JOYHAT_LEFT };
			return valueMap4[value];
		}
		else if (max == 7)
		{
			const uint8_t valueMap8[8] = { JOYHAT_UP, JOYHAT_RIGHTUP, JOYHAT_RIGHT, JOYHAT_RIGHTDOWN, JOYHAT_DOWN, JOYHAT_LEFTDOWN, JOYHAT_LEFT, JOYHAT_LEFTUP };
			return valueMap8[value];
		}
	}
	return JOYHAT_CENTERED;
}


- (void) handleInputEvent:(IOHIDValueRef)value
{
	IOHIDElementRef	element = IOHIDValueGetElement(value);
	uint32_t usagePage = IOHIDElementGetUsagePage(element);
	uint32_t usage = IOHIDElementGetUsage(element);
	int buttonNum = 0;
	int axisNum = 0;
	
	axisNum = AxisIndex(usagePage, usage);
	if (axisNum >= 0)
	{
		JoyAxisEvent evt;
		evt.type = JOYAXISMOTION;
		evt.which = 0;
		evt.axis = axisNum;
		
		CFIndex intValue = IOHIDValueGetIntegerValue(value);
		CFIndex min = IOHIDElementGetLogicalMin(element);
		CFIndex max = IOHIDElementGetLogicalMax(element);
		float axisValue = (float)(intValue - min) / (float)(max + 1 - min);
		
		// Note: this is designed so gammaIndex == intValue if min == 0 and max == kJoystickGammaTableSize - 1 (the common case).
		unsigned gammaIndex = floor(axisValue * kJoystickGammaTableSize);
		
		/*
			CRASH: r4435, Mac OS X 10.6.6, x86_64 -[OOMacJoystickManager handleInputEvent:] + 260
			http://aegidian.org/bb/viewtopic.php?f=3&t=9382
			The instruction is:
				movl (%r15,%rbx,4), %r12d
			which corresponds to the load gammaTable[gammaIndex].
			Check added to find out-of-range values.
			-- Ahruman 2011-03-07
		*/
		if (EXPECT_NOT(gammaIndex > kJoystickGammaTableSize))
		{
			OOLogERR(@"joystick.gamma.overflow", @"Joystick gamma table overflow - gammaIndex is %u of %u. Raw value: %i in [%i..%i]; axisValue: %g; unrounded gammaIndex: %g. Ignoring event. This is an internal error, please report it.",
					 gammaIndex, kJoystickGammaTableSize,
					 (int)intValue, (int)min, (int)max,
					 axisValue,
					 axisValue * kJoystickGammaTableSize
			);
			
			return;
		}
		// End bug check
		
		evt.value = gammaTable[gammaIndex];
		[self decodeAxisEvent:&evt];
	}
	else if (usagePage == kHIDPage_GenericDesktop && usage == kHIDUsage_GD_Hatswitch)
	{
		CFIndex max = IOHIDElementGetLogicalMax(element);
		CFIndex min = IOHIDElementGetLogicalMin(element);
		
		JoyHatEvent evt =
		{
			.type = JOYHAT_MOTION,
			.which = 0,
			.hat = 0,	// The abuse of usage values for identifying elements means we can't distinguish between hats.
			.value = MapHatValue(IOHIDValueGetIntegerValue(value) - min, max - min)
		};
		
		[self decodeHatEvent:&evt];
	}
	else if (usagePage == kHIDPage_Button)
	{
		// Button Event
		buttonNum = usage;
		JoyButtonEvent evt;
		BOOL buttonState = (IOHIDValueGetIntegerValue(value) != 0);
		evt.type = buttonState ? JOYBUTTONDOWN : JOYBUTTONUP;
		evt.which = 0;
		evt.button = buttonNum;
		evt.state = buttonState ? 1 : 0;	
		[self decodeButtonEvent:&evt];
	}
}


- (NSString *) nameOfJoystick:(int)stickNumber
{
	IOHIDDeviceRef device = (IOHIDDeviceRef)CFArrayGetValueAtIndex(devices, stickNumber);
	return (NSString *)IOHIDDeviceGetProperty(device, CFSTR(kIOHIDProductKey));
}



- (int16_t) getAxisWithStick:(int) stickNum axis:(int) axisNum 
{
	return 0;
}



@end


//Thunking to Objective-C
static void HandleDeviceMatchingCallback(void * inContext, IOReturn inResult, void* inSender, IOHIDDeviceRef  inIOHIDDeviceRef)
{
	[(OOMacJoystickManager *)inContext handleDeviceAttach:inIOHIDDeviceRef];
}



static void HandleInputValueCallback(void * inContext, IOReturn inResult, void* inSender, IOHIDValueRef  inIOHIDValueRef)
{
	[(OOMacJoystickManager *)inContext handleInputEvent:inIOHIDValueRef];
}



static void HandleDeviceRemovalCallback(void * inContext, IOReturn inResult, void* inSender, IOHIDDeviceRef  inIOHIDDeviceRef)
{
	[(OOMacJoystickManager *)inContext handleDeviceRemoval:inIOHIDDeviceRef];
}
