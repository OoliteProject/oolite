/*

OOCASoundChannel.m


OOCASound - Core Audio sound implementation for Oolite.
Copyright (C) 2005-2013 Jens Ayton

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

*/

#import "OOCASoundChannel.h"
#import "OOCASoundInternal.h"
#import <mach/mach.h>
#import <pthread.h>
#import "NSThreadOOExtensions.h"


static NSString * const kOOLogSoundNULLError			= @"sound.render.undexpectedNull";
static NSString * const kOOLogSoundBadStateError		= @"sound.render.badState";
static NSString * const kOOLogSoundPlaySuccess			= @"sound.play.success";
static NSString * const kOOLogSoundBadReuse				= @"sound.play.failed.badReuse";
static NSString * const kOOLogSoundSetupFailed			= @"sound.play.failed.setupFailed";
static NSString * const kOOLogSoundPlayAUError			= @"sound.play.failed.auError";
static NSString * const kOOLogSoundPlayUnknownError		= @"sound.play.failed";
static NSString * const kOOLogSoundCleanUpSuccess		= @"sound.channel.cleanup.success";
static NSString * const kOOLogSoundCleanUpBroken		= @"sound.channel.cleanup.failed.broken";
static NSString * const kOOLogSoundCleanUpBadState		= @"sound.channel.cleanup.failed.badState";
static NSString * const kOOLogSoundMachPortError		= @"sound.channel.machPortError";


#ifndef NDEBUG
// Tracks a kind of error that isn’t happening any more.
#define COUNT_NULLS					1
#endif


static mach_port_t					sReapPort = MACH_PORT_NULL;
static mach_port_t					sStatusPort = MACH_PORT_NULL;
static BOOL							sReaperRunning = NO;
static OOSoundChannel_RenderIMP		SoundChannelRender = NULL;

#if COUNT_NULLS
static int32_t						sDebugUnexpectedNullCount = 0;
#endif

/*
	When a channel finishes playing, it is put in the “play thread dead list.” At the end of each
	sound callback, if the play thread dead list is not empty and the reap queue mutex can be
	acquired, the play thread dead list is copied to the reap queue under the mutex. This allows us
	to use a mutex-protected list to communicate with the reap queue without having to wait on the
	mutex in the real-time thread.
*/
static OOSoundChannel				*sPlayThreadDeadList = NULL;
static OOSoundChannel				*sReapQueue = NULL;
static pthread_mutex_t				sReapQueueMutex = { 0 };

typedef enum
{
	kState_Stopped,
	kState_Playing,
	kState_Ended,
	kState_Reap,
	
	kState_Broken
} States;


#define kAURenderSelector		@selector(renderWithFlags:frames:context:data:)


@interface OOSoundChannel(Private)

+ (void)reaperThread:junk;

- (void)reap;
- (void)cleanUp;

- (OSStatus)renderWithFlags:(AudioUnitRenderActionFlags *)ioFlags frames:(UInt32)inNumFrames context:(OOCASoundRenderContext *)ioContext data:(AudioBufferList *)ioData;

@end


enum
{
	// Port messages
	kMsgThreadUp				= 1UL,
	kMsgDie,
	kMsgThreadDied,
	kMsgWakeUp
};


typedef struct
{
	uintptr_t					tag;
	void						*value;
} PortMessage;


typedef struct
{
	mach_msg_header_t			header;
	mach_msg_size_t				descCount;
	mach_msg_descriptor_t		descriptor;
	PortMessage					message;
} PortSendMsgBody;


typedef struct
{
	mach_msg_header_t			header;
	mach_msg_size_t				descCount;
	mach_msg_descriptor_t		descriptor;
	PortMessage					message;
	mach_msg_trailer_t			trailer;
} PortWaitMsgBody;


static OSStatus ChannelRenderProc(void *inRefCon, AudioUnitRenderActionFlags *ioFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumFrames, AudioBufferList *ioData);

static mach_port_t CreatePort(void);
static void PortSend(mach_port_t inPort, PortMessage inMessage);
static BOOL PortWait(mach_port_t inPort, PortMessage *outMessage);


@implementation OOSoundChannel

