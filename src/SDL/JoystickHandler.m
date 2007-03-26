/*

JoystickHandler.m
By Dylan Smith

Oolite
Copyright (C) 2004-2007 Giles C Williams and contributors

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

#import "JoystickHandler.h"
#import "OOLogging.h"

#define kOOLogUnconvertedNSLog @"unclassified.JoystickHandler"


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

   precisionMode=NO;
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

- (double) getAxisState: (int)function
{
   return axstate[function];
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
   for(i=0; i < MAX_AXES; i++)
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
   for(i=0; i < MAX_BUTTONS; i++)
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
   Sint16 axisvalue=SDL_JoystickGetAxis(stick[stickNum], axis);
   for(i=0; i < MAX_AXES; i++)
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

   // initialize the throttle to what it's set to now (or else the
   // commander has to waggle the throttle to wake it up). Other axes
   // set as default.
   if(function == AXIS_THRUST)
   {
      axstate[function]=(float)(65536 - (axisvalue + 32768)) / 65536;
   }
   else
   {
      axstate[function]=(float)axisvalue / STICK_NORMALDIV;
   }
}

- (void) setFunctionForButton: (int)button 
                     function: (int)function 
                        stick: (int)stickNum
{
   int i, j;
   for(i=0; i < MAX_BUTTONS; i++)
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

- (void) unsetAxisFunction: (int)function
{
   int i, j;
   for(i=0; i < MAX_AXES; i++)
   {
      for(j=0; j < MAX_STICKS; j++)
      {
         if(axismap[j][i] == function)
         {
            axismap[j][i]=STICK_NOFUNCTION;
            axstate[function]=STICK_AXISUNASSIGNED;
            break;
         }
      }
   }
}

- (void) unsetButtonFunction: (int)function
{
   int i,j;
   for(i=0; i < MAX_BUTTONS; i++)
   {
      for(j=0; j < MAX_STICKS; j++)
      {
         if(buttonmap[j][i] == function)
         {
            buttonmap[j][i]=STICK_NOFUNCTION;
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
   axismap[0][0]=AXIS_ROLL;
   axismap[0][1]=AXIS_PITCH;
   buttonmap[0][0]=BUTTON_FIRE;
   buttonmap[0][1]=BUTTON_LAUNCHMISSILE;
}

- (void) clearMappings
{
   int i, j;
   for(i=0; i < MAX_AXES; i++)
   {
      for(j=0; j < MAX_STICKS; j++)
      {
         axismap[j][i]=STICK_NOFUNCTION;
      }
   }
   for(i=0; i < MAX_BUTTONS; i++)
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
      axstate[i]=STICK_AXISUNASSIGNED;
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
      NSLog(@"Callback...");
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

   // SDL seems to have some bizarre (perhaps a bug) behaviour when
   // events get queued up because the game isn't ready to handle
   // them (perhaps it's loading a commander and initializing the
   // universe, and the main event loop is blocked).
   // What happens is SDL lies about the axis that was triggered. For
   // each queued event it adds 1 to the axis number!! This does
   // not seem to happen with buttons.
   int function;
   if(evt->axis < MAX_AXES)
   {
      function=axismap[evt->which][evt->axis];
   }
   else
   {
      NSLog(@"Stick axis out of range - axis was %d", evt->axis);
      return;
   }
   switch (function)
   {
      case STICK_NOFUNCTION:
         // do nothing
         break;
      case AXIS_THRUST:
         // Normalize the thrust setting.
         axstate[function]=(float)(65536 - (axisvalue + 32768)) / 65536;
         break;
      case AXIS_ROLL:
      case AXIS_PITCH:
         if(precisionMode)
         {
            axstate[function]=axisvalue / STICK_PRECISIONDIV;
         }
         else
         {
            axstate[function]=axisvalue / STICK_NORMALDIV;
         }
         break;
      default:
         // set the state with no modification.
         axstate[function]=axisvalue / 32768;         
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

   // Defensive measure - see comments in the axis handler for why.
   int function;
   if(evt->button < MAX_BUTTONS)
   {
      function=buttonmap[evt->which][evt->button];
   }
   else
   {
      NSLog(@"Joystick button out of range: %d", evt->button);
      return;
   }
   if(evt->type == SDL_JOYBUTTONDOWN)
   {
      bs=YES;
      if(function == BUTTON_PRECISION)
      {
         precisionMode=!precisionMode;
         
         // adjust current states now
         if(precisionMode)
         {
            axstate[AXIS_PITCH] /= STICK_PRECISIONFAC;
            axstate[AXIS_ROLL] /= STICK_PRECISIONFAC;
         }
         else
         {
            axstate[AXIS_PITCH] *= STICK_PRECISIONFAC;
            axstate[AXIS_ROLL] *= STICK_PRECISIONFAC;
         }
      }
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
