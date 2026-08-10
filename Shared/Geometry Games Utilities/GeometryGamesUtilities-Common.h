//	GeometryGamesUtilities-Common.h
//
//	Declares Geometry Games types and functions with platform-independent declarations.
//	The file GeometryGamesUtilities-Common.c implements 
//	the functions whose implementation is platform-independent.
//	The files GeometryGamesUtilities-iOS|Mac|….c implement 
//	the functions whose implementation is platform-dependent.
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#pragma once

#include "GeometryGames-Common.h"
#include <stdnoreturn.h>
#include <pthread.h>


//	Define GET_MEMORY and FREE_MEMORY macros to manage memory so
//	that in future we can easily change memory allocation schemes.
//	Use a variable gMemCount to test for memory leaks.
//	Define FREE_MEMORY_SAFELY() to test for and set NULL pointers.
//
//		Note:  macOS apps render in a separate thread, so for sure
//		we must ensure that their access to gMemCount is threadsafe.
//		iOS apps render in the main thread, but even there we
//		sometimes spawn worker threads, for example to select
//		a move in the Torus Chess game.  So either way we want
//		to protect access to gMemCount with a mutex.
//
#define GET_MEMORY(n)			(											\
									pthread_mutex_lock(&gMemCountMutex),	\
									gMemCount++,							\
									pthread_mutex_unlock(&gMemCountMutex),	\
									malloc(n)								\
								)
#define FREE_MEMORY(p)			(											\
									pthread_mutex_lock(&gMemCountMutex),	\
									gMemCount--,							\
									pthread_mutex_unlock(&gMemCountMutex),	\
									free(p)									\
								)
#define RESIZE_MEMORY(p,n)		(realloc(p,n))
#define FREE_MEMORY_SAFELY(p)	{if ((p) != NULL) {FREE_MEMORY(p); (p) = NULL;}}

extern signed int		gMemCount;
extern pthread_mutex_t	gMemCountMutex;


//	Assertions
//
//		The "do {} while (0)" construction is an ugly but
//		nevertheless standard trick to write an expression
//		that will work with or without a semi-colon afterwards.
//		Some such trick is needed to handle code like
//
//			if (foo)
//				GEOMETRY_GAMES_ASSERT(…, …);
//			else
//				…
//
//	Note:  A call to the built-in assert() function would also work here,
//	but it wouldn't display the description.
//
#define GEOMETRY_GAMES_ASSERT(statement, description)									\
	do																					\
	{																					\
		if (!(statement))																\
			GeometryGamesAssertionFailed(__FILE__, __LINE__, __func__, description);	\
	} while (0)

//	GEOMETRY_GAMES_ABORT() lets Xcode's static analyzer
//	see directly GeometryGamesAssertionFailed() is a "noreturn" function.
#define GEOMETRY_GAMES_ABORT(description)												\
	GeometryGamesAssertionFailed(__FILE__, __LINE__, __func__, description)

//	Maximum number of UTF-16 characters in a sound file name,
//	including the terminating zero.
#define SOUND_REQUEST_NAME_BUFFER_LENGTH	256


//	Logically it would work fine to pass "true" or "false" 
//	to request anisotropic texture filtering or not,
//	but the enum values AnisotropicOn and AnisotropicOff
//	make the code more readable.
typedef enum
{
	AnisotropicOff,
	AnisotropicOn
} AnisotropicMode;

//	GreyscaleOn and GreyscaleOff make clearer code than "true" and "false".
typedef enum
{
	GreyscaleOff,
	GreyscaleOn
} GreyscaleMode;

//	Most textures will be RGBA, but a few will be alpha-only.
typedef enum
{
	TextureRGBA,
	TextureAlpha
} TextureFormat;


//	Functions with platform-independent implementations
//	appear in GeometryGamesUtilities-Common.c.

extern bool				IsPowerOfTwo(unsigned int n);
extern bool				UTF8toUTF16(const char	*aInputStringUTF8, Char16 *anOutputBufferUTF16, unsigned int anOutputBufferLength);
extern bool				UTF16toUTF8(const Char16 *anInputStringUTF16, char *anOutputBufferUTF8, unsigned int anOutputBufferLength);
extern size_t			Strlen16(const Char16 *aString);
extern bool				Strcpy16(Char16 *aDstBuffer, size_t aDstBufferSize, const Char16 *aSrcString);
extern bool				Strcat16(Char16 *aDstBuffer, size_t aDstBufferSize, const Char16 *aSrcString);
extern bool				SameString16(const Char16 *aStringA, const Char16 *aStringB);

extern void				RandomInit(void);
extern void				RandomInitWithSeed(unsigned int aSeed);
extern bool				RandomBoolean(void);
extern unsigned int		RandomUnsignedInteger(void);
extern float			RandomFloat(void);
extern double			RandomGaussian(double aOneSigmaValue);

extern void				EnqueueSoundRequest(const Char16 *aSoundName);
extern bool				DequeueSoundRequest(Char16 *aSoundNameBuffer, size_t aSoundNameBufferLength);

extern ErrorText		GetFileContents(const Char16 *aDirectory, const Char16 *aFileName, unsigned int *aNumRawBytes, Byte **someRawBytes);
extern void				FreeFileContents(unsigned int *aNumRawBytes, Byte **someRawBytes);

extern bool				GetUserPrefBool(const Char16 *aKey);
extern void				SetUserPrefBool(const Char16 *aKey, bool aValue);
extern int				GetUserPrefInt(const Char16 *aKey);
extern void				SetUserPrefInt(const Char16 *aKey, int aValue);
extern float			GetUserPrefFloat(const Char16 *aKey);
extern void				SetUserPrefFloat(const Char16 *aKey, float aValue);
extern const Char16		*GetUserPrefString(const Char16 *aKey, Char16 *aBuffer, unsigned int aBufferLength);
extern void				SetUserPrefString(const Char16 *aKey, const Char16 *aString);

extern void				StartNewThread(ModelData *md, void (*aStartFuction)(ModelData *));
extern void				SleepBriefly(void);

extern void				GeometryGamesFatalError(ErrorText aMessage, ErrorText aTitle);
extern void				GeometryGamesErrorMessage(ErrorText aMessage, ErrorText aTitle);
extern noreturn void	GeometryGamesAssertionFailed(const char *aPathName, unsigned int aLineNumber, const char *aFunctionName, const char *aDescription);

//	Functions with platform-dependent implementations appear
//	in GeometryGamesUtilities-*.c/.m

extern Char16			ToLowerCase(Char16 aCharacter);
extern Char16			ToUpperCase(Char16 aCharacter);
