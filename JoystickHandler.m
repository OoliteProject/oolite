/* */
// JoystickHandler.m
//
// Created for the Oolite-Linux project
//
// Dylan Smith, 2005-09-23
//
// JoystickHandler handles joystick events from SDL, and translates them
// into the appropriate action via a lookup table. The lookup table is
// stored as a simple array rather than an ObjC dictionary since this
// will be examined fairly often. The table is however converted to
// an NSDictionary and back so it can be saved into the user's defaults
// file.
//
// oolite: (c) 2004 Giles C Williams.
// This work is licensed under the Creative Commons Attribution NonCommercial
// ShareAlike license.
//

#import "JoystickHandler.h"

@implementation JoystickHandler

- (id) init
{
   int i;
   
   // Find and open the sticks.
   numSticks=SDL_NumJoysticks();
   NSLog(@"init: numSticks=%d", numSticks);
   if(numSticks)
   {
      for(i = 0; i < numSticks; i++)
      {
         // it's doubtful MAX_STICKS will ever get exceeded, but
         // we need to be defensive.
         if(i > MAX_STICKS)
            break;

         stick[i]=SDL_JoystickOpen(i);
         if(!stick[i])
         {
            NSLog(@"Failed to open joystick #%d", i);
         }
      }
      SDL_JoystickEventState(SDL_ENABLE);
   }
      
   // Make some sensible mappings. This also ensures unassigned
   // axes and buttons are set to unassigned (STICK_NOFUNCTION).
   [self loadStickSettings];
   [self clearStickStates];

   return self;
}

- (BOOL) handleSDLEvent: (SDL_Event *)evt
{
   BOOL rc=NO;
   switch(evt->type)
   {
      case SDL_JOYAXISMOTION:
         [self decodeAxisEvent: (SDL_JoyAxisEvent *)evt];
         rc=YES;
         break;
      case SDL_JOYBUTTONDOWN:
      case SDL_JOYBUTTONUP:
         [self decodeButtonEvent: (SDL_JoyButtonEvent *)evt];
         rc=YES;
         break;
      default:
         NSLog(@"JoystickHandler was sent an event it doesn't know");
   }
   return rc;
}

- (NSPoint) getRollPitchAxis
{
   return NSMakePoint(axstate[AXIS_ROLL], axstate[AXIS_PITCH]);
}

- (BOOL) getButtonState: (int)function
{
   return butstate[function];
}

- (const BOOL *)getAllButtonStates
{
   return butstate;
}

- (double) getPrecision
{
   return precision;
}

- (NSArray *)listSticks
{
   int i;
   NSMutableArray *stickList=[[NSMutableArray alloc] init];
   for(i=0; i < numSticks; i++)
   {
      [stickList addObject: [NSString stringWithFormat: @"%s", SDL_JoystickName(i)]];
   }
   return stickList;
}

- (NSDictionary *)getAxisFunctions
{
   int i,j;
   NSMutableDictionary *fnList=[[NSMutableDictionary alloc] init];

   // Add axes
   for(i=0; i < AXIS_end; i++)
   {
      for(j=0; j < MAX_STICKS; j++)
      {
         if(axismap[j][i] >= 0)
         {
            NSDictionary *fnDict=[NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithBool: YES], STICK_ISAXIS,
                                    [NSNumber numberWithInt: j], STICK_NUMBER, 
                                    [NSNumber numberWithInt: i], STICK_AXBUT,
                                    nil];
            [fnList setValue: fnDict
                      forKey: ENUMKEY(axismap[j][i])];
         }
      }
   }
   return fnList;
}

- (NSDictionary *)getButtonFunctions
{
   int i, j;
   NSMutableDictionary *fnList=[[NSMutableDictionary alloc] init];

   // Add buttons
   for(i=0; i < BUTTON_end; i++)
   {
      for(j=0; j < MAX_STICKS; j++)
      {
         if(buttonmap[j][i] >= 0)
         {
            NSDictionary *fnDict=[NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithBool: NO], STICK_ISAXIS, 
                                    [NSNumber numberWithInt: j], STICK_NUMBER, 
                                    [NSNumber numberWithInt: i], STICK_AXBUT, 
                                    nil];
            [fnList setValue: fnDict
                      forKey: ENUMKEY(buttonmap[j][i])];
         }
      }
   }
   return fnList;
}

- (void) setFunction: (int)function  withDict: (NSDictionary *)stickFn
{
   BOOL isAxis=[(NSNumber *)[stickFn objectForKey: STICK_ISAXIS] boolValue];
   int stickNum=[(NSNumber *)[stickFn objectForKey: STICK_NUMBER] intValue];
   int stickAxBt=[(NSNumber *)[stickFn objectForKey: STICK_AXBUT] intValue];
      
   if(isAxis)
   {
      [self setFunctionForAxis: stickAxBt 
                      function: function
                         stick: stickNum];
   }
   else
   {
      [self setFunctionForButton: stickAxBt
                        function: function
                           stick: stickNum];
   }
}

- (void) setFunctionForAxis: (int)axis 
                   function: (int)function
                      stick: (int)stickNum
{
   int i, j;
   for(i=0; i < AXIS_end; i++)
   {
      for(j=0; j < MAX_STICKS; j++)
      {
         if(axismap[j][i] == function)
         {
            axismap[j][i] = STICK_NOFUNCTION;
            break;
         }
      }
   }
   axismap[stickNum][axis]=function;
}

