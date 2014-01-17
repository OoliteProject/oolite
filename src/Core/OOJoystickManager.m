/*

OOJoystickManager.m
By Dylan Smith
modified by Alex Smith

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

#import "OOJoystickManager.h"
#import "OOLogging.h"
#import "OOCollectionExtractors.h"


#define kOOLogUnconvertedNSLog @"unclassified.JoystickHandler"


static Class sStickHandlerClass = Nil;
static id sSharedStickHandler = nil;


@interface OOJoystickManager (Private)

// Setting button and axis functions
- (void) setFunctionForAxis:(int)axis
                   function:(int)function
                      stick:(int)stickNum;

- (void) setFunctionForButton:(int)button
                     function:(int)function
                        stick:(int)stickNum;

@end



@implementation OOJoystickManager

+ (id) sharedStickHandler
{
	if (sSharedStickHandler == nil)
	{
		if (sStickHandlerClass == Nil)  sStickHandlerClass = [OOJoystickManager class];
		sSharedStickHandler = [[sStickHandlerClass alloc] init];
	}
	return sSharedStickHandler;
}


+ (BOOL) setStickHandlerClass:(Class)aClass
{
	NSAssert(sStickHandlerClass == nil, @"Can't set joystick handler class after joystick handler is initialized.");
	NSParameterAssert(aClass == Nil || [aClass isSubclassOfClass:[OOJoystickManager class]]);
	
	sStickHandlerClass = aClass;
	return YES;
}


- (id) init
{
	if ((self = [super init]))
	{
		// set initial values for stick buttons/axes (NO for buttons,
		// STICK_AXISUNASSIGNED for axes). Caution: calling this again
		// after axes have been assigned will set all the axes to
		// STICK_AXISUNASSIGNED so if there is a need to do something
		// like this, then do it some other way, or change this method
		// so it doesn't do that.
		[self clearStickStates];
		
		// Make some sensible mappings. This also ensures unassigned
		// axes and buttons are set to unassigned (STICK_NOFUNCTION).
		[self loadStickSettings];
		
		precisionMode = NO;
		invertPitch = NO;
	}
	return self;
}



- (NSPoint) rollPitchAxis
{
	return NSMakePoint(axstate[AXIS_ROLL], axstate[AXIS_PITCH]);
}


- (NSPoint) viewAxis
{
	return NSMakePoint(axstate[AXIS_VIEWX], axstate[AXIS_VIEWY]);
}


- (BOOL) getButtonState: (int)function
{
	return butstate[function];
}


- (const BOOL *)getAllButtonStates
{
	return butstate;
}


- (double) getAxisState: (int)function
{
	return axstate[function];
}


- (double) getSensitivity
{
	return precisionMode ? STICK_PRECISIONFAC : 1.0;
}

- (NSArray *)listSticks
{
	NSUInteger i, stickCount = [self joystickCount];
	
	NSMutableArray *stickList = [NSMutableArray array];
	for (i = 0; i < stickCount; i++)
	{
		[stickList addObject:[self nameOfJoystick:i]];
	}
	return stickList;
}


- (NSDictionary *) axisFunctions
{
	int i,j;
	NSMutableDictionary *fnList = [NSMutableDictionary dictionary];
	
	// Add axes
	for (i = 0; i < MAX_AXES; i++)
	{
		for (j = 0; j < MAX_STICKS; j++)
		{
			if(axismap[j][i] >= 0)
			{
				NSDictionary *fnDict=[NSDictionary dictionaryWithObjectsAndKeys:
									  [NSNumber numberWithBool:YES], STICK_ISAXIS,
									  [NSNumber numberWithInt:j], STICK_NUMBER, 
									  [NSNumber numberWithInt:i], STICK_AXBUT,
									  nil];
				[fnList setValue: fnDict
						  forKey: ENUMKEY(axismap[j][i])];
			}
		}
	}
	return fnList;
}


- (NSDictionary *)buttonFunctions
{
	int i, j;
	NSMutableDictionary *fnList = [NSMutableDictionary dictionary];
	
	// Add buttons
	for (i = 0; i < MAX_BUTTONS; i++)
	{
		for (j = 0; j < MAX_STICKS; j++)
		{
			if(buttonmap[j][i] >= 0)
			{
				NSDictionary *fnDict = [NSDictionary dictionaryWithObjectsAndKeys:
										[NSNumber numberWithBool:NO], STICK_ISAXIS, 
										[NSNumber numberWithInt:j], STICK_NUMBER, 
										[NSNumber numberWithInt:i], STICK_AXBUT, 
										nil];
				[fnList setValue:fnDict
						  forKey:ENUMKEY(buttonmap[j][i])];
			}
		}
	}
	return fnList;
}


- (void) setFunction:(int)function withDict:(NSDictionary *)stickFn
{
	BOOL isAxis = [stickFn oo_boolForKey:STICK_ISAXIS];
	int stickNum = [stickFn oo_intForKey:STICK_NUMBER];
	int stickAxBt = [stickFn oo_intForKey:STICK_AXBUT];
	
	if (isAxis)
	{
		[self setFunctionForAxis:stickAxBt 
						function:function
						   stick:stickNum];
	}
	else
	{
		[self setFunctionForButton:stickAxBt
						  function:function
							 stick:stickNum];
	}
}


- (void) setFunctionForAxis:(int)axis 
                   function:(int)function
                      stick:(int)stickNum
{
	NSParameterAssert(axis < MAX_AXES && stickNum < MAX_STICKS);
	
	int16_t axisvalue = [self getAxisWithStick:stickNum axis:axis];
	[self unsetAxisFunction:function];
	axismap[stickNum][axis] = function;
	
	// initialize the throttle to what it's set to now (or else the
	// commander has to waggle the throttle to wake it up). Other axes
	// set as default.
	if(function == AXIS_THRUST)
	{
		axstate[function] = (float)(65536 - (axisvalue + 32768)) / 65536;
	}
	else
	{
		axstate[function] = (float)axisvalue / STICK_NORMALDIV;
	}
}


- (void) setFunctionForButton:(int)button 
                     function:(int)function 
                        stick:(int)stickNum
{
	NSParameterAssert(button < MAX_BUTTONS && stickNum < MAX_STICKS);
	
	int i, j;
	for (i = 0; i < MAX_BUTTONS; i++)
	{
		for (j = 0; j < MAX_STICKS; j++)
		{
			if (buttonmap[j][i] == function)
			{
				buttonmap[j][i] = STICK_NOFUNCTION;
				break;
			}
		}
	}
	buttonmap[stickNum][button] = function;
}


- (void) unsetAxisFunction:(int)function
{
	int i, j;
	for (i = 0; i < MAX_AXES; i++)
	{
		for (j = 0; j < MAX_STICKS; j++)
		{
			if (axismap[j][i] == function)
			{
				axismap[j][i] = STICK_NOFUNCTION;
				axstate[function] = STICK_AXISUNASSIGNED;
				break;
			}
		}
	}
}


- (void) unsetButtonFunction:(int)function
{
	int i,j;
	for (i = 0; i < MAX_AXES; i++)
	{
		for (j = 0; j < MAX_STICKS; j++)
		{
			if(buttonmap[j][i] == function)
			{
				buttonmap[j][i] = STICK_NOFUNCTION;
				break;
			}
		}
	}
}


- (void) setDefaultMapping
{
	// assign the simplest mapping: stick 0 having
	// axis 0/1 being roll/pitch and button 0 being fire, 1 being missile
	// All joysticks should at least have two axes and two buttons.
	axismap[0][0] = AXIS_ROLL;
	axismap[0][1] = AXIS_PITCH;
	buttonmap[0][0] = BUTTON_FIRE;
	buttonmap[0][1] = BUTTON_LAUNCHMISSILE;
}


- (void) clearMappings
{
	memset(axismap, STICK_NOFUNCTION, sizeof axismap);
	memset(buttonmap, STICK_NOFUNCTION, sizeof buttonmap);
}


- (void) clearStickStates
{
   int i;
   for (i = 0; i < AXIS_end; i++)
   {
      axstate[i] = STICK_AXISUNASSIGNED;
   }
   for (i = 0; i < BUTTON_end; i++)
   {
      butstate[i] = 0;
   }
}


- (void) clearStickButtonState:(int)stickButton
{
	if (stickButton >= 0 && stickButton < BUTTON_end)
	{
		butstate[stickButton] = 0;
	}
}


- (void)setCallback:(SEL) selector
             object:(id) obj
           hardware:(char)hwflags
{
	cbObject = obj;
	cbSelector = selector;
	cbHardware = hwflags;
}


- (void)clearCallback
{
	cbObject = nil;
	cbHardware = 0;
}


- (void)decodeAxisEvent: (JoyAxisEvent *)evt
{
	// Which axis moved? Does the value need to be made to fit a
	// certain function? Convert axis value to a double.
	double axisvalue = (double)evt->value;
	
	// First check if there is a callback and...
	if(cbObject && (cbHardware & HW_AXIS)) 
	{
		// ...then check if axis moved more than AXCBTHRESH - (fix for BUG #17482)
		if(axisvalue > AXCBTHRESH) 
		{
			NSDictionary *fnDict = [NSDictionary dictionaryWithObjectsAndKeys:
									[NSNumber numberWithBool: YES], STICK_ISAXIS,
									[NSNumber numberWithInt: evt->which], STICK_NUMBER, 
									[NSNumber numberWithInt: evt->axis], STICK_AXBUT,
									nil];
			cbHardware = 0;
			[cbObject performSelector:cbSelector withObject:fnDict];
			cbObject = nil;
		}
		
		// we are done.
		return;
	}
	
	// SDL seems to have some bizarre (perhaps a bug) behaviour when
	// events get queued up because the game isn't ready to handle
	// them (perhaps it's loading a commander and initializing the
	// universe, and the main event loop is blocked).
	// What happens is SDL lies about the axis that was triggered. For
	// each queued event it adds 1 to the axis number!! This does
	// not seem to happen with buttons.
	int function;
	if (evt->axis < MAX_AXES)
	{
		function = axismap[evt->which][evt->axis];
	}
	else
	{
		OOLog(@"decodeAxisEvent", @"Stick axis out of range - axis was %d", evt->axis);
		return;
	}
	switch (function)
	{
		case STICK_NOFUNCTION:
			// do nothing
			break;
		case AXIS_THRUST:
			// Normalize the thrust setting.
			axstate[function] = (float)(65536 - (axisvalue + 32768)) / 65536;
			break;
		case AXIS_ROLL:
		case AXIS_PITCH:
		case AXIS_YAW:
			if (fabs(axisvalue) < STICK_DEADZONE)
			{
				axisvalue = 0.0;
			}
			else
			{
				axisvalue = axisvalue < 0 ? -(-axisvalue-STICK_DEADZONE)/(1.0-STICK_DEADZONE) : (axisvalue-STICK_DEADZONE)/(1.0-STICK_DEADZONE);
			}
			if(precisionMode)
			{
				axstate[function] = axisvalue / STICK_PRECISIONDIV;
			}
			else
			{
				axstate[function] = axisvalue / STICK_NORMALDIV;
			}
			break;
		case AXIS_VIEWX:
		case AXIS_VIEWY:
			axstate[function] = axisvalue / STICK_NORMALDIV;
		default:
			// set the state with no modification.
			axstate[function] = axisvalue / 32768;         
	}
	if ((function == AXIS_PITCH) && invertPitch) axstate[function] = -1.0*axstate[function];
}


- (void) decodeButtonEvent:(JoyButtonEvent *)evt
{
	BOOL bs = NO;
	
	// Is there a callback we need to make?
	if(cbObject && (cbHardware & HW_BUTTON))
	{
		NSDictionary *fnDict = [NSDictionary dictionaryWithObjectsAndKeys:
								[NSNumber numberWithBool: NO], STICK_ISAXIS,
								[NSNumber numberWithInt: evt->which], STICK_NUMBER, 
								[NSNumber numberWithInt: evt->button], STICK_AXBUT,
								nil];
		cbHardware = 0;
		[cbObject performSelector:cbSelector withObject:fnDict];
		cbObject = nil;
		
		// we are done.
		return;
	}
	
	// Defensive measure - see comments in the axis handler for why.
	int function;
	if (evt->button < MAX_BUTTONS)
	{
		function = buttonmap[evt->which][evt->button];
	}
	else
	{
		OOLog(@"decodeButtonEvent", @"Joystick button out of range: %d", evt->button);
		return;
	}
	if (evt->type == JOYBUTTONDOWN)
	{
		bs = YES;
		if(function == BUTTON_PRECISION)
		{
			precisionMode = !precisionMode;
			
			// adjust current states now
			if(precisionMode)
			{
				if (axstate[AXIS_PITCH] != STICK_AXISUNASSIGNED) axstate[AXIS_PITCH] /= STICK_PRECISIONFAC;
				if (axstate[AXIS_ROLL] != STICK_AXISUNASSIGNED) axstate[AXIS_ROLL] /= STICK_PRECISIONFAC;
				if (axstate[AXIS_YAW] != STICK_AXISUNASSIGNED) axstate[AXIS_YAW] /= STICK_PRECISIONFAC;
			}
			else
			{
				if (axstate[AXIS_PITCH] != STICK_AXISUNASSIGNED) axstate[AXIS_PITCH] *= STICK_PRECISIONFAC;
				if (axstate[AXIS_ROLL] != STICK_AXISUNASSIGNED) axstate[AXIS_ROLL] *= STICK_PRECISIONFAC;
				if (axstate[AXIS_YAW] != STICK_AXISUNASSIGNED) axstate[AXIS_YAW] *= STICK_PRECISIONFAC;
			}
		}
	}
	
	if (function >= 0)
	{
		butstate[function]=bs;
	}
	
}


- (void) decodeHatEvent:(JoyHatEvent *)evt                                     
{                                                                                  
	// HACK: handle this as a set of buttons                                        
	int i;                                                                          
	JoyButtonEvent btn;                                                         
	
	btn.which = evt->which;                                                         
	
	for (i = 0; i < 4; ++i)                                                         
	{                                                                               
		if ((evt->value ^ hatstate[evt->which][evt->hat]) & (1 << i))                
		{                                                                            
			btn.type = (evt->value & (1 << i)) ? JOYBUTTONDOWN : JOYBUTTONUP; 
			btn.button = MAX_REAL_BUTTONS + i + evt->which * 4;                       
			btn.state = (evt->value & (1 << i)) ? JOYBUTTON_PRESSED : JOYBUTTON_RELEASED;         
			[self decodeButtonEvent:&btn];                                            
		}                                                                            
	}                                                                               
	
	hatstate[evt->which][evt->hat] = evt->value;
}


- (NSUInteger) joystickCount
{
	return 0;
}


- (void) saveStickSettings
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:[self axisFunctions]
				 forKey:AXIS_SETTINGS];
	[defaults setObject:[self buttonFunctions]
				 forKey:BUTTON_SETTINGS];
	
	[defaults synchronize];
}


- (void) loadStickSettings
{
	unsigned i;
	[self clearMappings];                  
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSDictionary *axisSettings = [defaults objectForKey: AXIS_SETTINGS];
	NSDictionary *buttonSettings = [defaults objectForKey: BUTTON_SETTINGS];
	if(axisSettings)
	{
		NSArray *keys = [axisSettings allKeys];
		for (i = 0; i < [keys count]; i++)
		{
			NSString *key = [keys objectAtIndex: i];
			[self setFunction: [key intValue]
					 withDict: [axisSettings objectForKey: key]];
		}
	}
	if(buttonSettings)
	{
		NSArray *keys = [buttonSettings allKeys];
		for (i = 0; i < [keys count]; i++)
		{
			NSString *key = [keys objectAtIndex: i];
			[self setFunction:[key intValue]
					 withDict:[buttonSettings objectForKey: key]];
		}
	}
	else
	{
		// Nothing to load - set useful defaults
		[self setDefaultMapping];
	}
}

// These get overidden by subclasses

- (NSString *) nameOfJoystick:(NSUInteger)stickNumber
{
	return @"Dummy joystick";
}

- (int16_t) getAxisWithStick:(NSUInteger)stickNum axis:(NSUInteger)axisNum
{
	return 0;
}

@end
