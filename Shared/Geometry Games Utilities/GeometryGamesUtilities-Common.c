//	GeometryGamesUtilities-Common.c
//
//	Implements functions declared in GeometryGamesUtilities-Common.h 
//	that have platform-independent implementations.
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#include "GeometryGamesUtilities-Common.h"
#include <stdio.h>
#include <string.h>
#include <math.h>	//	for floor()

#define PI	3.14159265358979323846	//	π


//	Test for memory leaks.
signed int		gMemCount		= 0;
pthread_mutex_t	gMemCountMutex	= PTHREAD_MUTEX_INITIALIZER;


static char	*CharacterAsUTF8String(Char16 aCharacter, char aBuffer[5]);


bool IsPowerOfTwo(unsigned int n)
{
	if (n == 0)
		return false;

	while ((n & 0x00000001) == 0)
		n >>= 1;

	return (n == 0x00000001);
}


bool UTF8toUTF16(	//	returns "true" upon success, "false" upon failure
	const char		*anInputStringUTF8,		//	zero-terminated UTF-8 string (BMP only -- code points 0x0000 - 0xFFFF)
	Char16			*anOutputBufferUTF16,	//	pre-allocated buffer for zero-terminated UTF-16 string
	unsigned int	anOutputBufferLength)	//	in Char16's, not bytes;  includes space for terminating zero
{
	const char		*r;	//	reading locating
	Char16			*w,	//	writing location
					c;	//	most recent character copied
	unsigned int	aNumCharactersAvailable,
					i;

	r						= anInputStringUTF8;
	w						= anOutputBufferUTF16;
	aNumCharactersAvailable	= anOutputBufferLength;
	
	do
	{
		if (*r & 0x80)	//	1-------    (part of multi-byte sequence)
		{
			if (*r & 0x40)	//	11------	(lead byte in multi-byte sequence)
			{
				if (*r & 0x20)	//	111-----	(at least 3 bytes in sequence)
				{
					if (*r & 0x10)	//	1111----	(at least 4 bytes in sequence)
						goto UTF8toUTF16Failed;	//	should never occur for 16-bit Unicode (BMP)

					//	leading byte is 1110xxxx
					//	so it's a three-byte sequence
					//	read the leading byte
					c = (*r << 12) & 0xF000;
					
					//	read the first follow-up byte
					r++;
					if ((*r & 0xC0) != 0x80)	//	must be 10xxxxxx
						goto UTF8toUTF16Failed;
					c |= ((*r << 6) & 0x0FC0);
					
					//	read the second follow-up byte
					r++;
					if ((*r & 0xC0) != 0x80)	//	must be 10xxxxxx
						goto UTF8toUTF16Failed;
					c |= (*r & 0x003F);
				}
				else	//	110-----	(lead byte in 2-byte sequence)
				{
					//	read the leading byte
					c = (*r << 6) & 0x07C0;
					
					//	read the follow-up byte as well
					r++;
					if ((*r & 0xC0) != 0x80)	//	must be 10xxxxxx
						goto UTF8toUTF16Failed;
					c |= (*r & 0x3F);
				}
				
				//	move on
				r++;
			}
			else	//	10------
			{
				//	error: unexpected trailing byte
				goto UTF8toUTF16Failed;
			}
		}
		else	//	0-------    (plain 7-bit character)
		{
			c = *r++;
		}

		if (aNumCharactersAvailable-- > 0)
			*w++ = c;
		else
			goto UTF8toUTF16Failed;

	} while (c);	//	keep going while copied character is nonzero
	
	return true;

UTF8toUTF16Failed:
	
	for (i = 0; i < anOutputBufferLength; i++)
		anOutputBufferUTF16[i] = 0;
	
	return false;
}