- (void) setFunctionForButton: (int)button 
                     function: (int)function 
                        stick: (int)stickNum
{
   int i, j;
   for(i=0; i < BUTTON_end; i++)
   {
      for(j=0; j < MAX_STICKS; j++)
      {
         if(buttonmap[j][i] == function)
         {
            buttonmap[j][i] = STICK_NOFUNCTION;
            break;
         }
      }
   }
   buttonmap[stickNum][button]=function;
}

- (void) setDefaultMapping
{
   // assign the simplest mapping: stick 0 having
   // axis 0/1 being roll/pitch and button 0 being fire, 1 being missile
   // All joysticks should at least have two axes and two buttons.
   axismap[0][0]=AXIS_ROLL;
   axismap[0][1]=AXIS_PITCH;
   buttonmap[0][0]=BUTTON_FIRE;
   buttonmap[0][1]=BUTTON_LAUNCHMISSILE;
}

- (void) clearMappings
{
   int i, j;
   for(i=0; i < AXIS_end; i++)
   {
      for(j=0; j < MAX_STICKS; j++)
      {
         axismap[j][i]=STICK_NOFUNCTION;
      }
   }
   for(i=0; i < BUTTON_end; i++)
   {
      for(j=0; j < MAX_STICKS; j++)
      {
         buttonmap[j][i]=STICK_NOFUNCTION;
      }
   }
}

- (void) clearStickStates
{
   int i;
   for(i=0; i < AXIS_end; i++)
   {
      axstate[i]=0;
   }
   for(i=0; i < BUTTON_end; i++)
   {
      butstate[i]=0;
   }
}

- (void)setCallback: (SEL) selector
             object: (id) obj
           hardware: (char)hwflags
{
   cbObject=obj;
   cbSelector=selector;
   cbHardware=hwflags;
}

- (void)clearCallback
{
   cbObject=nil;
   cbHardware=0;
}

- (void)decodeAxisEvent: (SDL_JoyAxisEvent *)evt
{
   // Which axis moved? Does the value need to be made to fit a
   // certain function? Convert axis value to a double.
   double axisvalue=(double)evt->value;

   // Is there a callback we need to make?
   if(cbObject && (cbHardware & HW_AXIS) && abs(axisvalue) > AXCBTHRESH)
   {
      NSDictionary *fnDict=[NSDictionary dictionaryWithObjectsAndKeys:
          [NSNumber numberWithBool: YES], STICK_ISAXIS,
          [NSNumber numberWithInt: evt->which], STICK_NUMBER, 
          [NSNumber numberWithInt: evt->axis], STICK_AXBUT,
           nil];
      cbHardware=0;
      [cbObject performSelector:cbSelector withObject:fnDict];
      cbObject=nil;

      // we are done.
      return;
   }

   int function=axismap[evt->which][evt->axis];
   switch (function)
   {
      case STICK_NOFUNCTION:
         // do nothing
         break;
      case AXIS_ROLL:
      case AXIS_PITCH:
         // Normalize roll/pitch to what the game expects.
         axstate[function]=axisvalue / 32768;
         break;
      default:
         // set the state with no modification.
         axstate[function]=axisvalue;         
   }
}

- (void)decodeButtonEvent: (SDL_JoyButtonEvent *)evt
{
   BOOL bs=NO;

   // Is there a callback we need to make?
   if(cbObject && (cbHardware & HW_BUTTON))
   {
      NSDictionary *fnDict=[NSDictionary dictionaryWithObjectsAndKeys:
          [NSNumber numberWithBool: NO], STICK_ISAXIS,
          [NSNumber numberWithInt: evt->which], STICK_NUMBER, 
          [NSNumber numberWithInt: evt->button], STICK_AXBUT,
           nil];
      cbHardware=0;
      [cbObject performSelector:cbSelector withObject:fnDict];
      cbObject=nil;

      // we are done.
      return;
   }

   int function=buttonmap[evt->which][evt->button];
   if(evt->type == SDL_JOYBUTTONDOWN)
   {
      bs=YES;
   }

   if(function >= 0)
   {
      butstate[function]=bs;
   }

}

- (int)getNumSticks
{
   return numSticks;
}

- (void)saveStickSettings
{
   NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
   [defaults setObject: [self getAxisFunctions]
                forKey: AXIS_SETTINGS];
   [defaults setObject: [self getButtonFunctions]
                forKey: BUTTON_SETTINGS];
   
   [defaults synchronize];
}

- (void)loadStickSettings
{
   int i;
   [self clearMappings];                  
   NSUserDefaults *defaults=[NSUserDefaults standardUserDefaults];
   NSDictionary *axisSettings=[defaults objectForKey: AXIS_SETTINGS];
   NSDictionary *buttonSettings=[defaults objectForKey: BUTTON_SETTINGS];
   if(axisSettings)
   {
      NSArray *keys=[axisSettings allKeys];
      for(i=0; i < [keys count]; i++)
      {
         NSString *key=[keys objectAtIndex: i];
         [self setFunction: [key intValue]
                  withDict: [axisSettings objectForKey: key]];
      }
   }
   if(buttonSettings)
   {
      NSArray *keys=[buttonSettings allKeys];
      for(i=0; i < [keys count]; i++)
      {
         NSString *key=[keys objectAtIndex: i];
         [self setFunction: [key intValue]
                  withDict: [buttonSettings objectForKey: key]];
      }
   }
   else
   {
      // Nothing to load - set useful defaults
      [self setDefaultMapping];
   }
}

@end
