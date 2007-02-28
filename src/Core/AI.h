/*

AI.h
Created by Giles Williams on 2004-04-03.

Core NPC behaviour/artificial intelligence class.

For Oolite
Copyright (C) 2004  Giles C Williams

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

#import <Foundation/Foundation.h>

#import "entities.h"

#define AI_THINK_INTERVAL					0.125

extern int debug;

@class OOInstinct;

@interface AI : NSObject {

	ShipEntity		*owner;						// the object this is the AI for
	NSString		*owner_desc;				// describes the object this is the AI for

	NSDictionary	*stateMachine;
	NSString		*stateMachineName;
	NSString		*currentState;
	NSMutableDictionary  *pendingMessages;
	
	NSMutableArray  *ai_stack;
	
	NSLock			*aiLock;
	
	OOInstinct*		rulingInstinct;
	
	double			nextThinkTime;
	double			thinkTimeInterval;
	
}

- (id) prepare;

- (id) initWithStateMachine:(NSString *) smName andState:(NSString *) stateName;

- (void) setRulingInstinct:(OOInstinct*) instinct;

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
