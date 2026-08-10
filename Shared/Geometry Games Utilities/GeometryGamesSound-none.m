//	GeometryGamesSound-none.m
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#import "GeometryGamesSound.h"


//	For inclusion in Geometry Games apps that play no sounds.
//	The implementation of PlayPendingSound() avoids a link error
//	in -animationTimerFired: (on iOS) and -updateAnimation (on macOS).


void SetUpAudio(void)
{
}

void ShutDownAudio(void)
{
}

void ClearSoundCache(void)
{
}

void PlayPendingSound(void)
{
}
