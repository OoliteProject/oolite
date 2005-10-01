/* */
// PlayerEntity_StickMapper.m
//
// Created for the Oolite-Linux project, but portable to other archs.
//
// Dylan Smith, 2005-09-24
//
// This category adds the GUI to handle player assignments of joystick
// things (axes, buttons) to game functions.
//
// oolite: (c) 2004 Giles C Williams.
// This work is licensed under the Creative Commons Attribution NonCommercial
// ShareAlike license.
//

#import "PlayerEntity_StickMapper.h"
#import "JoystickHandler.h"

@implementation PlayerEntity (StickMapper)

- (void) setGuiToStickMapperScreen
{
   GuiDisplayGen *gui=[universe gui];
   NSArray *stickList=[stickHandler listSticks];
   int i;
   int tabStop[GUI_MAX_COLUMNS];
   tabStop[0]=50;
   tabStop[1]=210;
   tabStop[2]=320;
   [gui setTabStops: tabStop];
   
   gui_screen=GUI_SCREEN_STICKMAPPER;
   [gui clear];
   [gui setTitle:[NSString stringWithFormat:@"Configure Joysticks"]];
  
   for(i=0; i < [stickList count]; i++)
   {
      [gui setArray: [NSArray arrayWithObjects:
         [NSString stringWithFormat: @"Stick %d", i+1],
         [stickList objectAtIndex: i], nil]
             forRow: i + STICKNAME_ROW];
   }
   
   [self displayFunctionList: gui];

   [gui setArray: [NSArray arrayWithObjects:
      [NSString stringWithString: @"Select a function and press Enter to modify or 'u' to unset."], nil]
          forRow: INSTRUCT_ROW];

   [gui setSelectedRow: selFunctionIdx + FUNCSTART_ROW];
   [[universe gameView] supressKeysUntilKeyUp];

}

- (void) stickMapperInputHandler: (GuiDisplayGen *)gui
                            view: (MyOpenGLView *)gameView
{
   // Don't do anything if the user is supposed to be selecting
   // a function - other than look for Escape.
   if(waitingForStickCallback)
   {
      if([gameView isDown: 27])
      {
         [stickHandler clearCallback];
         [gui setArray: [NSArray arrayWithObjects:
            [NSString stringWithString: @"Function setting aborted."], nil]
            forRow: INSTRUCT_ROW];
         waitingForStickCallback=NO;
      }

      // Break out now.
      return;
   }
   
   [self handleGUIUpDownArrowKeys: gui: gameView];
   
   if([gameView isDown: 13])
   {
      selFunctionIdx=[gui selectedRow]-FUNCSTART_ROW;
      NSDictionary *entry=[stickFunctions objectAtIndex: selFunctionIdx];
      int hw=[(NSNumber *)[entry objectForKey: KEY_ALLOWABLE] intValue];
      [stickHandler setCallback: @selector(updateFunction:)
                         object: self 
                       hardware: hw];

      // Print instructions
      NSString *instructions;
      switch(hw)
      {
         case HW_AXIS:
            instructions=[NSString stringWithString: 
               @"Fully deflect the axis you want to use for this function. Esc aborts."];
            break;
         case HW_BUTTON:
            instructions=[NSString stringWithString:
               @"Press the button you want to use for this function. Esc aborts."];
            break;
         default:
            instructions=[NSString stringWithString:
               @"Press the button or deflect the axis you want to use for this function."];
      }
      [gui setArray: [NSArray arrayWithObjects: instructions, nil] forRow: INSTRUCT_ROW];
      waitingForStickCallback=YES;
   }

   if([gameView isDown: 'u'])
   {
      [self removeFunction: [gui selectedRow]-FUNCSTART_ROW];
   }
}

// Callback function, called by JoystickHandler when the callback
// is set. The dictionary contains the thing that was pressed/moved.
- (void) updateFunction: (NSDictionary *)hwDict
{
   waitingForStickCallback=NO;

   // Right time and the right place?
   if(gui_screen != GUI_SCREEN_STICKMAPPER)
   {
      NSLog(@"updateFunction: Oops, we weren't expecting that callback");
      return;
   }
   
   // What moved?
   int function;
   NSDictionary *entry=[stickFunctions objectAtIndex: selFunctionIdx];
   if([(NSNumber *)[hwDict objectForKey: STICK_ISAXIS] boolValue] == YES)
   {
      function=[(NSNumber *)[entry objectForKey: KEY_AXISFN] intValue];
   }
   else
   {
      function=[(NSNumber *)[entry objectForKey: KEY_BUTTONFN] intValue];
   }
   [stickHandler setFunction: function withDict: hwDict];
   [stickHandler saveStickSettings];

   // Update the GUI (this will refresh the function list).
   [self setGuiToStickMapperScreen];
}