bool UTF16toUTF8(	//	returns "true" upon success, "false" upon failure
	const Char16	*anInputStringUTF16,	//	zero-terminated UTF-16 string (BMP only -- surrogate pairs not supported)
	char			*anOutputBufferUTF8,	//	pre-allocated buffer for zero-terminated UTF-8 string
	unsigned int	anOutputBufferLength)	//	in bytes;  includes space for terminating zero
{
	const Char16	*r;		//	reading locating
	char			*w,		//	writing location
					u[5];	//	UTF-8 encoding of current character
	unsigned int	aNumBytesAvailable,
					theNumNewBytes,
					i;

	r					= anInputStringUTF16;
	w					= anOutputBufferUTF8;
	aNumBytesAvailable	= anOutputBufferLength;
	
	while (*r != 0x0000)
	{
		if (*r >= 0xD800 && *r <= 0xDFFF)	//	part of a surrogate pair?
			goto UTF16toUTF8Failed;

		CharacterAsUTF8String(*r, u);

		theNumNewBytes = (unsigned int) strlen(u);
		if (aNumBytesAvailable < theNumNewBytes + 1)
			goto UTF16toUTF8Failed;
		strcpy(w, u);
		w					+= theNumNewBytes;
		aNumBytesAvailable	-= theNumNewBytes;

		r++;
	}
	
	if (aNumBytesAvailable < 1)
		goto UTF16toUTF8Failed;
	*w = 0;	//	terminating zero
	
	return true;

UTF16toUTF8Failed:
	
	for (i = 0; i < anOutputBufferLength; i++)
		anOutputBufferUTF8[i] = 0;

	return false;
}

static char *CharacterAsUTF8String(
	Char16	aCharacter,	//	input, a unicode character as UTF-16
	char	aBuffer[5])	//	output, the same character as UTF-8
{
	//	This cascade of cases allows for future UTF-32 compatibility.
	
	if ((aCharacter & 0x0000007F) == aCharacter)
	{
		//	aCharacter has length 0-7 bits.
		//	Write it directly as a single byte.
		aBuffer[0] = (char) aCharacter;
		aBuffer[1] = 0;
	}
	else
	if ((aCharacter & 0x000007FF) == aCharacter)
	{
		//	aCharacter has length 8-11 bits.
		//	Write it as a 2-byte sequence.
		aBuffer[0] = (char) (0xC0 | ((aCharacter >> 6) & 0x1F));
		aBuffer[1] = (char) (0x80 | ((aCharacter >> 0) & 0x3F));
		aBuffer[2] = 0;
	}
	else
	if ((aCharacter & 0x0000FFFF) == aCharacter)
	{
		//	aCharacter has length 12-16 bits.
		//	Write it as a 3-byte sequence.
		aBuffer[0] = (char) (0xE0 | ((aCharacter >> 12) & 0x0F));
		aBuffer[1] = (char) (0x80 | ((aCharacter >>  6) & 0x3F));
		aBuffer[2] = (char) (0x80 | ((aCharacter >>  0) & 0x3F));
		aBuffer[3] = 0;
	}
	else
	if ((aCharacter & 0x001FFFFF) == aCharacter)
	{
		//	aCharacter has length 17-21 bits.
		//	Write it as a 4-byte sequence.
		aBuffer[0] = (char) (0xF0 | ((aCharacter >> 18) & 0x07));
		aBuffer[1] = (char) (0x80 | ((aCharacter >> 12) & 0x3F));
		aBuffer[2] = (char) (0x80 | ((aCharacter >>  6) & 0x3F));
		aBuffer[3] = (char) (0x80 | ((aCharacter >>  0) & 0x3F));
		aBuffer[4] = 0;
	}
	else
	{
		//	aCharacter has length 22 or more bits,
		//	which is not valid Unicode.
		GEOMETRY_GAMES_ASSERT(0, "CharacterAsUTF8String() received an invalid Unicode character.  Unicode characters may not exceed 21 bits.");
	}
	
	return aBuffer;
}


size_t Strlen16(	//	returns number of Char16s, excluding terminating zero
	const Char16	*aString)	//	zero-terminated UTF-16 string
{
	const Char16	*theTerminatingZero;
	
	if (aString != NULL)
	{
		theTerminatingZero = aString;

		while (*theTerminatingZero != 0)
			theTerminatingZero++;
		
		return theTerminatingZero - aString;
	}
	else
	{
		return 0;
	}
}

