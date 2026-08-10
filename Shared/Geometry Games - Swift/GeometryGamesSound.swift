//	GeometryGamesSound.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import Foundation
import AVFoundation


//	Play sounds?
var gPlaySounds: Bool = UserDefaults.standard.bool(forKey: "sound effects") {
	didSet {
		UserDefaults.standard.set(gPlaySounds, forKey: "sound effects")
	}
}

//	Thread safety
//
//		AVAudioPlayer's documentation doesn't say whether it's thread-safe or not.
//		But either way, the Geometry Games apps call the following functions
//		from the main thread only.  Given that we're going with single-threaded
//		operation, there's no harm in using the following global variables.
//

//	Each sound cache entry associates an array of AVAudioPlayers to a file name.
//	The file name includes the file extension, for example "Foo.m4a" or "Foo.wav".
var gCachedSoundsForAVAudioPlayer: [String: [AVAudioPlayer]] = [:]

//	The various games can enqueue sound requests whenever they want,
//	but the platform-specific user interface code dequeues a sound request
//	and starts it playing only once per frame (meaning roughly 60 to 90
//	times per second).  We want to let several sound requests queue up
//	(so, for example, in a Pool game the player will hear multiple "clicks"
//	on the break), but we don't want to let too many sound requests pile up,
//	because each sound should either get played within a tenth of a second
//	or so from when it was requested, or get forgotten.  In practice
//	a queue length of 8 works well.
//
//		Note:  Why does the user interface code dequeue
//		only one sound per frame?  Because in a typical case
//		like the Pool break, it would be pointless to start
//		two copies of the same sound playing simultaneously.
//		That 1/60 sec delay is a feature, not a bug!
//
let gSoundRequestQueueMaxLength = 8
var gSoundRequestQueue: [String] = []	//	queue of sound file names


#if os(iOS)

//	Has setUpAudio() been called?
var gAudioHasBeenSetUp = false

func setUpAudio() {

	if gAudioHasBeenSetUp {
		return
	}

	//	The call to sharedInstance() implicitly initializes the audio session.
	let theAudioSession = AVAudioSession.sharedInstance()

	do {
		//	Never interrupt background music.
		try theAudioSession.setCategory(AVAudioSession.Category.ambient)
	}
	catch {
		//	Well... I guess we just push on without having set the Category.
	}

	do {
		try theAudioSession.setActive(true)	//	Unnecessary but recommended.
	}
	catch {
		//	Well... I guess we just push on without having set the Active status.
	}

	gAudioHasBeenSetUp = true
}

func shutDownAudio() {

	//	Never gets called (by design). But if it did get called,
	//	we'd want to stop all sounds and clear the sound cache.

	stopAllSoundsAndClearSoundCache()
}

func stopAllSoundsAndClearSoundCache() {

	for theDictionaryEntry in gCachedSoundsForAVAudioPlayer {
		let theAudioPlayerArray = theDictionaryEntry.value
		for theAudioPlayer in theAudioPlayerArray {
			theAudioPlayer.stop()
		}
	}

	gCachedSoundsForAVAudioPlayer.removeAll()
}

#endif // os(iOS)

func enqueueSoundRequest(
	_ soundFileName: String
) {
	//	The Geometry Games apps may submit sound requests
	//	from any thread.  For example, in the Torus Games
	//	the Chess game's "thinking thread" may submit
	//	a sound request.  A mutable Array is not thread-safe,
	//	so always let the main thread add the sound request to the queue.
	
	precondition(
		gSoundRequestQueue.count <= gSoundRequestQueueMaxLength,
		"Internal error: impossibly many requests on gSoundRequestQueue")
	
	//	If gSoundRequestQueue has already reached
	//	it maximum length, silently delete the oldest request.
	if gSoundRequestQueue.count == gSoundRequestQueueMaxLength {
		gSoundRequestQueue.removeFirst()
	}
	
	//	Append the new soundName to the end of the queue.
	gSoundRequestQueue.append(soundFileName)
}
	
func playPendingSound() {

#if os(iOS)
	if !gAudioHasBeenSetUp {	//	should never occur
		return
	}
#endif
	
	if gSoundRequestQueue.count > 0 {
	
		let theSoundFileName = gSoundRequestQueue.removeFirst()
	
		//	Even if the user has disabled sound effects,
		//	we still want to keep dequeueing sound requests,
		//	but we don't want to play them.
		if !gPlaySounds {
			return
		}

#if os(iOS)
		//	If background music is playing, don't play the sound.
		if AVAudioSession.sharedInstance().secondaryAudioShouldBeSilencedHint {
			return
		}
#endif

		//	Does gCachedSoundsForAVAudioPlayer already contain an array
		//	of AVAudioPlayers for the requested sound?  If not, create one.
		var theAudioPlayerArray
			= gCachedSoundsForAVAudioPlayer[theSoundFileName] ?? [AVAudioPlayer]()
		
		//	Does theAudioPlayerArray contain an AVAudioPlayer that isn't already playing?
		//	If not, create a new one.
		var thePossibleAudioPlayer: AVAudioPlayer?	//	will soon be guaranteed non-nil
		for theAudioPlayerCandidate in theAudioPlayerArray {
			if !theAudioPlayerCandidate.isPlaying {
				thePossibleAudioPlayer = theAudioPlayerCandidate
				break
			}
		}
		if thePossibleAudioPlayer == nil {
		
			guard let theFullPath = Bundle.main.resourcePath?
										.appending("/Sounds/")
										.appending(theSoundFileName) else {
				return
			}
			let theFileURL = URL(fileURLWithPath: theFullPath, isDirectory: false)
			do {
				let theFileExists = (try? theFileURL.checkResourceIsReachable()) ?? false
				if !theFileExists {
					assertionFailure("playPendingSound() can't find the requested file at url \(theFileURL)")
					return
				}
				
				let theNewAudioPlayer = try AVAudioPlayer(contentsOf: theFileURL)

				//	Use theNewAudioPlayer now...
				thePossibleAudioPlayer = theNewAudioPlayer

				//	... and cache it for future use.
				//
				//		Caution:  A Swift Array is a struct, not a class,
				//		so it gets passed by value.  Thus we must re-insert
				//		theAudioPlayerArray into the gCachedSoundsForAVAudioPlayer
				//		after we append theNewAudioPlayer, otherwise
				//		theNewAudioPlayer would be lost.
				//
				theAudioPlayerArray.append(theNewAudioPlayer)
				gCachedSoundsForAVAudioPlayer[theSoundFileName] = theAudioPlayerArray
			}
			catch {
				return	//	Should never occur
			}
		}

		//	Start the sound playing.
		//
		//	There's no need to call theAudioPlayer.prepareToPlay,
		//	given that we'll be calling theAudioPlayer.play immediately anyhow.
		//
		guard let theAudioPlayer = thePossibleAudioPlayer else {
			assertionFailure("Impossible error: thePossibleAudioPlayer = nil")
			return
		}
		
		//	gCachedSoundsForAVAudioPlayer keeps a strong reference
		//	to theAudioPlayer, so it's OK to start it playing and return.
		//	(Without that strong reference, the app would crash.)
		theAudioPlayer.play()
	}
}