+ (BOOL)setUp
{
	BOOL						OK = YES;
	PortMessage					message;
	
	if (sReaperRunning) return YES;
	
	SoundChannelRender = (OOSoundChannel_RenderIMP)[OOSoundChannel instanceMethodForSelector:kAURenderSelector];
	if (NULL == SoundChannelRender) OK = NO;
	
	if (OK)
	{
		sReapPort = CreatePort();
		if (MACH_PORT_NULL == sReapPort) OK = NO;
	}
	
	if (OK)
	{
		sStatusPort = CreatePort();
		if (MACH_PORT_NULL == sStatusPort) OK = NO;
	}
	
	if (OK)
	{
		if (0 != pthread_mutex_init(&sReapQueueMutex, NULL)) OK = NO;
	}
	
	if (OK)
	{
		[NSThread detachNewThreadSelector:@selector(reaperThread:) toTarget:self withObject:nil];
		OK = PortWait(sStatusPort, &message);
		if (OK)
		{
			if (kMsgThreadUp != message.tag) OK = NO;
		}
	}
	
	if (!OK)
	{
		OOLog(kOOLogSoundInitError, @"Failed to set up sound (channel queue allocation failed). No sound will be played.");
	}
	return OK;
}


+ (void)tearDown
{
	ipc_space_t					task;
	PortMessage					message = { kMsgDie, NULL };
	
	if (sReaperRunning)
	{
		PortSend(sReapPort, message);
		PortWait(sStatusPort, &message);
	}
	
	task = mach_task_self();
	if (MACH_PORT_NULL != sReapPort) mach_port_destroy(task, sReapPort);
	if (MACH_PORT_NULL != sStatusPort) mach_port_destroy(task, sStatusPort);
}


+ (void)reaperThread:junk
{
	PortMessage					message = { kMsgThreadUp, NULL };
	OOSoundChannel				*chan;
	NSAutoreleasePool			*pool = nil;
	
	[NSThread ooSetCurrentThreadName:@"OOSoundChannel reaper thread"];
	sReaperRunning = YES;
	PortSend(sStatusPort, message);
	
	[NSThread setThreadPriority:0.5];
	
	for (;;)
	{
		if (PortWait(sReapPort, &message))
		{
			pool = [[NSAutoreleasePool alloc] init];
			
			if (kMsgWakeUp == message.tag)
			{
				assert (!pthread_mutex_lock(&sReapQueueMutex));
				
				while (sReapQueue)
				{
					chan = sReapQueue;
					sReapQueue = chan->_next;
					if (kState_Reap == chan->_state) [chan reap];
					[chan cleanUp];
				}
				
				pthread_mutex_unlock(&sReapQueueMutex);
			}
			else if (kMsgDie == message.tag)
			{
				[pool release];
				break;
			}
			
			[pool release];
		}
	}
	
	message.tag = kMsgThreadDied;
	message.value = NULL;
	sReaperRunning = NO;
	PortSend(sStatusPort, message);
}


- (id)init
{
	[self release];
	return nil;
}


- (id)initWithID:(uint32_t)inID auGraph:(AUGraph)inGraph
{
	OSStatus					err = noErr;
	AudioComponentDescription	desc;
	AURenderCallbackStruct		input;
	
	assert(sReaperRunning);
	
	self = [super init];
	if (nil != self)
	{
		_id = inID;
		
		// Create a subgraph (since we can’t have multiple output units otherwise)
		err = AUGraphNewNodeSubGraph(inGraph, &_subGraphNode);
		if (!err) err = AUGraphGetNodeInfoSubGraph(inGraph, _subGraphNode, &_subGraph);
		
		// Create an output unit
		desc.componentType = kAudioUnitType_Output;
		desc.componentSubType = kAudioUnitSubType_GenericOutput;
		desc.componentManufacturer = kAudioUnitManufacturer_Apple;
		desc.componentFlags = 0;
		desc.componentFlagsMask = 0;
		if (!err) err = AUGraphAddNode(_subGraph, &desc, &_node);
		if (!err) err = AUGraphNodeInfo(_subGraph, _node, NULL, &_au);
		
		// Set render callback
		input.inputProc = ChannelRenderProc;
		input.inputProcRefCon = self;
		if (!err) err = AudioUnitSetProperty(_au, kAudioUnitProperty_SetRenderCallback,
									kAudioUnitScope_Input, 0, &input, sizeof input);
		
		// Init & check errors
		if (!err) err = AudioUnitInitialize(_au);
		
		if (err)
		{
			OOLog(kOOLogSoundInitError, @"AudioUnit setup error %@ preparing channel ID %u.", AudioErrorNSString(err), inID);
			
			[self release];
			self = nil;
		}
	}
	
	return self;
}


