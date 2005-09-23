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
   [self setDefaultMapping]; 
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

- (double) getPrecision
{
   return precision;
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
   int i, j;
   
   // Ensure the default action is unassigned.
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

   // assign the simplest mapping: stick 0 having
   // axis 0/1 being roll/pitch and button 0 being fire, 1 being missile
   // All joysticks should at least have two axes and two buttons.
   axismap[0][0]=AXIS_ROLL;
   axismap[0][1]=AXIS_PITCH;
   buttonmap[0][0]=BUTTON_FIRE;
   buttonmap[0][1]=BUTTON_LAUNCHMISSILE;
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

- (void)decodeAxisEvent: (SDL_JoyAxisEvent *)evt
{
   // Which axis moved? Does the value need to be made to fit a
   // certain function? Convert axis value to a double.
   double axisvalue=(double)evt->value;
   int function=axismap[evt->which][evt->axis];
   switch (function)
   {
      case STICK_NOFUNCTION:
         // do nothing
         break;
      case STICK_REPORTFUNCTION:
         // TODO
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

@end