- (void) removeFunction: (int)idx
{
   selFunctionIdx=idx;
   NSDictionary *entry=[stickFunctions objectAtIndex: idx];
   NSNumber *butfunc=[entry objectForKey: KEY_BUTTONFN];
   NSNumber *axfunc=[entry objectForKey: KEY_AXISFN];

   // Some things can have either axis or buttons - make sure we clear
   // both!
   if(butfunc)
   {
      [stickHandler unsetButtonFunction: [butfunc intValue]];
   }
   if(axfunc)
   {
      [stickHandler unsetAxisFunction: [axfunc intValue]];
   }
   [stickHandler saveStickSettings];
   [self setGuiToStickMapperScreen];
}

- (void) displayFunctionList: (GuiDisplayGen *)gui
{
   int i;
   [gui setColor: [NSColor greenColor] forRow: HEADINGROW];
   [gui setArray: [NSArray arrayWithObjects:
      @"Function", @"Assigned to", @"Type", nil]
          forRow: HEADINGROW];

   if(!stickFunctions)
   {
      stickFunctions=[self getStickFunctionList];
   }
   NSDictionary *assignedAxes=[stickHandler getAxisFunctions];
   NSDictionary *assignedButs=[stickHandler getButtonFunctions];
   
   for(i=0; i < [stickFunctions count]; i++)
   {
      NSString *allowedThings;
      NSString *assignment;
      NSDictionary *entry=[stickFunctions objectAtIndex: i];
      NSString *axFuncKey=[(NSNumber *)[entry objectForKey: KEY_AXISFN] stringValue];
      NSString *butFuncKey=[(NSNumber *)[entry objectForKey: KEY_BUTTONFN] stringValue];
      int allowable=[(NSNumber *)[entry objectForKey: KEY_ALLOWABLE] intValue];
      switch(allowable)
      {
         case HW_AXIS:
            allowedThings=[NSString stringWithString: @"Axis"];
            assignment=[self describeStickDict:
               [assignedAxes objectForKey: axFuncKey]];
            break;
         case HW_BUTTON:
            allowedThings=[NSString stringWithString: @"Button"];
            assignment=[self describeStickDict:
               [assignedButs objectForKey: butFuncKey]];
            break;
         default:
            allowedThings=[NSString stringWithString: @"Axis/Button"];

            // axis has priority
            assignment=[self describeStickDict:
               [assignedAxes objectForKey: axFuncKey]];
            if(!assignment)
               assignment=[self describeStickDict:
                  [assignedButs objectForKey: butFuncKey]];
      }
      
      // Find out what's assigned for this function currently.
      if(!assignment)
         assignment=[NSString stringWithString: @"   -   "];

      [gui setArray: [NSArray arrayWithObjects: 
         [entry objectForKey: KEY_GUIDESC], assignment, allowedThings, nil]
             forRow: i + FUNCSTART_ROW];
      [gui setKey: GUI_KEY_OK forRow: i + FUNCSTART_ROW];
   }
   [gui setSelectableRange: NSMakeRange(FUNCSTART_ROW, i + FUNCSTART_ROW - 1)];
                                      
} 

- (NSString *) describeStickDict: (NSDictionary *)stickDict
{
   NSString *desc=nil;
   if(stickDict)
   {
      int thingNumber=[(NSNumber *)[stickDict objectForKey: STICK_AXBUT]
                           intValue];
      int stickNumber=[(NSNumber *)[stickDict objectForKey: STICK_NUMBER]
                           intValue];
      // Button or axis?
      if([(NSNumber *)[stickDict objectForKey: STICK_ISAXIS] boolValue])
      {
         desc=[NSString stringWithFormat: @"Stick %d axis %d",
                  stickNumber+1, thingNumber+1];
      }
      else
      {
         desc=[NSString stringWithFormat: @"Stick %d button %d",
                  stickNumber+1, thingNumber+1];
      }
   }
   return desc;
}

- (NSString *)hwToString: (int)hwFlags
{
   NSString *hwString;
   switch(hwFlags)
   {
      case HW_AXIS:
         hwString=[NSString stringWithString: @"axis"];
         break;
      case HW_BUTTON:
         hwString=[NSString stringWithString: @"button"];
         break;
      default:
         hwString=[NSString stringWithString: @"axis/button"];
   }
   return hwString;   
}

