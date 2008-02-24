/*
 
 OOLegacyEventHandlerScript.m
 
 
 Oolite
 Copyright (C) 2004-2008 Giles C Williams and contributors
 
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

#import "OOLegacyEventHandlerScript.h"
#import "PlayerEntityLegacyScriptEngine.h"


@implementation OOLegacyEventHandlerScript

- (id)initWithEventHandlers:(NSDictionary *)eventHandlers forOwner:(id<OOWeakReferenceSupport>)owner
{
	self = [super init];
	if (self != nil)
	{
		if (eventHandlers != nil && owner != nil)
		{
			_eventHandlers = [eventHandlers copy];
			_owner = [owner weakRetain];
		}
		else
		{
			[self release];
			self = nil;
		}
	}
	return self;
}


- (void)dealloc
{
	[_eventHandlers release];
	[_owner release];
	
	[super dealloc];
}


- (NSString *)name
{
	return @"<synthesized event handler script>";
}


- (NSString *)scriptDescription
{
	return @"Script created by aggregation of legacy event handlers.";
}


- (NSString *)version
{
	return nil;
}

- (void)runWithTarget:(Entity *)target
{
	// Do nothing
}


- (BOOL)doEvent:(NSString *)eventName
{
	id						actions = nil;
	
	actions = [_eventHandlers objectForKey:eventName];
	if (actions != nil)
	{
		[[PlayerEntity sharedPlayer] scriptActions:actions forTarget:_owner];
		return YES;
	}
	return NO;
}


- (BOOL)doEvent:(NSString *)eventName withArguments:(NSArray *)arguments
{
	return [self doEvent:eventName];
}

@end