bool Strcpy16(	//	Returns true if successful, false if aDstBuffer is too small.
	Char16			*aDstBuffer,	//	initial contents are ignored
	size_t			aDstBufferSize,	//	in Char16's, not in bytes
	const Char16	*aSrcString)	//	zero-terminated UTF-16 string
{
	size_t			theNumCharsAvailable;
	Char16			*w;	//	write location
	const Char16	*r;	//	read  location
	
	theNumCharsAvailable	= aDstBufferSize;
	w						= aDstBuffer;
	r						= aSrcString;
	
	while (theNumCharsAvailable-- > 0)
	{
		if ((*w++ = *r++) == 0)
			return true;
	}
	
	//	aDstBuffer wasn't big enough to accomodate aSrcString.
	//	Write a terminating zero into aDstBuffer's last position.
	if (aDstBufferSize >= 1)
		aDstBuffer[aDstBufferSize - 1] = 0;
	
	//	The Geometry Games don't pretend to fully support UTF-16 surrogate pairs,
	//	but for future robustness, let's make sure we didn't truncate
	//	the output string in the middle of a surrogate pair.
	if (aDstBufferSize >= 2							//	Buffer contains at least two Char16's?
	 && aDstBuffer[aDstBufferSize - 2] >= 0xD800	//	Last non-zero Char16 is
	 && aDstBuffer[aDstBufferSize - 2] <= 0xDBFF)	//		a widowed leading surrogate?
	{
		aDstBuffer[aDstBufferSize - 2] = 0;			//	Suppress widowed leading surrogate.
	}
	
	return false;
}

bool Strcat16(	//	Returns true if successful, false if aDstBuffer is too small.
	Char16			*aDstBuffer,	//	contains the first zero-terminated UTF-16 string
									//		plus empty space for the second
	size_t			aDstBufferSize,	//	in Char16's, not in bytes
	const Char16	*aSrcString)	//	the second zero-terminated UTF-16 string
{
	Char16	*theSubBuffer;
	size_t	theSubBufferSize;
	
	//	Locate aDstBuffer's terminating zero.
	theSubBuffer		= aDstBuffer;
	theSubBufferSize	= aDstBufferSize;
	while (theSubBufferSize > 0	//	Still something left to read?
		&& *theSubBuffer != 0)	//	If so, is it a non-trivial Char16?
	{
		theSubBufferSize--;		//	Move on to the next Char16.
		theSubBuffer++;			//
	}
	
	//	The above while() loop will terminate when either
	//
	//		theSubBufferSize == 0	(bad news)
	//	or
	//		*theSubBuffer == 0		(good news)
	//
	if (theSubBufferSize == 0)
		GeometryGamesFatalError(u"Strcat16() received aDstBuffer with no terminating zero.", u"Internal Error");

	//	We've found aDstBuffer's terminating zero.
	//	Ask Strcpy16() to copy aSrcString beginning there,
	//	and return the result.
	return Strcpy16(theSubBuffer, theSubBufferSize, aSrcString);
}

bool SameString16(
	const Char16	*aStringA,
	const Char16	*aStringB)
{
	while (true)
	{
		if (*aStringA != *aStringB)
			return false;
		
		if (*aStringA == 0)
			return true;
		
		aStringA++;
		aStringB++;
	}
}


void RandomInit(void)
{
	//	Be careful with srandomdev().  According to
	//
	//		https://kqueue.org/blog/2012/06/25/more-randomness-or-less/
	//
	//	srandomdev() will first try /dev/random, but if that fails
	//	it falls back to
	//
	//		struct timeval tv;
	//		unsigned long junk;
	//
	//		gettimeofday(&tv, NULL);
	//		srandom((getpid() << 16) ^ tv.tv_sec ^ tv.tv_usec ^ junk);
	//
	//	The kqueue.org article then goes on to explain
	//	why using uninitialized memory is a bad idea,
	//	and how in fact the LLVM compiler will optimize away that whole line!
	//	Presumably Apple has fixed this bug by now???
	
	srandomdev();
}

void RandomInitWithSeed(unsigned int aSeed)
{
	//	RandomInitWithSeed() is useful when one wants to be able
	//	to reliably reproduce a given series of random numbers.
	//	Otherwise it may be better to use RandomInit() instead.
	
	srandom(aSeed);
}

bool RandomBoolean(void)
{
	return (bool)( random() & 0x00000001 );
}

unsigned int RandomUnsignedInteger(void)
{
	return (unsigned int)random();	//	in range 0 to RAND_MAX = 0x7FFFFFFF
}

float RandomFloat(void)
{
	return (float)( (double)random() / (double)RAND_MAX );
}

double RandomGaussian(
	double	aOneSigmaValue)
{
	double	u,
			v;

	//	Use the Box-Muller transform to generate
	//	a normally distributed random variable.

	u = RandomFloat();
	do
	{
		v = RandomFloat();
	} while (v < 0.0001);	//	avoid ln(0)
	
	return aOneSigmaValue * sqrt(-2.0 * log(v)) * cos(2.0*PI*u);
}


