//
// OOALSASound.m: Interface for oolite to the Advanced Linux Sound
// Achitecture.
// Implements methods from NSSound which are used by oolite.
//
// Note: this only implements as much as oolite needs from NSSound.
// It's also a bit of a stopgap measure since GNUstep NSSound doesn't
// yet support ALSA and the sound server crashes all the time.
//
// Dylan Smith, 2005-04-22
//
#import <Foundation/NSData.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSLock.h>
#import "OOAlsaSound.h"
#include <math.h>

@implementation OOSound

- (BOOL) pause
{
   return 1;
}

- (BOOL) isPlaying
{
   return isPlaying;
}

- (BOOL) play
{
   if(!soundThread)
   {
      soundThread = [[OOAlsaSoundThread alloc] init];
   }

   // do we need to upsample?
   if(_samplingRate < SAMPLERATE)
   {
      NSLog(@"sampleRate was %f; resampling", _samplingRate);
      [self resample];
   }
   [soundThread playBuffer: self]; 
}

- (BOOL) stop
{
   NSLog(@"Stopping it");
   [soundThread stopTrack: self];
   return YES;
}

- (BOOL) resume
{
   return 1;
}

- (void) dealloc
{
   NSLog(@"deallocing sound");
   playPosition=NULL;
   [soundThread stopTrack: self];
   [super dealloc];
}

- (void) resample
{
   int i;
   int stretchSample=SAMPLERATE / _samplingRate;
   NSLog(@"Stretching sample by %d", stretchSample);
   long newDataSize=_dataSize * stretchSample; 
   unsigned char *newBuf=(unsigned char *)malloc(newDataSize);
   unsigned char *newBufPtr=newBuf;
   unsigned char *newBufEnd=newBuf + newDataSize;
   unsigned char *oldBuf=[_data bytes];
   unsigned char *oldBufPtr;
   unsigned char *oldBufEnd=oldBuf+_dataSize;

   for(oldBufPtr=oldBuf; oldBufPtr < oldBufEnd; oldBufPtr += FRAMESIZE)
   {
      for(i=0; i < stretchSample; i++)
      {
         memcpy(newBufPtr, oldBufPtr, FRAMESIZE);
         newBufPtr+=FRAMESIZE;
      }
   }
   [_data release];
   _data=[NSData dataWithBytes: newBuf length: newDataSize];
   [_data retain];
   _samplingRate=SAMPLERATE;
   _dataSize=newDataSize;
   _frameCount=newDataSize >> 2;
}

// These methods reveal the internals of the NSSound.
- (NSData *)getData
{
   return _data;
}

// Float!? Surely an integer Mr. Stallman!
- (float)getSampleRate
{
   return _samplingRate;
}

- (float)getFrameSize
{
   return _frameSize;
}

- (long)getDataSize
{
   return _dataSize;
}

- (long)getFrameCount
{
   return _frameCount;
}

- (int)getChannelCount
{
   return _channelCount;
}

- (void)resetState
{
   isPlaying=NO;
   playPosition=NULL;
}

- (void)startup
{
   isPlaying=YES;
   playPosition=[_data bytes];
}

- (unsigned char *)getPlayPosition
{
   return playPosition;
}

- (unsigned char *)getBufferEnd;
{
   unsigned char *buf=[_data bytes];
   buf+=_dataSize;
   return buf;
}

- (void)setPlayPosition: (unsigned char *)pos
{
   playPosition=pos;
}

- (void)resetPlayPosition
{
   playPosition = [_data bytes];
}

@end

// Now here comes the really yucky stuff.
// Some of this may not be strictly necesary, but the ALSA documentation
// is truly abysmal. If you know ALSA better and can make a better
// implementation of this I won't feel insulted, trust me :-) In fact
// I think I might be a little bit relieved.
@implementation OOAlsaSoundThread

- (id)init
{
   // all we need to do is initialize the semaphore and crank the
   // player thread up. It's the equivalent of starting the sound
   // daemon. (Start it with a count of zero so sem_wait waits)
   sem_init(&soundSem, 0, 0);
   [NSThread detachNewThreadSelector:@selector(soundThread:)
                           toTarget:self
                           withObject: nil];
   return self;
}

