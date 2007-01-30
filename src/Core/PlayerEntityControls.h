//
//  PlayerEntity (Controls).h
/*
 *
 *  Oolite
 *
 *  Created by Jens Ayton on Fri Dec 02 2005.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004-2005, Giles C Williams and contributors.
All rights reserved.

This work is licensed under the Creative Commons Attribution-NonCommercial-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Noncommercial. You may not use this work for commercial purposes.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#include "PlayerEntity.h"


@interface PlayerEntity (Controls)

- (void) pollControls:(double) delta_t;
- (void) pollApplicationControls;
- (void) pollFlightControls:(double) delta_t;
- (void) pollFlightArrowKeyControls:(double) delta_t;
- (void) pollGuiArrowKeyControls:(double) delta_t;
- (BOOL) handleGUIUpDownArrowKeys:(GuiDisplayGen *)gui 
                                 :(MyOpenGLView *)gameView;
- (void) switchToMainView;
- (void) pollViewControls;
- (void) pollGuiScreenControls;
- (void) pollGameOverControls:(double) delta_t;
- (void) pollAutopilotControls:(double) delta_t;
- (void) pollDockedControls:(double) delta_t;
- (void) pollDemoControls:(double) delta_t;

@end
