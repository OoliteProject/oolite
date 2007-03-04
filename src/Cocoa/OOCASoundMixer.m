/*

OOCASoundMixer.m

Class responsible for managing and mixing sound channels. This class is an
implementation detail. Do not use it directly; use an OOSoundSource to play an
OOSound.

OOCASound - Core Audio sound implementation for Oolite.
Copyright (C) 2005-2006 Jens Ayton

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

#import "OOCASoundInternal.h"
#import "OOCASoundChannel.h"


static NSString * const kOOLogSoundInspetorNotLoaded			= @"sound.mixer.inspector.loadFailed";
static NSString * const kOOLogSoundMixerOutOfChannels			= @"sound.mixer.outOfChannels";
static NSString * const kOOLogSoundMixerReplacingBrokenChannel	= @"sound.mixer.replacingBrokenChannel";
static NSString * const kOOLogSoundMixerFailedToConnectChannel	= @"sound.mixer.failedToConnectChannel";


@interface OOCASoundMixer(Private)

- (void)reallyRelease;
- (void)channelSoundEnded:(OOCASoundChannel *)inChannel;

- (void)pushChannel:(OOCASoundChannel *)inChannel;
- (OOCASoundChannel *)popChannel;

@end


static OOCASoundMixer *sSingleton = nil;


@implementation OOCASoundMixer

+ (OOCASoundMixer *)mixer
{
	if (nil == sSingleton)
	{
		sSingleton = [[self alloc] init];
	}
	return sSingleton;
}


- (id)init
{
	OSStatus						err = noErr;
	BOOL							OK;
	uint32_t						idx = 0, count = kMixerGeneralChannels;
	OOCASoundChannel				*temp;
	ComponentDescription			desc;
	
	if (!gOOSoundSetUp) [OOSound setUp];
	
	if (nil != sSingleton)
	{
		[super release];
	}
	else
	{
		self = [super init];
		if (nil != self)
		{
			_listLock = [[NSLock alloc] init];
			OK = nil != _listLock;
			
			if (OK)
			{
				// Create audio graph
				err = NewAUGraph(&_graph);
				
				// Add output node
				desc.componentType = kAudioUnitType_Output;
				desc.componentSubType = kAudioUnitSubType_DefaultOutput;
				desc.componentManufacturer = kAudioUnitManufacturer_Apple;
				desc.componentFlags = 0;
				desc.componentFlagsMask = 0;
				if (!err) err = AUGraphNewNode(_graph, &desc, 0, NULL, &_outputNode);
				
				// Add mixer node
				desc.componentType = kAudioUnitType_Mixer;
				desc.componentSubType = kAudioUnitSubType_StereoMixer;
				desc.componentManufacturer = kAudioUnitManufacturer_Apple;
				desc.componentFlags = 0;
				desc.componentFlagsMask = 0;
				if (!err) err = AUGraphNewNode(_graph, &desc, 0, NULL, &_mixerNode);
				
				// Connect mixer to output
				if (!err) err = AUGraphConnectNodeInput(_graph, _mixerNode, 0, _outputNode, 0);
				
				// Open the graph (turn it into concrete AUs) and extract mixer AU
				if (!err) err = AUGraphOpen(_graph);
				if (!err) err = AUGraphGetNodeInfo(_graph, _mixerNode, NULL, NULL, NULL, &_mixerUnit);
				
				if (err) OK = NO;
			}
			
			if (OK)
			{
				// Allocate channels
				do
				{
					temp = [[OOCASoundChannel alloc] initWithID:count auGraph:_graph];
					if (nil != temp)
					{
						_channels[idx++] = temp;
						[temp setNext:_freeList];
						_freeList = temp;
					}
				} while (--count);
				
				if (noErr != AUGraphInitialize(_graph)) OK = NO;
			}
			
			if (!OK)
			{
				[self reallyRelease];
				self = nil;
			}
			
			#if SUPPORT_SOUND_INSPECTOR
			if (![NSBundle loadNibNamed:@"SoundInspector" owner:self])
			{
				OOLog(kOOLogSoundInspetorNotLoaded, @"Failed to load sound inspector panel.");
			}
			#endif
		}
		sSingleton = self;
	}
	
	return sSingleton;
}


- (id)retain
{
	return self;
}


- (void)release
{
	
}


- (void)reallyRelease
{
	[super release];
}


- (id)autorelease
{
	return self;
}


+ (void)destroy
{
	if (nil != sSingleton)
	{
		[sSingleton reallyRelease];
		sSingleton = nil;
	}
}


- (void)dealloc
{
	uint32_t					idx;
	
	if (NULL != _graph)
	{
		AUGraphStop(_graph);
		AUGraphUninitialize(_graph);
		AUGraphClose(_graph);
		DisposeAUGraph(_graph);
	}
	for (idx = 0; idx != kMixerGeneralChannels; ++idx)
	{
		[_channels[idx] release];
	}
	
	[super dealloc];
}


- (void)playSound:(OOSound *)inSound
{
	BOOL						OK = YES;
	OOCASoundChannel			*chan;
	
	if (nil == inSound) return;
	
	chan = [self popChannel];
	
	if (nil != chan)
	{
		[chan setDelegate:self];
		OK = [chan playSound:inSound looped:NO];
		
		if (OK)
		{
			[inSound incrementPlayingCount];
			[self retain];
		}
		else
		{
			[self pushChannel:chan];
		}
	}
	else
	{
		OOLog(kOOLogSoundMixerOutOfChannels, @"Out of sound channels! Pretend you're hearing %@", [inSound name]);
	}
}


- (void)channel:(OOCASoundChannel *)inChannel didFinishPlayingSound:(OOSound *)inSound
{
	uint32_t				ID;
		
	[inSound decrementPlayingCount];
	
	if (![inChannel isOK])
	{
		OOLog(kOOLogSoundMixerReplacingBrokenChannel, @"Sound mixer: replacing broken channel %@.", inChannel);
		ID = [inChannel ID];
		[inChannel release];
		inChannel = [[OOCASoundChannel alloc] initWithID:ID auGraph:_graph];
	}
	
	[self pushChannel:inChannel];
}


- (void)update
{
#if SUPPORT_SOUND_INSPECTOR
	uint32_t					i;
	Float32						load;
	
	for (i = 0; i != kMixerGeneralChannels && i != 32; ++i)
	{
		[[checkBoxes cellWithTag:i] setIntValue:_playMask & (1 << i)];
	}
	
	if (_maxChannels < _activeChannels)
	{
		_maxChannels = _activeChannels;
		[maxField setIntValue:_maxChannels];
	}
	[currentField setIntValue:_activeChannels];
	
	if (!AUGraphGetCPULoad(_graph, &load))
	{
		[loadBar setDoubleValue:load];
		[loadField setObjectValue:[NSString stringWithFormat:@"%.2g%%", load * 100.0]];
	}
#endif
}


#if SUPPORT_SOUND_INSPECTOR
- (void)awakeFromNib
{
	uint32_t					i;
	
	if (nil != checkBoxes)
	{
		for (i = 0; i != kMixerGeneralChannels; ++i)
		{
			[[checkBoxes cellWithTag:i] setIntValue:0];
		}
	}
}
#endif


- (void)setMasterVolume:(float)inVolume
{
	AudioUnitSetParameter(_mixerUnit, kStereoMixerParam_Volume, kAudioUnitScope_Output, 0, inVolume, 0);
}


- (void)pushChannel:(OOCASoundChannel *)inChannel
{
	uint32_t					ID;
	
	assert(nil != inChannel);
	
	[_listLock lock];
	
	[inChannel setNext:_freeList];
	_freeList = inChannel;
	
	if (0 == --_activeChannels)
	{
		AUGraphStop(_graph);
	}
	ID = [inChannel ID] - 1;
	if (ID < 32) _playMask &= ~(1 << ID);
	[_listLock unlock];
}


- (OOCASoundChannel *)popChannel
{
	OOCASoundChannel			*result;
	uint32_t					ID;
	
	[_listLock lock];
	result = _freeList;
	_freeList = [result next];
	
	if (nil != result)
	{
		if (0 == _activeChannels++)
		{
			AUGraphStart(_graph);
		}
		
		ID = [result ID] - 1;
		if (ID < 32) _playMask |= (1 << ID);
	}
	[_listLock unlock];
	
	return result;
}


- (BOOL)connectChannel:(OOCASoundChannel *)inChannel
{
	AUNode						node;
	OSStatus					err;
	
	assert(nil != inChannel);
	
	node = [inChannel auSubGraphNode];
	err = AUGraphConnectNodeInput(_graph, node, 0, _mixerNode, [inChannel ID]);
	if (!err) err = AUGraphUpdate(_graph, NULL);
	
	if (err) OOLog(kOOLogSoundMixerFailedToConnectChannel, @"Sound mixer: failed to connect channel %@, error = %@.", inChannel, AudioErrorNSString(err));
	
	return !err;
}


- (OSStatus)disconnectChannel:(OOCASoundChannel *)inChannel
{
	OSStatus					err;
	
	assert(nil != inChannel);
	
	err = AUGraphDisconnectNodeInput(_graph, _mixerNode, [inChannel ID]);
	if (noErr == err) AUGraphUpdate(_graph, NULL);
	
	return err;
}

@end
