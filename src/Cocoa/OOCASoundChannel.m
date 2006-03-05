//	
//	OOCASoundChannel.m
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

#import "OOCASoundChannel.h"
#import "OOCASoundInternal.h"
#import <mach/mach.h>


static mach_port_t sReapPort = MACH_PORT_NULL;
static mach_port_t sStatusPort = MACH_PORT_NULL;
static BOOL sReaperRunning = NO;
static OOCASoundChannel_RenderIMP SoundChannelRender = NULL;

static SInt32 sDebugUnexpectedNullCount = 0;


enum
{
	kState_Stopped,
	kState_Playing,
	kState_Ended
};


#define kAURenderSelector		@selector(renderWithFlags:frames:context:data:)


@interface OOCASoundChannel(Private)

+ (void)reaperThread:junk;
- (void)cleanUp;

- (OSStatus)renderWithFlags:(AudioUnitRenderActionFlags *)ioFlags frames:(UInt32)inNumFrames context:(OOCASoundRenderContext *)ioContext data:(AudioBufferList *)ioData;

@end


enum
{
	// Port messages
	kMsgRecycleChannel			= 1UL,
	kMsgThreadUp,
	kMsgDie,
	kMsgThreadDied
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


@implementation OOCASoundChannel

+ (BOOL)setUp
{
	BOOL						OK = YES;
	PortMessage					message;
	
	if (sReaperRunning) return YES;
	
	SoundChannelRender = (OOCASoundChannel_RenderIMP)[OOCASoundChannel instanceMethodForSelector:kAURenderSelector];
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
		[NSThread detachNewThreadSelector:@selector(reaperThread:) toTarget:self withObject:nil];
		OK = PortWait(sStatusPort, &message);
		if (OK)
		{
			if (kMsgThreadUp != message.tag) OK = NO;
		}
	}
	