//	Package up information for the new-thread wrapper function.

#include <pthread.h>	//	use pthread_create() on all platforms except Windows

typedef struct
{
	ModelData	*md;
	void		(*itsStartFuction)(ModelData *);
	bool		itsArgumentsHaveBeenCopied;
} ThreadStartData;

static void	*StartFunctionWrapper(void *aParam);

void StartNewThread(
	ModelData	*md,
	void		(*aStartFuction)(ModelData *))
{
	//	Put a wrapper around aStartFuction to isolate details
	//	like _cdecl vs. _stdcall from the rest of the program.
	
	ThreadStartData	theThreadStartData;
	pthread_t		theNewThreadID;	//	We'll ignore the new thread's ID.
	
	theThreadStartData.md							= md;
	theThreadStartData.itsStartFuction				= aStartFuction;
	theThreadStartData.itsArgumentsHaveBeenCopied	= false;

	pthread_create(&theNewThreadID, NULL, StartFunctionWrapper, (void *)&theThreadStartData);
	
	while ( ! theThreadStartData.itsArgumentsHaveBeenCopied )
		SleepBriefly();
}

static void *StartFunctionWrapper(void *aParam)
{
	ThreadStartData	theThreadStartData;
	
	//	Copy the input parameters to our own local memory.
	theThreadStartData = *(ThreadStartData *)aParam;
	
	//	Let the caller know we've made a copy, so it can return safely.
	((ThreadStartData *)aParam)->itsArgumentsHaveBeenCopied = true;
	
	//	Call itsStartFunction.
	//	Whatever calling convention the compiler prefers is fine by us.
	(*theThreadStartData.itsStartFuction)(theThreadStartData.md);

	return NULL;
}


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
//		only one sound per frame?  Because a the typical case
//		like the Pool break, it would be pointless to start
//		two copies of the same sound playing simultaneously.
//		That 1/60 sec delay is a feature, not a bug!
//
#define SOUND_REQUEST_QUEUE_LENGTH	8

//	Each sound name is a zero-terminated UTF-16 string.
static pthread_mutex_t	gSoundNameQueueLock = PTHREAD_MUTEX_INITIALIZER;
static Char16			gSoundNameQueue[SOUND_REQUEST_QUEUE_LENGTH][SOUND_REQUEST_NAME_BUFFER_LENGTH];
static uint32_t			gSoundNameQueueStart  = 0,
						gSoundNameQueueLength = 0;

void EnqueueSoundRequest(
	const Char16	*aSoundName)	//	zero-terminated UTF-8 string
{
	uint32_t	theFirstAvailableSlot;
	
	pthread_mutex_lock(&gSoundNameQueueLock);
	
	if (gSoundNameQueueLength > SOUND_REQUEST_QUEUE_LENGTH)	//	should never occur
		GeometryGamesFatalError(u"Impossible value for gSoundNameQueueLength", u"Internal Error");
	
	//	If the queue is full, drop the oldest sound name
	//	to allow space for the new sound name that just arrived.
	if (gSoundNameQueueLength == SOUND_REQUEST_QUEUE_LENGTH)
	{
		gSoundNameQueueStart = (gSoundNameQueueStart + 1) % SOUND_REQUEST_QUEUE_LENGTH;
		gSoundNameQueueLength--;
	}

	theFirstAvailableSlot = (gSoundNameQueueStart + gSoundNameQueueLength) % SOUND_REQUEST_QUEUE_LENGTH;
	Strcpy16(gSoundNameQueue[theFirstAvailableSlot], SOUND_REQUEST_NAME_BUFFER_LENGTH, aSoundName);
	gSoundNameQueueLength++;

	pthread_mutex_unlock(&gSoundNameQueueLock);
}

bool DequeueSoundRequest(
	Char16	*aSoundNameBuffer,		//	Receives the pending sound name, if any,
									//		as a zero-terminated UTF-16 string.
									//	This buffer will typically have enough space
									//		to hold MAX_PENDING_SOUND_NAME_LENGTH Char16's.
	size_t	aSoundNameBufferLength)	//	Length in Char16's, not bytes,
									//		including the space for the terminating zero.
{
	bool	theQueueWasNonEmpty;
	
	pthread_mutex_lock(&gSoundNameQueueLock);

	if (gSoundNameQueueLength > 0)
	{
		Strcpy16(aSoundNameBuffer, aSoundNameBufferLength, gSoundNameQueue[gSoundNameQueueStart]);
		memset(gSoundNameQueue[gSoundNameQueueStart], 0x00, sizeof(gSoundNameQueue[gSoundNameQueueStart]));	//	size in bytes, not Char16's
		gSoundNameQueueStart = (gSoundNameQueueStart + 1) % SOUND_REQUEST_QUEUE_LENGTH;
		gSoundNameQueueLength--;
		theQueueWasNonEmpty = true;
	}
	else
	{
		theQueueWasNonEmpty = false;
	}

	pthread_mutex_unlock(&gSoundNameQueueLock);

	return theQueueWasNonEmpty;
}


