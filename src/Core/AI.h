//
//  AI.h
/*
 *
 *  Oolite
 *
 *  Created by Giles Williams on Sat Apr 03 2004.
 *  Copyright (c) 2004 for aegidian.org. All rights reserved.
 *

Copyright (c) 2004, Giles C Williams
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

#import <Foundation/Foundation.h>

#import "entities.h"

#define AI_THINK_INTERVAL					0.125

extern int debug;

@interface AI : NSObject {

	ShipEntity		*owner;						// the object this is the AI for
	NSString		*owner_desc;				// describes the object this is the AI for

	NSDictionary	*stateMachine;
	NSString		*stateMachineName;
	NSString		*currentState;
	NSMutableDictionary  *pendingMessages;
	
	NSMutableArray  *ai_stack;
	
	NSLock			*aiLock;
	
	double			nextThinkTime;
	double			thinkTimeInterval;
	
}

- (id) prepare;

- (id) initWithStateMachine:(NSString *) smName andState:(NSString *) stateName;

- (void) setOwner:(ShipEntity *)ship;

- (void) preserveCurrentStateMachine;

- (void) restorePreviousStateMachine;

- (void) exitStateMachine;

- (void) setStateMachine:(NSString *) smName;

- (NSString*) name;

- (int) ai_stack_depth;

- (void) setState:(NSString *) stateName;

- (void) reactToMessage:(NSString *) message;

- (void) takeAction:(NSString *) action;

- (void) think;

- (void) message:(NSString *) ms;

- (void) setNextThinkTime:(double) ntt;

- (double) nextThinkTime;

- (void) setThinkTimeInterval:(double) tti;

- (double) thinkTimeInterval;

- (void) clearStack;

- (void) clearAllData;

@end
