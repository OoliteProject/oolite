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
      [NSString stringWithString: @"Select a function and press Enter to modify."], nil]
          forRow: INSTRUCT_ROW];

   [gui setSelectedRow: FUNCSTART_ROW];
   [universe guiUpdated];
   [[universe gameView] supressKeysUntilKeyUp];

}

- (void) stickMapperInputHandler: (GuiDisplayGen *)gui
                            view: (MyOpenGLView *)gameView
{
   [self handleGUIUpDownArrowKeys: gui: gameView];
   if([gameView isDown: 13])
   {
      int funcIdx=[gui selectedRow] - FUNCSTART_ROW;
   }
}

- (void) displayFunctionList: (GuiDisplayGen *)gui
{
   int i;
   [gui setColor: [NSColor greenColor] forRow: HEADINGROW];
   [gui setArray: [NSArray arrayWithObjects:
      @"Function", @"Assigned to", @"Type", nil]
          forRow: HEADINGROW];

   NSArray *functions=[self getStickFunctionList];
   NSDictionary *assignedAxes=[stickHandler getAxisFunctions];
   NSDictionary *assignedButs=[stickHandler getButtonFunctions];
   
   for(i=0; i < [functions count]; i++)
   {
      NSString *allowedThings;
      NSString *assignment;
      NSDictionary *entry=[functions objectAtIndex: i];
      NSString *axFuncKey=[(NSNumber *)[entry objectForKey: KEY_AXISFN] stringValue];
      NSString *butFuncKey=[(NSNumber *)[entry objectForKey: KEY_BUTTONFN] stringValue];
      int allowable=[(NSNumber *)[entry objectForKey: KEY_ALLOWABLE] intValue];
      switch(allowable)
      {
         case ALLOW_AXISONLY:
            allowedThings=[NSString stringWithString: @"Axis"];
            assignment=[self describeStickDict:
               [assignedAxes objectForKey: axFuncKey]];
            break;
         case ALLOW_BUTTONONLY:
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
         assignment=[NSString stringWithString: @"  - "];

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

// TODO:
// FUTURE: This data could be put into a plist (i18n or just modifiable by
// the user). It is otherwise an ugly method, but it'll do for testing.
- (NSArray *)getStickFunctionList
{
   NSMutableArray *funcList=[[NSMutableArray alloc] init];

   [funcList addObject: 
      [self makeStickGuiDict: @"Roll" 
                   allowable: ALLOW_AXISONLY
                      axisfn: AXIS_ROLL
                       butfn: STICK_NOFUNCTION]];
   [funcList addObject: 
      [self makeStickGuiDict: @"Pitch"
                   allowable: ALLOW_AXISONLY
                      axisfn: AXIS_PITCH
                       butfn: STICK_NOFUNCTION]];
   [funcList addObject:
      [self makeStickGuiDict: @"Increase thrust"
                   allowable: ALLOW_ALL
                      axisfn: AXIS_THRUST
                       butfn: BUTTON_INCTHRUST]];
   [funcList addObject:
      [self makeStickGuiDict: @"Decrease thrust"
                   allowable: ALLOW_ALL
                      axisfn: AXIS_THRUST
                       butfn: BUTTON_DECTHRUST]];
   [funcList addObject:
      [self makeStickGuiDict: @"Primary weapon"
                   allowable: ALLOW_BUTTONONLY
                      axisfn: STICK_NOFUNCTION
                       butfn: BUTTON_FIRE]];
   [funcList addObject:
      [self makeStickGuiDict: @"Secondary weapon"
                   allowable: ALLOW_BUTTONONLY
                      axisfn: STICK_NOFUNCTION
                       butfn: BUTTON_LAUNCHMISSILE]];
   [funcList addObject:
      [self makeStickGuiDict: @"Arm secondary"
                   allowable: ALLOW_BUTTONONLY
                      axisfn: STICK_NOFUNCTION
                       butfn: BUTTON_ARMMISSILE]];
   [funcList addObject:
      [self makeStickGuiDict: @"Disarm secondary"
                   allowable: ALLOW_BUTTONONLY
                      axisfn: STICK_NOFUNCTION
                       butfn: BUTTON_UNARM]];
   [funcList addObject:
      [self makeStickGuiDict: @"Cycle secondary"
                   allowable: ALLOW_BUTTONONLY
                      axisfn: STICK_NOFUNCTION
                       butfn: BUTTON_CYCLEMISSILE]];
   [funcList addObject:
      [self makeStickGuiDict: @"ECM"
                   allowable: ALLOW_BUTTONONLY
                      axisfn: STICK_NOFUNCTION
                       butfn: BUTTON_ECM]];
   [funcList addObject:
      [self makeStickGuiDict: @"Toggle ID"
                   allowable: ALLOW_BUTTONONLY
                      axisfn: STICK_NOFUNCTION
                       butfn: BUTTON_ID]];
   [funcList addObject:
      [self makeStickGuiDict: @"Fuel Injection"
                   allowable: ALLOW_BUTTONONLY
                      axisfn: STICK_NOFUNCTION
                       butfn: BUTTON_FUELINJECT]];
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