- (void)soundThread: (id)obj
{
   NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
   if(![self initAlsa])
   {
      NSLog(@"initAlsa returned NO, sound thread aborting");
      return;
   }

   // do this forever
   while(1)
   { 
      // wait for the semaphore count to become nonzero.
      // When the count is nonzero, the thread gets resumed and the
      // semaphore count gets decremented.
      sem_wait(&soundSem);
    
      // finally we get to try and play it.
      NSLog(@"Playing it");

      snd_pcm_prepare(pcm_handle);
  
      // play it one chunk at a time.
      SoundChunk chunk;
      while([self getChunkToPlay: &chunk])
      {
         snd_pcm_writei(pcm_handle, chunk.buf, chunk.frames);
      }
      free(chunk.buf);
      snd_pcm_drain(pcm_handle);
   }

   [pool release]; 
}

// do all the initialization. The ALSA website doesn't document this
// very well but the function calls are in the main self explanatory.
- (BOOL) initAlsa
{
   int dir;
   periods=PERIODS;
   periodsize=PERIODSIZE;
   fpp=(periodsize * periods) >> 2;

   snd_pcm_stream_t stream = SND_PCM_STREAM_PLAYBACK;
  
   // init the PCM name. TODO: perhaps load this from a config plist?
   // wanna get it working first...
   char *pcm_name=strdup("default");
   snd_pcm_hw_params_alloca(&hwparams);

   // open it up
   if(snd_pcm_open(&pcm_handle, pcm_name, stream, 0) < 0)
   {
      NSLog(@"ALSA failed to initialize %s", pcm_name);
      return NO;
   }

   if(snd_pcm_hw_params_any(pcm_handle, hwparams) < 0)
   {
      NSLog(@"ALSA cannot configure PCM device");
      return NO;
   }  
   
   // TODO: investigate mmaped access
   NSLog(@"Setting access");
   if(snd_pcm_hw_params_set_access(pcm_handle, hwparams,
                     SND_PCM_ACCESS_RW_INTERLEAVED) < 0)
   {
      NSLog(@"ALSA failed to set access");
      return NO;
   }

   // assumption...
   NSLog(@"Setting format");
   if(snd_pcm_hw_params_set_format(pcm_handle, hwparams,
                           SND_PCM_FORMAT_S16_LE) < 0)
   {
      NSLog(@"ALSA failed to set the format");
      return NO;
   }

   // set sample rate and channels
   int exact_rate=SAMPLERATE;
   NSLog(@"Setting rate to %d", exact_rate);
   if(snd_pcm_hw_params_set_rate_near
            (pcm_handle, hwparams, &exact_rate, &dir))
   {
      NSLog(@"ALSA can't set the rate %d", exact_rate);
      return NO;
   }
   
   NSLog(@"Setting channels to %d", CHANNELS);
   if(snd_pcm_hw_params_set_channels(pcm_handle, hwparams, CHANNELS) < 0)
   {
      NSLog(@"ALSA can't set channels to %d", CHANNELS);
      return NO;
   }
  

   // TODO: find out exactly what periods are useful for.
   if(snd_pcm_hw_params_set_periods(pcm_handle, hwparams, periods, 0) < 0)
   {
      NSLog(@"ALSA could not set periods");
      return NO;
   }
   NSLog(@"Setting buffer size");
   if(snd_pcm_hw_params_set_buffer_size
         (pcm_handle, hwparams, fpp) < 0)
   {
      NSLog(@"ALSA could not set the buffer size to %d", fpp);
      return NO;
   }

   NSLog(@"Setting hw params");
   if(snd_pcm_hw_params(pcm_handle, hwparams) < 0)
   {
      NSLog(@"ALSA could not set HW params");
      return NO;
   }

   return YES; 
}