- (void)dealloc
{
	[self stop];
	if (NULL != _au) CloseComponent(_au);
	
	[super dealloc];
}


- (void)setDelegate:(id)inDelegate
{
	_delegate = inDelegate;
}


- (uint32_t)ID
{
	return _id;
}


- (AUNode)auSubGraphNode
{
	return _subGraphNode;
}


- (OOSoundChannel *)next
{
	return _next;
}


- (void)setNext:(OOSoundChannel *)inNext
{
	_next = inNext;
}


- (OOSound *)sound
{
	return _sound;
}


- (BOOL)playSound:(OOSound *)inSound looped:(BOOL)inLooped
{
	BOOL						OK = YES;
	OSStatus					err = noErr;
	AudioStreamBasicDescription	format;
	OOSound						*temp;
	
#if COUNT_NULLS
	SInt32						unexpectedNulls;
	
	unexpectedNulls = sDebugUnexpectedNullCount;
	if (0 != unexpectedNulls)
	{
		OSAtomicAdd32(-unexpectedNulls, &sDebugUnexpectedNullCount);
		OOLog(kOOLogSoundNULLError, @"%u NULL Render() or nil _sound errors have occured.", (unsigned int)unexpectedNulls);
	}
#endif
	
	if (nil != inSound)
	{
		[gOOCASoundSyncLock lock];
		if (kState_Stopped != _state)
		{
			OOLog(kOOLogSoundBadReuse, @"Channel %@ reused while playing.", self);
			
			[[OOSoundMixer sharedMixer] disconnectChannel:self];
			if (_sound)
			{
				Render = NULL;
				temp = _sound;
				_sound = nil;
				[temp finishStoppingWithContext:_context];
				_context = 0;
				[temp release];
			}
			_stopReq = NO;
			_state = kState_Stopped;
		}
		
		Render = (OOSoundChannel_RenderIMP)[inSound methodForSelector:kAURenderSelector];
		OK = (NULL != Render);
		
		if (OK) OK = [inSound getAudioStreamBasicDescription:&format];
		if (OK) OK = [inSound prepareToPlayWithContext:&_context looped:inLooped];
		
		if (!OK)
		{
			OOLog(kOOLogSoundSetupFailed, @"Failed to play sound %@ - set-up failed.", inSound);
		}
		
		if (OK)
		{
			_sound = inSound;
			
			err = AudioUnitSetProperty(_au, kAudioUnitProperty_StreamFormat,
						kAudioUnitScope_Input, 0, &format, sizeof format);
			
			if (err) OOLog(kOOLogSoundPlayAUError, @"Failed to play %@ (error %@)", inSound, AudioErrorNSString(err));
			OK = !err;
		}
		
		if (OK) OK = [[OOSoundMixer sharedMixer] connectChannel:self];
		
		if (OK)
		{
			[_sound retain];
			_state = kState_Playing;
			OOLog(kOOLogSoundPlaySuccess, @"Playing sound %@", _sound);
		}
		else
		{
			_sound = nil;
			if (!err) OOLog(kOOLogSoundPlayUnknownError, @"Failed to play %@", inSound);
		}
		[gOOCASoundSyncLock unlock];
	}
	
	return OK;
}


- (void)stop
{
	if (kState_Playing == _state)
	{
		_stopReq = YES;
	}
	
	if (kState_Ended == _state) [self cleanUp];
}


- (void)reap
{
	OSStatus						err;
	
	err = [[OOSoundMixer sharedMixer] disconnectChannel:self];
	
	if (noErr == err)
	{
		_state = kState_Ended;
	}
	else
	{
		_state = kState_Broken;
		_error = err;
	}
}


