/*

OOOpenALController.h

Singleton controller for Open AL interfaces

Oolite
Copyright (C) 2004-2013 Giles C Williams and contributors

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

#import "OOOpenAL.h"


static NSString * const kOOLogSoundInitError		= @"sound.initialization.error";
static NSString * const kOOLogSoundLoadingSuccess	= @"sound.load.success";
static NSString * const kOOLogSoundLoadingError		= @"sound.load.error";


@interface OOOpenALController : NSObject 
{
@private
	ALCdevice *device;
	ALCcontext *context;
}
 
+ (OOOpenALController *) sharedController;

- (void) setMasterVolume:(ALfloat) fraction;
- (ALfloat) masterVolume;

- (void) shutdown;

@end
