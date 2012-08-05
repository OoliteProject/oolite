/*

GameController+MacFullScreen.m

Full-screen rendering support for 64-bit Mac Oolite.


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


#import "GameController.h"

#if OOLITE_MAC_OS_X && OOLITE_64_BIT

#import "OOCollectionExtractors.h"
#import "MyOpenGLView.h"
#import "Universe.h"


@interface GameController (FullScreenInternal)

@property (nonatomic) bool fullScreenMode;

@end


@implementation GameController (FullScreen)

- (void) setUpDisplayModes
{
}


- (IBAction) goFullscreen:(id)sender
{
	self.fullScreenMode = YES;
}


// Compatibiity wrappers.
- (void) exitFullScreenMode
{
	self.fullScreenMode = NO;
}


- (BOOL) inFullScreenMode
{
	return self.fullScreenMode;
}


- (BOOL) setDisplayWidth:(unsigned int) d_width Height:(unsigned int) d_height Refresh:(unsigned int) d_refresh
{
	return NO;
}


- (NSDictionary *) findDisplayModeForWidth:(unsigned int)d_width Height:(unsigned int)d_height Refresh:(unsigned int) d_refresh
{
	return nil;
}


- (NSArray *) displayModes
{
	return [NSArray array];
}


- (OOUInteger) indexOfCurrentDisplayMode
{
	return NSNotFound;
}


- (void) pauseFullScreenModeToPerform:(SEL)selector onTarget:(id)target
{
	[target performSelector:selector];
}

@end


@implementation GameController (FullScreenInternal)

- (bool) fullScreenMode
{
	return _fullScreen;
}


- (void) setFullScreenMode:(bool)value
{
	_fullScreen = value;
	[[NSUserDefaults standardUserDefaults] setBool:value forKey:@"fullscreen"];
}

@end


#endif
