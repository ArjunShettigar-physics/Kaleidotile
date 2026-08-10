//	GeometryGamesSound.h
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#include "GeometryGames-Common.h"	//	for bool


//	Enable sound effects?
extern bool	gPlaySounds;

extern void	SetUpAudio(void);
extern void	ShutDownAudio(void);

extern void	PlayPendingSound(void);

extern void	ClearSoundCache(void);	//	non-MIDI sounds only
