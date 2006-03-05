//
//  Groolite.m
//  Oolite
/*

Copyright © 2005, Jens Ayton
All rights reserved.

This work is licensed under the Creative Commons Attribution-ShareAlike License.
To view a copy of this license, visit http://creativecommons.org/licenses/by-sa/2.0/
or send a letter to Creative Commons, 559 Nathan Abbott Way, Stanford, California 94305, USA.

You are free:

•	to copy, distribute, display, and perform the work
•	to make derivative works

Under the following conditions:

•	Attribution. You must give the original author credit.

•	Share Alike. If you alter, transform, or build upon this work,
you may distribute the resulting work only under a license identical to this one.

For any reuse or distribution, you must make clear to others the license terms of this work.

Any of these conditions can be waived if you get permission from the copyright holder.

Your fair use and other rights are in no way affected by the above.

*/

#import "Groolite.h"
#import <Growl/Growl.h>
#import "GameController.h"
#import "GuiDisplayGen.h"
#import "Universe.h"
#import "PlayerEntity.h"

//	#define GROOLITE_DEBUG
#ifdef GROOLITE_DEBUG
	#define DEBUGMSG NSLog
#else
	#define DEBUGMSG (void)
#endif


@protocol GrowlNotificationObserver
- (oneway void) notifyWithDictionary:(bycopy NSDictionary *)dict;
@end


@protocol GrowlNotificationCenterProtocol

- (oneway void) addObserver:(byref id<GrowlNotificationObserver>)observer;
- (oneway void) removeObserver:(byref id<GrowlNotificationObserver>)observer;

@end


@interface Groolite (Private) <GrowlNotificationObserver>

- (void)connectToGrowl:unused;
- (void)disconnectFromGrowl:unused;
- (void)connectionDied:unused;
- (void)displayGrowlNotificiationWithTitle:(NSString *)inTitle andMessage:(NSString *)inMessage fromApp:(NSString *) inAppname;

@end


@implementation Groolite

- (void)displayGrowlNotificiationWithTitle:(NSString *)inTitle andMessage:(NSString *)inMessage fromApp:(NSString *) inAppname
{
	Universe				*universe;
	PlayerEntity			*player;
	NSString				*notificationString;
	NSString				*displayString;
	
	universe = [gameController universe];
	player = (PlayerEntity *)[universe entityZero];
	
	if (!inTitle)
		return;	// catch blank messages
	
	if (!inAppname)
	{
		// standard response
		notificationString = @"Growl";
	}
	else
	{
		// response if we're told which application is sending the message
		notificationString = inAppname;
	}
	
	if (nil == inMessage)
	{
		// Terse mode
		displayString = [NSString stringWithFormat:@"%@: %@", notificationString, inTitle];
	}
	else
	{
		// Standard 'verbose' mode
		displayString = [NSString stringWithFormat:@"%@: %@\n%@", notificationString, inTitle, inMessage];
	}
	
	[player commsMessage: displayString];
	
	if ([player speech_on])
	{
		if ([universe isSpeaking]) [universe stopSpeaking];
		[universe startSpeakingString:[NSString stringWithFormat:@"%@ message: %@", notificationString, inTitle]];
	}
}


- (id)init
{
	NSDistributedNotificationCenter		*dnc;
	
	self = [super init];
	if (nil != self)
	{
		/*
			Subscribe to GROWL_IS_READY notifications.
			This is necessary in case GrowlHelperApp currently isn't running, and in case
			it is restarted.
		*/
		dnc = [NSDistributedNotificationCenter defaultCenter];
		[dnc addObserver:self selector:@selector(connectToGrowl:) name:GROWL_IS_READY object:nil];
		
		// Also, try to connect on the off chance it’s running now.
		[self connectToGrowl:nil];
	}
	return self;
}


- (void)dealloc
{
	[self disconnectFromGrowl:nil];
	
	[super dealloc];
}