- (void)cleanUp
{
	OOSound							*sound;
	
	[gOOCASoundSyncLock lock];
	
	if (kState_Broken == _state)
	{
		OOLog(kOOLogSoundCleanUpBroken, @"Sound channel %@ broke with error %@.", self, AudioErrorNSString(_error));
	}
	
	if (kState_Ended == _state || kState_Broken == _state)
	{
		Render = NULL;
		sound = _sound;
		_sound = nil;
		[sound finishStoppingWithContext:_context];
		_context = 0;
		
		_state = kState_Stopped;
		_stopReq = NO;
		
		if (nil != _delegate && [_delegate respondsToSelector:@selector(channel:didFinishPlayingSound:)])
		{
			[_delegate channel:self didFinishPlayingSound:sound];
		}
		[sound release];
		
		OOLog(kOOLogSoundCleanUpSuccess, @"Sound channel id %u cleaned up successfully.", _id);
	}
	else
	{
		OOLog(kOOLogSoundCleanUpBadState, @"Sound channel %@ cleaned up in invalid state %u.", self, _state);
	}
	
	[gOOCASoundSyncLock unlock];
}


- (BOOL)isOK
{
	return kState_Broken != _state;
}


#ifndef NDEBUG
- (OOCASoundDebugMonitorChannelState) soundInspectorState
{
	switch ((States)_state)
	{
		case kState_Stopped:
			return kOOCADebugStateIdle;
			
		case kState_Playing:
			return kOOCADebugStatePlaying;
			
		case kState_Ended:
		case kState_Reap:
		case kState_Broken:
			return kOOCADebugStateOther;
	}
	
	return kOOCADebugStateOther;
}
#endif


- (NSString *)description
{
	NSString						*result, *stateString = nil;
	
	[gOOCASoundSyncLock lock];
	switch ((States)_state)
	{
		case kState_Stopped:
			stateString = @"stopped";
			break;
		
		case kState_Playing:
			stateString = @"playing";
			break;
			
		case kState_Ended:
			stateString = @"ended";
			break;
			
		case kState_Reap:
			stateString = @"waiting to be reaped";
			break;
		
		case kState_Broken:
			stateString = [NSString stringWithFormat:@"broken (%@)", AudioErrorShortNSString(_error)];
			break;
	}
	if (stateString == nil)
	{
		stateString = [NSString stringWithFormat:@"unknown (%u)", _state];
	}
	
	result = [NSString stringWithFormat:@"<%@ %p>{ID=%u, state=%@, sound=%@}", [self className], self, _id, stateString, _sound];
	[gOOCASoundSyncLock unlock];
	
	return result;
}


- (OSStatus)renderWithFlags:(AudioUnitRenderActionFlags *)ioFlags frames:(UInt32)inNumFrames context:(OOCASoundRenderContext *)ioContext data:(AudioBufferList *)ioData
{
	OSStatus					err = noErr;
	PortMessage					message;
	BOOL						renderSilence = NO;
	
	if (EXPECT_NOT(_stopReq)) err = endOfDataReached;
	else if (EXPECT(kState_Playing == _state))
	{
		if (NULL != Render && nil != _sound)
		{
			err = Render(_sound, kAURenderSelector, ioFlags, inNumFrames, &_context, ioData);
		}
		else
		{
			err = endOfDataReached;
			renderSilence = YES;
			
#if COUNT_NULLS
			// Logging in real-time thread _baaaaaad_.
			if (NULL == Render || nil == _sound)
			{
				OSAtomicAdd32(1, &sDebugUnexpectedNullCount);
			}
#endif
		}
	}
	else
	{
		renderSilence = YES;
	}
	
	if (EXPECT_NOT(renderSilence))
	{
		unsigned			i, count = ioData->mNumberBuffers;
		
		for (i = 0; i != count; i++)
		{
			memset(ioData->mBuffers[i].mData, 0, ioData->mBuffers[i].mDataByteSize);
		}
		*ioFlags |= kAudioUnitRenderAction_OutputIsSilence;
	}
	
	if (EXPECT_NOT(endOfDataReached == err))
	{
		err = noErr;
		if (EXPECT(kState_Playing == _state))
		{
			_state = kState_Reap;
			
			_next = sPlayThreadDeadList;
			sPlayThreadDeadList = self;
		}
	}
	
	if (EXPECT_NOT(nil != sPlayThreadDeadList && !pthread_mutex_trylock(&sReapQueueMutex)))
	{
		// Put sPlayThreadDeadList at front of sReapQueue
		OOSoundChannel		*curr;
		
		curr = sPlayThreadDeadList;
		while (nil != curr->_next) curr = curr->_next;
		
		curr->_next = sReapQueue;
		sReapQueue = sPlayThreadDeadList;
		sPlayThreadDeadList = nil;
		
		pthread_mutex_unlock(&sReapQueueMutex);
		
		// Wake up reaper thread
		message.tag = kMsgWakeUp;
		message.value = NULL;
		PortSend(sReapPort, message);
	}
	
	return err;
}

