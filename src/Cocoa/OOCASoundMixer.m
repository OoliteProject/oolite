//	
//	OOCASoundMixer.m
//	CoreAudio sound implementation for Oolite
//	
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

#import "OOCASoundInternal.h"
#import "OOCASoundChannel.h"

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
			
			if (OK) _musicSource = [[OOSoundSource alloc] init];
			
			if (!OK)
			{
				[self reallyRelease];
				self = nil;
			}
			
			#if SUPPORT_SOUND_INSPECTOR
			if (![NSBundle loadNibNamed:@"SoundInspector" owner:self])
			{
				NSLog(@"Failed to load sound inspector panel.");
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
	[_musicSource release];
	
	[super dealloc];
}


- (void)playMusic:(OOMusic *)inMusic
{
	if (_music != inMusic)
	{
		_music = [inMusic retain];
		[_musicSource playSound:inMusic];
	}
}


- (void)stopMusic:(OOMusic *)inMusic
{
	if (_music == inMusic)
	{
		[_musicSource stop];
		[_music autorelease];
		_music = nil;
	}
}


- (OOMusic *)currentMusic
{
	return _music;
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
		OK = [chan playSound:inSound];
		
		if (OK) [self retain];
		else
		{
			[self pushChannel:chan];
		}
	}
	else
	{
		NSLog(@"Out of sound channels! Pretend you're hearing %@", [inSound name]);
	}
}


- (void)channel:(OOCASoundChannel *)inChannel didFinishPlayingSound:(OOSound *)inSound
{
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
	
	if (err) NSLog(@"OOCASoundMixer: failed to connect channel %@, error = %@.", inChannel, AudioErrorNSString(err));
	
	return !err;
}


- (void)disconnectChannel:(OOCASoundChannel *)inChannel
{
	assert(nil != inChannel);
	
	AUGraphDisconnectNodeInput(_graph, _mixerNode, [inChannel ID]);
	AUGraphUpdate(_graph, NULL);
}

@end
