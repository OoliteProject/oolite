/*

AI.h

Core NPC behaviour/artificial intelligence class.

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

#import <Foundation/Foundation.h>

#define AI_THINK_INTERVAL					0.125


@class ShipEntity, OOInstinct;


@interface AI : NSObject
{
	id					_owner;						// OOWeakReference to the ShipEntity this is the AI for
	NSString			*ownerDesc;					// describes the object this is the AI for
	
	NSDictionary		*stateMachine;
	NSString			*stateMachineName;
	NSString			*currentState;
	NSMutableDictionary	*pendingMessages;
	
	NSMutableArray		*aiStack;
	
	OOInstinct			*rulingInstinct;
	
	double				nextThinkTime;
	double				thinkTimeInterval;
	
}

- (NSString*) name;

- (void) setStateMachine:(NSString *)smName;
- (void) setState:(NSString *)stateName;

- (void) setStateMachine:(NSString *)smName afterDelay:(NSTimeInterval)delay;
- (void) setState:(NSString *)stateName afterDelay:(NSTimeInterval)delay;

- (id) initWithStateMachine:(NSString *) smName andState:(NSString *) stateName;

- (void) setRulingInstinct:(OOInstinct*) instinct;

- (ShipEntity *)owner;
- (void) setOwner:(ShipEntity *)ship;

- (void) preserveCurrentStateMachine;

- (void) restorePreviousStateMachine;

- (void) exitStateMachine;

- (int) ai_stack_depth;

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

- (void)dumpState;

@end
