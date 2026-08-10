//	GeometryGamesSound-Mac.m
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#include <Cocoa/Cocoa.h>
#include <AudioToolbox/AudioToolbox.h>	//	for MIDI player
#include <AVFoundation/AVFoundation.h>
#include "GeometryGamesSound.h"
#include "GeometryGamesUtilities-Mac-iOS.h"
#include "GeometryGamesUtilities-Common.h"


//	Maintain a global MIDI player.
MusicPlayer		gMIDIPlayer		= NULL;
MusicSequence	gMIDISequence	= NULL;

//	Play sounds?
bool			gPlaySounds		= true;	//	App delegate will override
										//		using "sound effects" user pref


static void	SetUpMIDI(void);
static void	SetUpWAV(void);
static void	ShutDownMIDI(void);
static void	ShutDownWAV(void);
static void	PlayMIDI(NSString *aFullPath);
static void	PlayWAV(NSString *aFullPath);


//	Each sound cache entry associates an NSMutableSet of AVAudioPlayers to a file name.
//	The file name includes the file extension, for example "Foo.m4a" or "Foo.wav".
static NSMutableDictionary<NSString *, NSMutableSet<AVAudioPlayer *> *>	*gCachedSoundsForAVAudioPlayer;


void SetUpAudio(void)
{
	SetUpMIDI();
	SetUpWAV();
}

static void SetUpMIDI(void)
{
	if (NewMusicPlayer(&gMIDIPlayer) != noErr)
		gMIDIPlayer = NULL;

	gMIDISequence = NULL;
	
	//	The first time a sound was played, there'd be
	//	a noticeable delay while the MIDI player got up to speed.
	//	To avoid, say, the first Maze victory sound arriving late,
	//	let's play a silent sound now to get the MIDI player warmed up.
	EnqueueSoundRequest(u"SilenceToPrestartMIDI.mid");
}

static void SetUpWAV(void)
{
	gCachedSoundsForAVAudioPlayer = [NSMutableDictionary<NSString *, NSMutableSet<AVAudioPlayer *> *>
										dictionaryWithCapacity:32];	//	will grow if necessary
}

void ShutDownAudio(void)
{
	ShutDownMIDI();
	ShutDownWAV();
}

static void ShutDownMIDI(void)
{
	if (gMIDIPlayer != NULL)
	{
		MusicPlayerStop(gMIDIPlayer);
		DisposeMusicPlayer(gMIDIPlayer);
		gMIDIPlayer = NULL;
	}
	
	if (gMIDISequence != NULL)
	{
		DisposeMusicSequence(gMIDISequence);
		gMIDISequence = NULL;
	}
}

static void ShutDownWAV(void)
{
	ClearSoundCache();
	gCachedSoundsForAVAudioPlayer = nil;
}

void ClearSoundCache(void)
{
	NSString						*theKey;
	NSMutableSet<AVAudioPlayer *>	*theAudioPlayerSet;
	AVAudioPlayer					*theAudioPlayer;
	
	for (theKey in gCachedSoundsForAVAudioPlayer)
	{
		theAudioPlayerSet = [gCachedSoundsForAVAudioPlayer objectForKey:theKey];
		for (theAudioPlayer in theAudioPlayerSet)
			[theAudioPlayer stop];
	}

	[gCachedSoundsForAVAudioPlayer removeAllObjects];
}


void PlayPendingSound(void)
{
	Char16		thePendingSoundFileName[SOUND_REQUEST_NAME_BUFFER_LENGTH];
	NSString	*theSoundFileName;

	if (DequeueSoundRequest(thePendingSoundFileName, SOUND_REQUEST_NAME_BUFFER_LENGTH))
	{
		if (gPlaySounds)
		{
			theSoundFileName = GetNSStringFromZeroTerminatedString(thePendingSoundFileName);

			//	macOS supports MIDI playback, with a built-in sound font.
			if ([theSoundFileName hasSuffix:@".m4a"])
				theSoundFileName = [[theSoundFileName stringByDeletingPathExtension] stringByAppendingString:@".mid"];

			//	The sound library might not be thread safe (in fact comments
			//	on online forums suggest that NSSound is not thread safe)
			//	so let's play sounds on the main thread only.
			//
			//	Use dispatch_async() rather than dispatch_sync()
			//	to avoid any chance of deadlock, for example if the caller
			//	holds a lock on the ModelData and the main thread
			//	is waiting for a lock on that same ModelData.
			//
			//		Performance mystery:  Even though I'm calling
			//		this code via asynchronously, it introduces
			//		a huge pause in the animation.  Just on macOS --
			//		the corresponding single-threaded iOS code is fine.
			//
			dispatch_async(dispatch_get_main_queue(),
			^{
				if ([theSoundFileName hasSuffix:@".mid"])
					PlayMIDI(theSoundFileName);
				else
				if ([theSoundFileName hasSuffix:@".wav"])
					PlayWAV(theSoundFileName);
				else
					GeometryGamesErrorMessage(u"The Geometry Games apps support only .mid and .wav files", u"Internal Error");
			});
		}
	}
}