// playBuffer adds a buffer to our list of things to play and
// posts the semaphore so the player thread gets to work.
- (void) playBuffer: (OOSound *)sound
{
   NSLock *addlock=[[NSLock alloc] init];
   [addlock lock];
   [sound retain];   // we don't want it unexpectedly disappearing
   int i;
   int slot=0;
   BOOL slotAssigned=NO;
   for(i=0; i < MAXTRACKS; i++)
   {
      if(track[i] == sound)
      {
         NSLog(@"Already playing, aborting");
         return;
      }

      if(!track[i] && !slotAssigned)
      {
         NSLog(@"assigning track %d", i);
         slot=i;
         slotAssigned=YES;
      }
   }
   if(!slotAssigned)
   {
      NSLog(@"No free tracks");
      return;
   }

   NSLog(@"Putting sound in slot %d", slot);
   track[slot]=sound;
   [sound startup];

   // only post if we're actually waiting otherwise the mixer
   // takes care of adding the noise.
   int semval;
   sem_getvalue(&soundSem, &semval);
   if(!semval)
   {
      sem_post(&soundSem);
   }
   [addlock unlock];
}

- (BOOL) getChunkToPlay: (SoundChunk *)chunk
{
   Sample *sbuf;
   int i;
   int chunki=0;
   int numRelease=0;
   int releasei[MAXTRACKS];
   BOOL rv=NO;
   
   for(i=0; i<MAXTRACKS; i++)
   {
      if(track[i])
      {
         sbuf=[self getSampleBuffer: track[i]];
         if(sbuf)
         {
            rv=YES;
            chunks[chunki]=sbuf;
            chunki++;
         }
         else
         {
            [track[i] resetState];
            releasei[numRelease]=i;
            numRelease++;
         }
      }
   }

   numChunks=chunki;
   chunk->buf=(unsigned char *)[self mixChunks];
   chunk->frames=(PERIODSIZE * PERIODS) >> 2;

   for(i=0; i < numRelease; i++)
   {
      int tidx=releasei[i];
      [track[tidx] release];
      track[tidx]=nil;
   }
   return rv;
}
            
- (Sample *) getSampleBuffer: (OOSound *)sound
{
   unsigned char *position=[sound getPlayPosition];
   unsigned char *end=[sound getBufferEnd];
   if(position >= end)
   {
      return NULL;
   }

   long bufsz=PERIODSIZE * PERIODS;
   Sample *sbuf=(Sample *)malloc(bufsz);
   memset(sbuf, 0, bufsz);

   long copyBytes=bufsz;
   long bytesLeft=end-position;
   if(copyBytes > bytesLeft)
      copyBytes=bytesLeft;

   memcpy(sbuf, position, copyBytes);
   [sound setPlayPosition: position+copyBytes];
   return sbuf;
}

- (Sample *) mixChunks
{
   int i;
   long bufsz=PERIODSIZE * PERIODS;
   Sample *trackPtr[MAXTRACKS];
   for(i=0; i < numChunks; i++)
   {
      trackPtr[i]=chunks[i];
   }
   
   Sample *chunkBuf=(Sample *)malloc(bufsz);
   Sample *current;
   
   for(current=chunkBuf; current < chunkBuf+bufsz; current+=FRAMESIZE)
   {
      short chana;
      short chanb;
      short sumChanA=0;
      short sumChanB=0;
      for(i=0; i < numChunks; i++)
      {
         memcpy(&chana, trackPtr[i], sizeof(short));
         memcpy(&chanb, trackPtr[i]+sizeof(short), sizeof(short));
         trackPtr[i]+=sizeof(short) * 2;
         sumChanA+=chana >> 1;
         sumChanB+=chanb >> 1;
      }
      memcpy(current, &sumChanA, sizeof(short));
      memcpy(current+sizeof(short), &sumChanB, sizeof(short)); 
         
   }

   // free chunks
   for(i=0; i<numChunks; i++)
   {
      free(chunks[i]);
   }

   return chunkBuf;
}

- (void) stopTrack: (OOSound *)trackToStop
{
   int i;
   for(i=0; i < MAXTRACKS; i++)
   {
      if(trackToStop == track[i])
      {
         track[i]=nil;
         [trackToStop resetState];
      }
   }
}

@end