- (void)connectToGrowl:unused
{
	NSConnection			*theConnection;
	NSNotificationCenter	*nc;
	id<GrowlNotificationCenterProtocol> growlNC;
	
	NS_DURING
		theConnection = [NSConnection connectionWithRegisteredName:@"GrowlNotificationCenter" host:nil];
		if (nil != theConnection)
		{
			growlNC = (id<GrowlNotificationCenterProtocol>)[theConnection rootProxy];
			[growlNC addObserver:self];
			
			// Subscribe to connection-died and application-quit notifications, so we can unregister appropriately.
			nc = [NSNotificationCenter defaultCenter];
			[nc addObserver:self selector:@selector(connectionDied:) name:NSConnectionDidDieNotification object:theConnection];
			[nc addObserver:self selector:@selector(disconnectFromGrowl:) name:NSApplicationWillTerminateNotification object:nil];
			
			connection = [theConnection retain];
		}
	NS_HANDLER
//		DEBUGMSG(@"DEBUG GROOLITE exception : %@ : %@", [localException name], [localException reason]);
	NS_ENDHANDLER
}


- (void)disconnectFromGrowl:unused
{
	NSNotificationCenter	*nc;
	id<GrowlNotificationCenterProtocol> growlNC;
	
	if (nil != connection)
	{
		NS_DURING
			growlNC = (id<GrowlNotificationCenterProtocol>)[connection rootProxy];
			[growlNC removeObserver:self];
			[connection release];
			connection = nil;
			
			nc = [NSNotificationCenter defaultCenter];
			[nc removeObserver:self];
		NS_HANDLER
//			DEBUGMSG(@"DEBUG GROOLITE exception : %@ : %@", [localException name], [localException reason]);
		NS_ENDHANDLER
	}
}


- (void)connectionDied:unused
{
	NSNotificationCenter	*nc;
	
	if (nil != connection)
	{
		NS_DURING
			[connection release];
			connection = nil;
			
			nc = [NSNotificationCenter defaultCenter];
			[nc removeObserver:self];
		NS_HANDLER
//			DEBUGMSG(@"DEBUG GROOLITE exception : %@ : %@", [localException name], [localException reason]);
		NS_ENDHANDLER
	}
}


- (oneway void) notifyWithDictionary:(bycopy NSDictionary *)inDict
{
	NSUserDefaults			*prefs;
	int						priority;
	NSString				*title;
	NSString				*message;
	NSString				*appname;
	
	prefs = [NSUserDefaults standardUserDefaults];

	// Ignore if we're in a window
	#ifndef GROOLITE_DEBUG
	if (![gameController inFullScreenMode])
		return;
	#endif
	
	// Ignore if we're paused
	if ([gameController game_is_paused])
		return;
	
	// Check that priority is not below our threshold
	priority = [[inDict objectForKey:GROWL_NOTIFICATION_PRIORITY] intValue];
	#ifndef GROOLITE_DEBUG
	if (priority < [prefs integerForKey:@"groolite-min-priority"])
		return;
	#endif
	
	// If we get here, we need to handle the message
	title = [inDict objectForKey:GROWL_NOTIFICATION_TITLE];
	message = [inDict objectForKey:GROWL_NOTIFICATION_DESCRIPTION];
	appname = [inDict objectForKey:GROWL_APP_NAME];
	
//	DEBUGMSG(@"DEBUG Groolite:  inDict\n%@\n\n", inDict);
//	DEBUGMSG(@"Groolite: priority = %d appname = \"%@\" title = \"%@\", message = \"%@\"", priority, appname, title, message);
	
	if (nil == title || [@"" isEqual:title])
	{
		title = message;
		message = nil;
	}
	
	[self displayGrowlNotificiationWithTitle:title andMessage:message fromApp:appname];
}

+ (NSString*) priorityDescription: (int) min_priority
{
	NSString* result;
	switch (min_priority)
	{
		case -2:
			result = @"ON (for all messages)";	break;
		case -1:
			result = @"ON (for low priority messages)";	break;
		case 0:
			result = @"ON (for medium priority messages)";	break;
		case 1:
			result = @"ON (for high priority messages)";	break;
		case 2:
			result = @"ON (for highest priority messages)";	break;
		case 3:
			result = @"OFF (for all messages)";	break;
		default:
			result = @"Bad Value";
	}
	return result;
}

@end