static void PlayMIDI(NSString *aSoundFileName)
{
	NSString		*theFullPath;
	MusicSequence	theNewSequence	= NULL;

	theFullPath = [[[[NSBundle mainBundle] resourcePath]
					stringByAppendingString:@"/Sounds - midi/"]
					stringByAppendingString:aSoundFileName];

	if (gMIDIPlayer != NULL)
	{
		//	Stop any music that might already be playing.
		MusicPlayerStop(gMIDIPlayer);

		//	Create a new sequence, start it playing,
		//	and remember it so we can free it later.
		if (NewMusicSequence(&theNewSequence) == noErr)
		{
			if
			(
				MusicSequenceFileLoadData(
					theNewSequence,
					(__bridge CFDataRef) [NSData dataWithContentsOfFile:theFullPath],
					kMusicSequenceFile_MIDIType,
					0
					) == noErr
			 &&
				MusicPlayerSetSequence(gMIDIPlayer, theNewSequence) == noErr
			)
			{
				//	Start the new music playing.
				MusicPlayerStart(gMIDIPlayer);
				
				//	Destroy the old sequence and remember the new one.
				if (gMIDISequence != NULL)
					DisposeMusicSequence(gMIDISequence);
				gMIDISequence	= theNewSequence;
				theNewSequence	= NULL;
			}
			else
			{
				if (theNewSequence != NULL)
					DisposeMusicSequence(theNewSequence);
				theNewSequence = NULL;
			}
		}
	}
}

//	My original version of PlayWAV() used NSSound.
//	It worked, but it froze the main thread for several
//	tenths of a second each time it was called.
//	It also required us to keep an external strong reference
//	to the NSSound until it was done playing,
//	and then manually clear that reference.  Ugh.
//	This new version of PlayWAV() using AVAudioPlayer...
//	also freezes the main thread for several tenths
//	of a second.  Curiously, the same code works fine
//	-- with no freeze -- when running on iOS,
//	and even when running on Mac Catalyst.
//	So my inclination is not to worry about
//	the freeze in this pure macOS version of PlayWAV().
//	Clearly traditional macOS apps are about to be
//	superseded by UIKit apps (most likely to be running
//	on Apple Silicon processors in upcoming MacBooks),
//	with a migration to SwiftUI from there.
//	So as of December 2019 this pure macOS version
//	of PlayWAV() is essentially legacy code.
//
static void PlayWAV(NSString *aSoundFileName)
{
	NSMutableSet<AVAudioPlayer *>	*theAudioPlayerSet;
	AVAudioPlayer					*theAudioPlayer,
									*theAudioPlayerCandidate;
	NSString						*theFullPath;
	NSURL							*theFileURL;

	//	Does gCachedSoundsForAVAudioPlayer already
	//	contain a set of players for the requested sound?
	//	If not, create it.
	theAudioPlayerSet = [gCachedSoundsForAVAudioPlayer objectForKey:aSoundFileName];
	if (theAudioPlayerSet == nil)
	{
		theAudioPlayerSet = [NSMutableSet<AVAudioPlayer *> setWithCapacity:1];	//	Capacity will automatically increase as needed.
		[gCachedSoundsForAVAudioPlayer setObject:theAudioPlayerSet forKey:aSoundFileName];	//	Cache theAudioPlayerSet for future use.
	}
	
	//	Does theAudioPlayerSet contain an AVAudioPlayer this isn't already playing?
	//	If not, create a new one.
	theAudioPlayer = nil;
	for (theAudioPlayerCandidate in theAudioPlayerSet)
	{
		if ( ! [theAudioPlayerCandidate isPlaying] )
		{
			theAudioPlayer = theAudioPlayerCandidate;
			break;
		}
	}
	if (theAudioPlayer == nil)
	{
		theFullPath		= [[[[NSBundle mainBundle] resourcePath]
							stringByAppendingString:@"/Sounds - midi/"]	//	"Sounds - midi" also holds .wav file, just not .m4a
							stringByAppendingString:aSoundFileName];
		theFileURL		= [NSURL fileURLWithPath:theFullPath isDirectory:NO];
		theAudioPlayer	= [[AVAudioPlayer alloc] initWithContentsOfURL:theFileURL error:NULL];
		if (theAudioPlayer == nil)	//	should never occur (unless the file is missing)
			return;

		[theAudioPlayerSet addObject:theAudioPlayer];	//	Cache theAudioPlayer for future use.
	}
	
	//	Start the sound playing.
	//
	//	There's no need to call [theAudioPlayer prepareToPlay],
	//	given that we'll be calling [theAudioPlayer play] immediately anyhow.
	//
	[theAudioPlayer play];
}