	if (!OK)
	{
		NSLog(@"Failed to set up sound (channel release queue allocation failed). No sound will be played.");
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
	OOCASoundChannel			*chan;
	
	sReaperRunning = YES;
	PortSend(sStatusPort, message);
	
	[NSThread setThreadPriority:0.5];
	
	for (;;)
	{
		if (PortWait(sReapPort, &message))
		{
			if (kMsgRecycleChannel == message.tag)
			{
				chan = message.value;
				[chan cleanUp];
			}
			else if (kMsgDie == message.tag)
			{
				break;
			}
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
	ComponentDescription		desc;
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
		if (!err) err = AUGraphNewNode(_subGraph, &desc, 0, NULL, &_node);
		if (!err) err = AUGraphGetNodeInfo(_subGraph, _node, NULL, NULL, NULL, &_au);
		
		// Set render callback
		input.inputProc = ChannelRenderProc;
		input.inputProcRefCon = self;
		if (!err) err = AudioUnitSetProperty(_au, kAudioUnitProperty_SetRenderCallback,
									kAudioUnitScope_Input, 0, &input, sizeof input);
		
		// Init & check errors
		if (!err) err = AudioUnitInitialize(_au);
		
		if (err)
		{
			NSLog(@"AudioUnit setup error %@.", AudioErrorNSString(err));
			
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


- (OOCASoundChannel *)next
{
	return _next;
}


- (void)setNext:(OOCASoundChannel *)inNext
{
	_next = inNext;
}


- (OOSound *)sound
{
	return _sound;
}


- (BOOL)playSound:(OOSound *)inSound
{
	BOOL						OK = YES;
	OSStatus					err = noErr;
	AudioStreamBasicDescription	format;
	OOSound						*temp;
	SInt32						unexpectedNulls;
	
	unexpectedNulls = sDebugUnexpectedNullCount;
	if (0 != unexpectedNulls)
	{
		OTAtomicAdd32(-unexpectedNulls, &sDebugUnexpectedNullCount);
		if (1 == unexpectedNulls)
		{
			NSLog(@"A NULL Render() or nil _sound error has occured.");
		}
		else
		{
			NSLog(@"%i NULL Render() or nil _sound errors have occured.", (int)unexpectedNulls);
		}
	}
	
	if (nil != inSound)
	{
		[gOOCASoundSyncLock lock];
		if (kState_Stopped != _state)
		{
			NSLog(@"Channel %@ reused while playing.", self);
			
			[[OOCASoundMixer mixer] disconnectChannel:self];
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
		
		Render = (OOCASoundChannel_RenderIMP)[inSound methodForSelector:kAURenderSelector];
		OK = (NULL != Render);
		
		if (OK) OK = [inSound getAudioStreamBasicDescription:&format];
		if (OK) OK = [inSound prepareToPlayWithContext:&_context];
		
		if (!OK)
		{
			NSLog(@"OOCASoundChannel: Failed to play sound %@ - set-up issues.", inSound);
		}
		
		if (OK)
		{
			_sound = inSound;
			
			err = AudioUnitSetProperty(_au, kAudioUnitProperty_StreamFormat,
						kAudioUnitScope_Input, 0, &format, sizeof format);
			
			if (err) NSLog(@"OOCASoundChannel: Failed to play %@ (error %@)", inSound, AudioErrorNSString(err));
			OK = !err;
		}
		
		if (OK) OK = [[OOCASoundMixer mixer] connectChannel:self];
		
		if (OK)
		{
			[_sound retain];
			_state = kState_Playing;
		}
		else
		{
			_sound = nil;
		//	if (!err) NSLog(@"OOCASoundChannel: Failed to play %@", inSound);
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


- (void)cleanUp
{
	OOSound							*sound;
	
	[gOOCASoundSyncLock lock];
	
	if (kState_Ended == _state)
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
	}
	[gOOCASoundSyncLock unlock];
}


- (NSString *)description
{
	NSString						*result, *stateString;
	
	[gOOCASoundSyncLock lock];
	switch (_state)
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
		
		default:
			stateString = [NSString stringWithFormat:@"unknown (%u)", _state];
	}
	
	result = [NSString stringWithFormat:@"<%@ %p>{ID=%u, state=%@, sound=%@}", [self className], self, _id, stateString, _sound];
	[gOOCASoundSyncLock unlock];
	
	return result;
}


- (OSStatus)renderWithFlags:(AudioUnitRenderActionFlags *)ioFlags frames:(UInt32)inNumFrames context:(OOCASoundRenderContext *)ioContext data:(AudioBufferList *)ioData
{
	OSStatus					err;
	PortMessage					message;
	
	if (__builtin_expect(_stopReq, 0)) err = endOfDataReached;
	else
	{
		if (NULL != Render && nil != _sound)
		{
			err = Render(_sound, kAURenderSelector, ioFlags, inNumFrames, &_context, ioData);
		}
		else
		{
			unsigned			i, count;
			
			err = endOfDataReached;
			count = ioData->mNumberBuffers;
			
			// Logging in real-time thread _baaaaaad_.
			if (NULL == Render)
			{
				OTAtomicAdd32(1, &sDebugUnexpectedNullCount);
				//	NSLog(@"NULL Render()! Zeroing output (%u channels).", count);
			}
			else if (nil == _sound)
			{
				OTAtomicAdd32(1, &sDebugUnexpectedNullCount);
				//	NSLog(@"nil _sound! Zeroing output (%u channels).", count);
			}
			
			for (i = 0; i != count; ++count)
			{
				bzero(ioData->mBuffers[i].mData, ioData->mBuffers[i].mDataByteSize);
			}
			*ioFlags |= kAudioUnitRenderAction_OutputIsSilence;
		}
	}
	
	if (endOfDataReached == err)
	{
		err = noErr;
		
		[[OOCASoundMixer mixer] disconnectChannel:self];
		_state = kState_Ended;
		
		message.tag = kMsgRecycleChannel;
		message.value = self;
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
		NSLog(@"Mach port creation failure: %@", KernelResultNSString(err));
		result = MACH_PORT_NULL;
	}
	
	return result;
}


static void PortSend(mach_port_t inPort, PortMessage inMessage)
{
	PortSendMsgBody				message;
	mach_msg_return_t			result;
	
	bzero(&message, sizeof message);
	
	message.header.msgh_bits = MACH_MSGH_BITS_REMOTE(MACH_MSG_TYPE_MAKE_SEND);
	message.header.msgh_size = sizeof message;
	message.header.msgh_remote_port = inPort;
	message.header.msgh_local_port = MACH_PORT_NULL;
	
	message.descCount = 1;
	
	message.message = inMessage;
	
	result = mach_msg(&message.header, MACH_SEND_MSG | MACH_SEND_TIMEOUT, sizeof message, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
	if (MACH_MSG_SUCCESS != result)
	{
		NSLog(@"Mach port transient send failure: %@", KernelResultNSString(result));
		result = mach_msg(&message.header, MACH_SEND_MSG, sizeof message, 0, MACH_PORT_NULL, 0, MACH_PORT_NULL);
		if (MACH_MSG_SUCCESS != result)
		{
			NSLog(@"Mach port send failure: %@", KernelResultNSString(result));
		}
	}
}


static BOOL PortWait(mach_port_t inPort, PortMessage *outMessage)
{
	PortWaitMsgBody				message;
	mach_msg_return_t			result;
	
	bzero(&message, sizeof message);
	
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
		if (MACH_RCV_TIMED_OUT != result) NSLog(@"Mach port receive failure: %@", KernelResultNSString(result));
	}
	
	return MACH_MSG_SUCCESS == result;
}
