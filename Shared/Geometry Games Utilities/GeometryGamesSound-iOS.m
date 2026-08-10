//	GeometryGamesSound-iOS.m
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#import "GeometryGamesSound.h"
#import "GeometryGamesUtilities-Common.h"
#import "GeometryGamesUtilities-Mac-iOS.h"
#import <AVFoundation/AVFoundation.h>


#define SILENT_SOUND_INTERVAL	1.0		//	in seconds


//	Design note:
//
//	Often the user interface will call EnqueueSoundRequest() when a sound
//	is already playing (either the same sound or a different one).
//	The best approach is let the already-playing sounds keep playing,
//	and play the new sound along with them.  The sounds sound good,
//	and the animation flows smoothly.  For example, in the Torus Games
//	Pool game, you get a smooth break with satisfying click-click-click
//	sound effects as the ball hit each other.
//
//	By contast, when I had previously tried calls like
//		[theAudioPlayer setCurrentTime:0.0];
//	or
//		[theAudioPlayer stop];
//	they stalled the system for several tenths of a second,
//	leading to noticeable hesistations in the animation.


//	Play sounds?
bool	gPlaySounds	= true;	//	App delegate will override using "sound effects" user pref

//	Each sound cache entry associates an NSMutableSet of AVAudioPlayers to a file name.
//	The file name includes the file extension, for example "Foo.m4a" or "Foo.wav".
static NSMutableDictionary<NSString *, NSMutableSet<AVAudioPlayer *> *>	*gCachedSoundsForAVAudioPlayer;


void SetUpAudio(void)
{
	//	SetUpAudio() presently sets up an AVAudioSession (which can play M4A), not a MIDI player.
	//	If iOS ever supports MIDI with no need for a custom sound font, we can switch over.

	AVAudioSession	*theAudioSession;

	theAudioSession = [AVAudioSession sharedInstance];	//	Implicitly initializes the audio session.
	[theAudioSession setCategory:AVAudioSessionCategoryAmbient error:NULL];	//	Never interrupt background music.
	[theAudioSession setActive:YES error:NULL];			//	Unnecessary but recommended.

	gCachedSoundsForAVAudioPlayer = [NSMutableDictionary<NSString *, NSMutableSet<AVAudioPlayer *> *>
										dictionaryWithCapacity:32];	//	will grow if necessary
}

void ShutDownAudio(void)
{
	//	Never gets called (by design).
	//	But if it did get called, we'd want to stop all sounds
	//	and release the cache dictionary.
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
	Char16							thePendingSoundFileName[SOUND_REQUEST_NAME_BUFFER_LENGTH];
	NSString						*theSoundFileName;
	NSMutableSet<AVAudioPlayer *>	*theAudioPlayerSet;
	AVAudioPlayer					*theAudioPlayer,
									*theAudioPlayerCandidate;
	NSString						*theFullPath;
	NSURL							*theFileURL;

	if (DequeueSoundRequest(thePendingSoundFileName, SOUND_REQUEST_NAME_BUFFER_LENGTH))
	{
		//	If the user has disabled sound effects, don't play the sound.
		if ( ! gPlaySounds )
			return;

		//	If background music is playing, don't play the sound.
		if ([[AVAudioSession sharedInstance] secondaryAudioShouldBeSilencedHint])
			return;

		//	Convert the sound file name from a zero-terminated UTF-16 string to an NSString.
		theSoundFileName = GetNSStringFromZeroTerminatedString(thePendingSoundFileName);

		//	AVMIDIPlayer supports MIDI playback, but with no built-in instruments on iOS --
		//	we'd need to provide our own "sound bank" file (SoundFont2 or DLS).
		//	So on iOS let's instead replace each each MIDI file
		//	with an equivalent M4A file, prepared in advance.
		if ([theSoundFileName hasSuffix:@".mid"])
			theSoundFileName = [[theSoundFileName stringByDeletingPathExtension] stringByAppendingString:@".m4a"];

		//	Does gCachedSoundsForAVAudioPlayer already
		//	contain a set of players for the requested sound?
		//	If not, create it.
		theAudioPlayerSet = [gCachedSoundsForAVAudioPlayer objectForKey:theSoundFileName];
		if (theAudioPlayerSet == nil)
		{
			theAudioPlayerSet = [NSMutableSet<AVAudioPlayer *> setWithCapacity:1];	//	Capacity will automatically increase as needed.
			[gCachedSoundsForAVAudioPlayer setObject:theAudioPlayerSet forKey:theSoundFileName];	//	Cache theAudioPlayerSet for future use.
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
								stringByAppendingString:@"/Sounds - m4a/"]
								stringByAppendingString:theSoundFileName];
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
}