#include <unistd.h>		//	for usleep()

void SleepBriefly(void)
{
	//	Normally the platform-independent code doesn't sleep;
	//	it returns control to the platform-dependent UI code
	//	which manages idle time as it sees fit.  However, when
	//	the Torus Games Chess waits for its secondary thread to terminate,
	//	it needs to do something to avoid hogging CPU cycles while it waits.
	
	//	NOTE:  I'M NOT THRILLED WITH THE IDEA OF USING SleepBriefly().
	//	SOMEDAY I MAY WANT TO RE-THINK THESE QUESTIONS
	//	AND PERHAPS FIND A BETTER SOLUTION.
	
	usleep(10000);	//	10000 µs = 10 ms
}


//	Use GeometryGamesAssertionFailed for "impossible" situations that
//	the user will almost surely never encounter.  Otherwise use GeometryGamesFatalError().
noreturn void GeometryGamesAssertionFailed(
	const char		*aPathName,		//	UTF-8, but assume file name (without path) is ASCII
	unsigned int	aLineNumber,
	const char		*aFunctionName,	//	in principle UTF-8, but assume ASCII
	const char		*aDescription)	//	in principle UTF-8, but assume ASCII
{
	const char	*theLastSeparator,
				*theCharacter,
				*theFileName;
	
	//	The file name itself (without the full path) appears
	//	just after the last '/'.
	theLastSeparator = NULL;
	for (theCharacter = aPathName; *theCharacter != 0; theCharacter++)
		if (*theCharacter == '/')
			theLastSeparator = theCharacter;
	if (theLastSeparator != NULL)	//	did we find a '/' ?
		theFileName = theLastSeparator + 1;
	else
		theFileName = aPathName;
	
	//	Assume the strings are all ASCII.
	printf("\n\nGeometry Games assertion failed\n    File:      %s\n    Line:      %d\n    Function:  %s\n    Reason:    %s\n\n\n",
		theFileName, aLineNumber, aFunctionName, aDescription);
	exit(1);
}


#pragma mark -
#pragma mark error messages

//	My original intention was to use GeometryGamesFatalError() for situations
//	that the user might conceivably encounter, and GEOMETRY_GAMES_ASSERT() otherwise.
//	But in practice, the number of situations that would trigger a GeometryGamesFatalError()
//	has gotten less and less over the years, while the difficultly
//	of displaying the error message from points deep in the code
//	has increased.  So now the best thing might be just to print
//	the message to the console and exit.
void GeometryGamesFatalError(
	ErrorText	aMessage,	//	UTF-16, may be NULL
	ErrorText	aTitle)		//	UTF-16, may be NULL
{
	GeometryGamesErrorMessage(aMessage, aTitle);
	exit(1);
}

void GeometryGamesErrorMessage(
	ErrorText	aMessage,	//	UTF-16, may be NULL
	ErrorText	aTitle)		//	UTF-16, may be NULL
{
	const Char16	*theMessage,
					*theTitle,
					*theChar16;
				
	//	printf() interprets %S to specify a string of 32-bit wchar_t characters
	//	(in contrast to NSLog, which interprets it as 16-bit unichars instead).
	//	It seems printf() doesn't accommodate strings of 16-bit unichars at all,
	//	so let's print theMessage and theTitle manually.
	
	theMessage	= (aMessage != NULL ? aMessage : u"<no message>");
	theTitle	= ( aTitle  != NULL ?  aTitle  :  u"<no title>" );
	
	printf("\nGeometry Games error message:\n");
	
	for (theChar16 = theTitle; *theChar16 != 0; theChar16++)
		putchar(*theChar16);
	putchar('\n');
		
	for (theChar16 = theMessage; *theChar16 != 0; theChar16++)
		putchar(*theChar16);
	putchar('\n');

	putchar('\n');
}