// TODO:
// FUTURE: This data could be put into a plist (i18n or just modifiable by
// the user). It is otherwise an ugly method, but it'll do for testing.
- (NSArray *)getStickFunctionList
{
   NSMutableArray *funcList=[[NSMutableArray alloc] init];

   [funcList addObject: 
      [self makeStickGuiDict: @"Roll" 
                   allowable: HW_AXIS
                      axisfn: AXIS_ROLL
                       butfn: STICK_NOFUNCTION]];
   [funcList addObject: 
      [self makeStickGuiDict: @"Pitch"
                   allowable: HW_AXIS
                      axisfn: AXIS_PITCH
                       butfn: STICK_NOFUNCTION]];
   [funcList addObject:
      [self makeStickGuiDict: @"Increase thrust"
                   allowable: HW_AXIS|HW_BUTTON
                      axisfn: AXIS_THRUST
                       butfn: BUTTON_INCTHRUST]];
   [funcList addObject:
      [self makeStickGuiDict: @"Decrease thrust"
                   allowable: HW_AXIS|HW_BUTTON
                      axisfn: AXIS_THRUST
                       butfn: BUTTON_DECTHRUST]];
   [funcList addObject:
      [self makeStickGuiDict: @"Primary weapon"
                   allowable: HW_BUTTON
                      axisfn: STICK_NOFUNCTION
                       butfn: BUTTON_FIRE]];
   [funcList addObject:
      [self makeStickGuiDict: @"Secondary weapon"
                   allowable: HW_BUTTON
                      axisfn: STICK_NOFUNCTION
                       butfn: BUTTON_LAUNCHMISSILE]];
   [funcList addObject:
      [self makeStickGuiDict: @"Arm secondary"
                   allowable: HW_BUTTON
                      axisfn: STICK_NOFUNCTION
                       butfn: BUTTON_ARMMISSILE]];
   [funcList addObject:
      [self makeStickGuiDict: @"Disarm secondary"
                   allowable: HW_BUTTON
                      axisfn: STICK_NOFUNCTION
                       butfn: BUTTON_UNARM]];
   [funcList addObject:
      [self makeStickGuiDict: @"Cycle secondary"
                   allowable: HW_BUTTON
                      axisfn: STICK_NOFUNCTION
                       butfn: BUTTON_CYCLEMISSILE]];
   [funcList addObject:
      [self makeStickGuiDict: @"ECM"
                   allowable: HW_BUTTON
                      axisfn: STICK_NOFUNCTION
                       butfn: BUTTON_ECM]];
   [funcList addObject:
      [self makeStickGuiDict: @"Toggle ID"
                   allowable: HW_BUTTON
                      axisfn: STICK_NOFUNCTION
                       butfn: BUTTON_ID]];
   [funcList addObject:
      [self makeStickGuiDict: @"Fuel Injection"
                   allowable: HW_BUTTON
                      axisfn: STICK_NOFUNCTION
                       butfn: BUTTON_FUELINJECT]];
   [funcList addObject:
      [self makeStickGuiDict: @"Hyperspeed"
                   allowable: HW_BUTTON
                      axisfn: STICK_NOFUNCTION
                       butfn: BUTTON_HYPERSPEED]];
   [funcList addObject:
      [self makeStickGuiDict: @"Roll/pitch precision toggle"
                   allowable: HW_BUTTON
                      axisfn: STICK_NOFUNCTION
                       butfn: BUTTON_PRECISION]];
   return funcList;
}

- (NSDictionary *)makeStickGuiDict: (NSString *)what
                         allowable: (int)allowable
                            axisfn: (int)axisfn
                             butfn: (int)butfn
{
   NSMutableDictionary *guiDict=[[NSMutableDictionary alloc] init];
   [guiDict setObject: what  forKey: KEY_GUIDESC];
   [guiDict setObject: [NSNumber numberWithInt: allowable]  
               forKey: KEY_ALLOWABLE];
   if(axisfn >= 0)
      [guiDict setObject: [NSNumber numberWithInt: axisfn]
                  forKey: KEY_AXISFN];
   if(butfn >= 0)
      [guiDict setObject: [NSNumber numberWithInt: butfn]
                  forKey: KEY_BUTTONFN];
   return guiDict;
} 

@end

