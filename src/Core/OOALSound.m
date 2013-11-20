/*

OOALSound.m

OOALSound - OpenAL sound implementation for Oolite.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOALSound.h"
#import "OOLogging.h"
#import "OOCollectionExtractors.h"
#import "OOMaths.h"
#import "OOALSoundDecoder.h"
#import "OOOpenALController.h"
#import "OOALBufferedSound.h"
#import "OOALStreamedSound.h"
#import "OOALSoundMixer.h"

#define KEY_VOLUME_CONTROL @"volume_control"

static const size_t kMaxBufferedSoundSize = 1 << 20;	// 1 MB

static BOOL	sIsSetUp = NO;
static BOOL sIsSoundOK = NO;

@implementation OOSound

+ (BOOL) setUp
{
	if (!sIsSetUp)
	{
		sIsSetUp = YES;
		OOOpenALController* controller = [OOOpenALController sharedController];
		if (controller != nil)
		{
			sIsSoundOK = YES;
			float volume = [[NSUserDefaults standardUserDefaults] oo_floatForKey:KEY_VOLUME_CONTROL defaultValue:1.0];
			[self setMasterVolume:volume];
		}
	}
	
	return sIsSoundOK;
}


+ (void) setMasterVolume:(float) fraction
{
	if (!sIsSetUp && ![self setUp])
		return;
	
	fraction = OOClamp_0_1_f(fraction);

	OOOpenALController *controller = [OOOpenALController sharedController];
	if (fraction != [controller masterVolume])
	{
		[controller setMasterVolume:fraction];
		[[NSUserDefaults standardUserDefaults] setFloat:[controller masterVolume] forKey:KEY_VOLUME_CONTROL];
	}
}


+ (float) masterVolume
{
	if (!sIsSetUp && ![self setUp] )
		return 0.0;

	OOOpenALController *controller = [OOOpenALController sharedController];
	return [controller masterVolume];
}


- (id) init
{
	if (!sIsSetUp)  [OOSound setUp];
	return [super init];
}


- (id) initWithContentsOfFile:(NSString *)path
{
	[self release];
	if (!sIsSetUp && ![OOSound setUp])  return nil;

	OOALSoundDecoder		*decoder;

	decoder = [[OOALSoundDecoder alloc] initWithPath:path];
	if (nil == decoder) return nil;
	
	if ([decoder sizeAsBuffer] <= kMaxBufferedSoundSize)
	{
		self = [[OOALBufferedSound alloc] initWithDecoder:decoder];
	}
	else
	{
		self = [[OOALStreamedSound alloc] initWithDecoder:decoder];
	}
	[decoder release];
	
	if (nil != self)
	{
		#ifndef NDEBUG
			OOLog(kOOLogSoundLoadingSuccess, @"Loaded sound %@", path);
		#endif
	}
	else
	{
		OOLog(kOOLogSoundLoadingError, @"Failed to load sound \"%@\"", path);
	}
	
	return self;


}

- (id)initWithDecoder:(OOALSoundDecoder *)inDecoder
{
	[self release];
	return nil;
}


- (NSString *)name
{
	OOLogGenericSubclassResponsibility();
	return @"";
}


+ (void) update
{
	OOSoundMixer * mixer = [OOSoundMixer sharedMixer];
	if( sIsSoundOK && mixer)
		[mixer update];
}

+ (BOOL) isSoundOK
{
  return sIsSoundOK;
}


- (ALuint) soundBuffer
{
	OOLogGenericSubclassResponsibility();
	return 0;
}


- (BOOL) soundIncomplete
{
	return NO;
}


- (void) rewind
{
	// doesn't need to do anything on seekable FDs
}

@end
