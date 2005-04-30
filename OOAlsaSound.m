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
   [soundThread stopTrack: self];
   return YES;
}

- (BOOL) resume
{
   return 1;
}

- (void) dealloc
{
   [soundThread stopTrack: self];
   [super dealloc];
}

- (void) resample
{
   int i;
   int stretchSample=SAMPLERATE / _samplingRate;
   long newDataSize=_dataSize * stretchSample; 
   Frame *newBuf=(Frame *)malloc(newDataSize);
   Frame *newBufPtr=newBuf;
   const Frame *oldBuf=(const Frame *)[_data bytes];
   const Frame *oldBufPtr;
   const Frame *oldBufEnd=oldBuf+(_dataSize / sizeof(Frame));

   Sample lastChana;
   Sample lastChanb;
   Sample thisChana=0;
   Sample thisChanb=0;

   for(oldBufPtr=oldBuf; oldBufPtr < oldBufEnd; oldBufPtr ++)
   {
      // Keep the last sample value and split out the ones
      // we are looking at (or use zero if we're at the first
      // frame of the buffer). Then make a simple straight line
      // between the two to antialise the sound that's being
      // resampled.
      lastChana=thisChana;
      lastChanb=thisChanb;

      thisChana=(*oldBufPtr & 0xFFFF0000) >> 16;
      thisChanb=*oldBufPtr & 0x0000FFFF;

      short stepChana=(thisChana-lastChana) / stretchSample;
      short stepChanb=(thisChanb-lastChanb) / stretchSample;

      // we'll increment chana and chanb by the step as we
      // write them.
      short chana=lastChana;
      short chanb=lastChanb;
         
      for(i=0; i < stretchSample; i++)
      {
         *newBufPtr=chana;
         *newBufPtr <<= 16;

         // see later comment about shorts being aligned on longword
         // boundaries.
         *newBufPtr |= (chanb & 0x0000FFFF);
         chana+=stepChana;
         chanb+=stepChanb;
         newBufPtr++;
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
}

- (void)startup
{
   isPlaying=YES;
}

- (const unsigned char *)getBufferEnd;
{
   const unsigned char *buf=[_data bytes];
   buf+=_dataSize;
   return buf;
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
   // Crank up the player thread.
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


   unsigned short int silence[1024];
   memset(silence, 0, sizeof(silence));

   // Prepare/reset the PCM device for playback.
   // According to ALSA docs, just opening the device
   // implicitly prepares it, but it can't hurt to make
   // sure, especially knowing ALSA consistency...

   snd_pcm_prepare(pcm_handle);

   // do this forever
   // Note we have to play silence instead of stopping, it seems
   // to prevent problems with stalls/buffer underruns with some
   // hardware. It apparently uses more CPU to actually stop than
   // keep continously feeding the sound card.
   while(1)
   {
      int res; 
      // play it one chunk at a time.
      if([self mixChunks])
      {
         res = snd_pcm_writei(pcm_handle, chunkBuf, bufsz);
      }
      else // Nothing to play? Play silence so we don't get an underrun.
      {
         res = snd_pcm_writei(pcm_handle, silence, sizeof(silence) / 4);
      }
      // Check for errors/problems
      if (res < 0)
      {
         NSLog(@"ALSA: error during snd_pcm_writei() (%s), resetting stream.", 
               snd_strerror(res));
         snd_pcm_prepare(pcm_handle);
      }
   }

   [pool release]; 
}

// do all the initialization. The ALSA website doesn't document this
// very well but the function calls are in the main self explanatory.
- (BOOL) initAlsa
{
   int dir;
   int periods = PERIODS;
   snd_pcm_uframes_t periodsize = PERIODSIZE;
   bufsz=MIXBUFSIZE;
   
   int i;

   // init track pointers.
   for(i=0; i < MAXTRACKS; i++)
   {
      trackBuffer[i].buf=NULL;
      trackBuffer[i].bufEnd=NULL;
   }

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
   if(snd_pcm_hw_params_set_access(pcm_handle, hwparams,
                     SND_PCM_ACCESS_RW_INTERLEAVED) < 0)
   {
      NSLog(@"ALSA failed to set access");
      return NO;
   }

   // assumption...
   if(snd_pcm_hw_params_set_format(pcm_handle, hwparams,
                           SND_PCM_FORMAT_S16_LE) < 0)
   {
      NSLog(@"ALSA failed to set the format");
      return NO;
   }

   // set sample rate and channels
   int exact_rate=SAMPLERATE;
   if(snd_pcm_hw_params_set_rate_near
            (pcm_handle, hwparams, &exact_rate, &dir))
   {
      NSLog(@"ALSA can't set the rate %d", exact_rate);
      return NO;
   }
   
   if(snd_pcm_hw_params_set_channels(pcm_handle, hwparams, CHANNELS) < 0)
   {
      NSLog(@"ALSA can't set channels to %d", CHANNELS);
      return NO;
   }
  

   // TODO: find out exactly what periods are useful for.
   snd_pcm_uframes_t origPeriods=periods;
   int periodDir=0;
   if(snd_pcm_hw_params_set_periods_near
         (pcm_handle, hwparams, &periods, &periodDir) < 0)
   {
      NSLog(@"ALSA could not set periods");
      return NO;
   }
   
   // http://www.suse.de/~mana/alsa090_howto.html
   // bufsz is the size in frames not bytes
   unsigned long hwbufsz=(periods * periodsize) >> 2;
   unsigned long origbufsz=hwbufsz;

   if(origPeriods != periods)
   {
      NSLog(@"Tried to set %d periods but ended up with %d",
            origPeriods, periods);
   }

   // bufsz = buffer size in frames. fpp = frames per period.
   // We try to allocate a buffer of the number of frames per
   // period but it might not happen.
   if(snd_pcm_hw_params_set_buffer_size_near
         (pcm_handle, hwparams, &hwbufsz) < 0)
   {
      NSLog(@"ALSA could not set the buffer size to %d", hwbufsz);
      return NO;
   }

   if(hwbufsz != origbufsz)
   {
      NSLog(@"Sound card can't take a buffer of %d - using %d instead",
             origbufsz, hwbufsz);

      // If the hwbufsz is smaller than our default bufsz, downsize
      // bufsz.
      if(hwbufsz < bufsz)
         bufsz=hwbufsz;
   }

   // convert bufsz to bytes and allocate our mixer buffer.
   chunkBuf=(Frame *)malloc(bufsz * FRAMESIZE);

   if(snd_pcm_hw_params(pcm_handle, hwparams) < 0)
   {
      NSLog(@"ALSA could not set HW params");
      return NO;
   }

   return YES; 
}

// playBuffer doesn't actually do the playing - it merely adds the
// sound to the list of tracks the player thread should mix.
- (void) playBuffer: (OOSound *)sound
{
   NSLock *addlock=[[NSLock alloc] init];
   [addlock lock];
   int i;
   int slot=0;
   BOOL slotAssigned=NO;
   for(i=0; i < MAXTRACKS; i++)
   {
      if(!track[i] && !slotAssigned)
      {
         slot=i;
         slotAssigned=YES;
      }
   }
   if(!slotAssigned)
   {
      NSLog(@"No free tracks");
      return;
   }

   [sound retain];   // we don't want it unexpectedly disappearing
   track[slot]=sound;
   trackBuffer[slot].buf=(Frame *)[[sound getData] bytes];
   trackBuffer[slot].bufEnd=(Frame *)[sound getBufferEnd];
   [sound startup];
   [addlock unlock];
}

- (BOOL) mixChunks
{
   int i;
   Frame *current;

   // Check there's something to mix.
   for(i=0; i < MAXTRACKS; i++)
   {
      if(track[i])
         break;
   }
   if(i == MAXTRACKS)
   {
      // No tracks to do, exit now.
      return NO;
   }
   
   for(current=chunkBuf; current < chunkBuf + bufsz; current++)
   {
      long sumChanA=0;
      long sumChanB=0;
      for(i=0; i < MAXTRACKS; i++)
      {
         if(!trackBuffer[i].buf) continue;
         if(trackBuffer[i].buf >= trackBuffer[i].bufEnd) continue;
         sumChanA += (long)*trackBuffer[i].buf >> 16;
         sumChanB += (long)(*trackBuffer[i].buf << 16) >> 16;
         trackBuffer[i].buf++;
      }

      if(sumChanA > 32767) sumChanA=32767;
      else if(sumChanA < -32768) sumChanA=-32768;
      if(sumChanB > 32767) sumChanB=32767;
      else if(sumChanB < -32768) sumChanB=-32768;

      *current = (sumChanA << 16) | (sumChanB & 0xffff);
   }

   // drop tracks we don't want any more
   for(i=0; i < MAXTRACKS; i++)
   {
      if(trackBuffer[i].buf && trackBuffer[i].buf == trackBuffer[i].bufEnd)
      {
         [track[i] resetState];
         [track[i] release];
         track[i]=nil;
         trackBuffer[i].buf=NULL;
      }
   }
   return YES;
}

- (void) stopTrack: (OOSound *)trackToStop
{
   int i;
   for(i=0; i < MAXTRACKS; i++)
   {
      if(trackToStop == track[i])
      {
         track[i]=nil;
         trackBuffer[i].buf=NULL;
         [trackToStop resetState];
         [trackToStop release];
      }
   }
}

@end
