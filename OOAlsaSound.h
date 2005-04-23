//
// OOALSASound.h: Interface for oolite to the Advanced Linux Sound
// Achitecture.
// Implements methods from NSSound which are used by oolite.
//
// It is a bit of a stopgap measure since the base NSSound is fine,
// well, except the gnustep_sndd (sound daemon) crashes each time
// it plays a sound, and it probably uses OSS instead of ALSA.
// We also don't want a dependency on gnustep_sndd for statically-linked
// versions of oolite.
//
// Dylan Smith, 2005-04-22
//

#import <AppKit/NSSound.h>
#import <Foundation/NSLock.h>
#include <alsa/asoundlib.h>
#include <semaphore.h>

@interface OOSound : NSSound
{
   BOOL isPlaying;
   unsigned char *playPosition;
}

- (BOOL) pause;
- (BOOL) isPlaying;
- (BOOL) play;
- (BOOL) stop;
- (BOOL) resume;

// we only do 44.1kHz so resample anything that's not. This makes
// the mixer much simpler. TODO: make the mixer better.
- (void) resample;

// accessor methods. Only OOAlsaSoundThread should be calling these.
- (NSData *)getData;
- (float)getSampleRate;
- (float)getFrameSize;
- (long)getDataSize;
- (long)getFrameCount;
- (int)getChannelCount;
- (unsigned char *)getPlayPosition;
- (unsigned char *)getBufferEnd;
- (void)setPlayPosition: (unsigned char *)pos;
- (void)resetPlayPosition;

// call startup when starting to play a sound, and resetState when
// finishing. The two methods set the pointers right to do stuff.
- (void)resetState;
- (void)startup;

@end

// Some constants. (We normalize anything sent to us to these values)
#define PERIODS      2
#define PERIODSIZE   512 
#define SAMPLERATE   44100
#define CHANNELS     2
#define MAXTRACKS    4
#define FRAMESIZE    4

// Instances of this class control a per-PCM thread that is responsible
// for controlling access to the hardware.
typedef struct _soundChunk
{
   unsigned char *buf;
   long frames;
} SoundChunk;

typedef struct _trackPointer
{
   unsigned char *bufptr;
   unsigned char *bufend;
} TrackPointer;

typedef unsigned char Sample;

@interface OOAlsaSoundThread : NSObject
{
   snd_pcm_t           *pcm_handle;
   snd_pcm_hw_params_t *hwparams;
   int fpp;
   snd_pcm_uframes_t   periodsize;
   int periods;

   // controlling semapore
   sem_t soundSem;

   // sounds to play
   OOSound *track[MAXTRACKS];
   TrackPointer tptr[MAXTRACKS];
   Sample *chunks[MAXTRACKS];
   int numChunks;
}

// init creates the thread and returns self.
- (id) init;

// soundThread is a single thread per ALSA PCM device. It should only
// ever be called once per PCM device.
- (void) soundThread: (id)obj;
- (void) stopTrack: (OOSound *)trackToStop;

// playBuffer sets up the buffer to be played and posts the semaphore
// to crank it up.
- (void) playBuffer: (OOSound *)sound;

// initAlsa sets up the device.
- (BOOL) initAlsa;

// Quite a lot of nasty stuff is done here. The implementation almost
// certainly can be improved, but I think it'll take reading the 
// ALSA library code to figure out a better way to do this.
// If you think this code is bizarre or at best baroque I quite agree!
- (BOOL) getChunkToPlay: (SoundChunk *)chunk;
- (Sample *)getSampleBuffer: (OOSound *)sound;
- (Sample *)mixChunks;

@end

static OOAlsaSoundThread *soundThread;

// a bet to self: this class is still in use 2 years from now...