@end


static OSStatus ChannelRenderProc(void *inRefCon, AudioUnitRenderActionFlags *ioFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumFrames, AudioBufferList *ioData)
{
	return SoundChannelRender((id)inRefCon, kAURenderSelector, ioFlags, inNumFrames, 0, ioData);
}


static mach_port_t CreatePort(void)
{
	kern_return_t				err;
	mach_port_t					result;
	ipc_space_t					task;
	mach_msg_type_name_t		type;
	mach_port_t					sendRight;
	
	task = mach_task_self();
	err = mach_port_allocate(task, MACH_PORT_RIGHT_RECEIVE, &result);
	if (KERN_SUCCESS == err) err = mach_port_insert_right(task, result, result, MACH_MSG_TYPE_MAKE_SEND);
	if (KERN_SUCCESS == err) err = mach_port_extract_right(task, result, MACH_MSG_TYPE_MAKE_SEND, &sendRight, &type);
	
	if (KERN_SUCCESS != err)
	{
		OOLog(kOOLogSoundInitError, @"Mach port creation failure: %@", KernelResultNSString(err));
		result = MACH_PORT_NULL;
	}
	
	return result;
}


static void PortSend(mach_port_t inPort, PortMessage inMessage)
{
	PortSendMsgBody				message;
	mach_msg_return_t			result;
	
	memset(&message, 0, sizeof message);
	
	message.header.msgh_bits = MACH_MSGH_BITS_REMOTE(MACH_MSG_TYPE_MAKE_SEND);
	message.header.msgh_size = sizeof message;
	message.header.msgh_remote_port = inPort;
	message.header.msgh_local_port = MACH_PORT_NULL;
	
	message.descCount = 1;
	
	message.message = inMessage;
	
	result = mach_msg(&message.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT, sizeof message, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
	if (MACH_MSG_SUCCESS != result)
	{
		OOLog(kOOLogSoundMachPortError, @"Mach port transient send failure: %@", KernelResultNSString(result));
		result = mach_msg(&message.header, MACH_SEND_MSG, sizeof message, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
		if (MACH_MSG_SUCCESS != result)
		{
			OOLog(kOOLogSoundMachPortError, @"Mach port send failure: %@", KernelResultNSString(result));
		}
	}
}


static BOOL PortWait(mach_port_t inPort, PortMessage *outMessage)
{
	PortWaitMsgBody				message;
	mach_msg_return_t			result;
	
	memset(&message, 0, sizeof message);
	
	message.header.msgh_bits = MACH_MSGH_BITS_LOCAL(MACH_MSG_TYPE_COPY_RECEIVE);
	message.header.msgh_size = sizeof message;
	message.header.msgh_local_port = inPort;
	
	result = mach_msg_receive(&message.header);
	if (MACH_MSG_SUCCESS == result)
	{
		if (NULL != outMessage) *outMessage = message.message;
	}
	else
	{
		if (MACH_RCV_TIMED_OUT != result) OOLog(kOOLogSoundMachPortError, @"Mach port receive failure: %@", KernelResultNSString(result));
	}
	
	return MACH_MSG_SUCCESS == result;
}
