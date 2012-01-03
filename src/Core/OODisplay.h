//
//  OODisplay.h
//  Oolite
//
//  Created by Jens Ayton on 2007-12-08.
//  Copyright 2007-2012 Jens Ayton. All rights reserved.
//

#import "OOCocoa.h"
#import "OODisplayMode.h"

@class OODisplayMode;


@interface OODisplay: NSObject

+ (NSArray *) allDisplays;	// Array of OODisplay
+ (OODisplay *) mainDisplay;

- (NSString *) name;
- (NSArray *) modes;		// Array of OODisplayMode

- (OODisplayMode *) currentMode;
- (unsigned) indexOfCurrentMode;

/*	Matching. A "matching dictionary" is a dictionary of property list types
	used to identify a display. If no match is found, the main display is
	returned.
*/
- (NSDictionary *) matchingDictionary;
+ (id) displayForMatchingDictionary:(NSDictionary *)dictionary;

@end


// Except were noted, each of these is posted with the relevant display as its object.
// Registering with nil as the object is required to get Display Added notifications.
extern NSString * const kOODisplayAddedNotification;
extern NSString * const kOODisplayRemovedNotification;
extern NSString * const kOODisplaySettingsChangedNotification;
extern NSString * const kOODisplayOrderChangedNotification;	// Object is nil
