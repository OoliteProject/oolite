/*

Groolite.m

Oolite
Copyright (C) 2004-2012 Giles C Williams and contributors

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

#import "Groolite.h"
#import <Growl/Growl.h>
#import "GameController.h"
#import "GuiDisplayGen.h"
#import "Universe.h"
#import "PlayerEntityLegacyScriptEngine.h"
#import "OOCollectionExtractors.h"

static NSString * const kOOLogGrooliteError	= @"growl.error";
static NSString * const kOOLogGrooliteDebug	= @"growl.debug";

// #define GROOLITE_DEBUG


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
- (void)displayGrowlNotificationWithTitle:(NSString *)inTitle andMessage:(NSString *)inMessage fromApp:(NSString *) inAppname;

@end


@implementation Groolite

- (void)displayGrowlNotificationWithTitle:(NSString *)inTitle andMessage:(NSString *)inMessage fromApp:(NSString *) inAppname
{
	PlayerEntity			*player;
	NSString				*notificationString;
	NSString				*displayString;
	
	player = PLAYER;
	
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
	
	if ([player isSpeechOn])
	{
		[UNIVERSE stopSpeaking];
		[UNIVERSE startSpeakingString:[NSString stringWithFormat:@"%@ message: %@", notificationString, inTitle]];
	}
}


- (id)init
{
	if (![Groolite isEnabled])
	{
		[self release];
		return nil;
	}
	
	self = [super init];
	if (nil != self)
	{
		/*
			Subscribe to GROWL_IS_READY notifications.
			This is necessary in case GrowlHelperApp currently isn't running, and in case
			it is restarted.
		*/
		NSDistributedNotificationCenter *dnc = [NSDistributedNotificationCenter defaultCenter];
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
		OOLog(kOOLogGrooliteError, @"DEBUG GROOLITE exception : %@ : %@", [localException name], [localException reason]);
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
			OOLog(kOOLogGrooliteError, @"DEBUG GROOLITE exception : %@ : %@", [localException name], [localException reason]);
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
			OOLog(kOOLogGrooliteError, @"DEBUG GROOLITE exception : %@ : %@", [localException name], [localException reason]);
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
	if ([gameController isGamePaused])
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
	
	OOLog(kOOLogGrooliteDebug, @"Received Growl notification:  inDict\n%@\n\n", inDict);
	OOLog(kOOLogGrooliteDebug, @"Groolite: priority = %d appname = \"%@\" title = \"%@\", message = \"%@\"", priority, appname, title, message);
	
	if (nil == title || [@"" isEqual:title])
	{
		title = message;
		message = nil;
	}
	
	[self displayGrowlNotificationWithTitle:title andMessage:message fromApp:appname];
}


+ (NSString *) priorityDescription:(int)min_priority
{
	if (min_priority < kGroolitePriorityMinimum || min_priority > kGroolitePriorityMaximum)  return @"?";
	return [UNIVERSE descriptionForArrayKey:@"growl-priority-levels" index:min_priority - kGroolitePriorityMinimum];
}


+ (BOOL) isEnabled
{
	return ![[NSUserDefaults standardUserDefaults] oo_boolForKey:@"groolite-disable" defaultValue:!GROOLITE_VISIBLE];
}

@end
