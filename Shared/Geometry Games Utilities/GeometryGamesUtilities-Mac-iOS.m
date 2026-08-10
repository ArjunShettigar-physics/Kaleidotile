//	GeometryGamesUtilities-Mac-iOS.m
//
//	Implements
//
//		functions declared in GeometryGamesUtilities-Common.h that have 
//		the same implementation on macOS and iOS,
//		but would require a different implementation on other platforms
//	and
//		all functions declared in GeometryGamesUtilities-Mac-iOS.h.
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#import "GeometryGamesUtilities-Mac-iOS.h"
#import "GeometryGamesColorSpaces.h"
#import "GeometryGamesLocalization.h"
#import <Foundation/Foundation.h>
#import <Metal/MTLDevice.h>
#import <CoreText/CoreText.h>
#import <mach/mach.h>


static ErrorText	GetPathContents(NSString *aPathName, unsigned int *aNumRawBytes, Byte **someRawBytes);
static uint32_t		BevelPixelColor(uint8_t aBaseColorRGB[3], uint32_t anImageWidthPx, uint32_t anImageHeightPx,
						uint32_t aBevelThicknessPx, uint32_t aScale, uint32_t aRow, uint32_t aCol);




unsigned int GetMaxFramebufferSizeOnDevice(
	id<MTLDevice>	aDevice)
{
	unsigned int	theMaxTextureSize;

	//	A color buffer gets created in Metal as a texture, via the call
	//
	//		[itsDevice newTextureWithDescriptor:theColorBufferDescriptor]
	//
	//	so the maximum texture size also tells the maximum framebuffer size.

	if (
//		[aDevice supportsFamily:MTLGPUFamilyApple8]		//	Apple A15 (I assume)
//	 ||
		[aDevice supportsFamily:MTLGPUFamilyApple7]		//	Apple A14
	 || [aDevice supportsFamily:MTLGPUFamilyApple6]		//	Apple A13
	 || [aDevice supportsFamily:MTLGPUFamilyApple5]		//	Apple A12
	 || [aDevice supportsFamily:MTLGPUFamilyApple4]		//	Apple A11
	 || [aDevice supportsFamily:MTLGPUFamilyApple3])	//	Apple A9, A10
	{
		theMaxTextureSize = 16384;
	}
	else
	if ([aDevice supportsFamily:MTLGPUFamilyApple2]		//	Apple A8
	 || [aDevice supportsFamily:MTLGPUFamilyApple1])	//	Apple A7
	{
		theMaxTextureSize =  8192;
	}
	else
	if ([aDevice supportsFamily:MTLGPUFamilyMac2]		//	unspecified Mac GPUs
	 || [aDevice supportsFamily:MTLGPUFamilyMac1])		//	unspecified Mac GPUs
	{
		theMaxTextureSize = 16384;
	}
	else
	if ([aDevice supportsFamily:MTLGPUFamilyMacCatalyst2]
	 || [aDevice supportsFamily:MTLGPUFamilyMacCatalyst1])
	{
		//	As of 3 November 2019, there seems to be no documentation
		//	for the Mac Catalyst GPU families.
		//	So let's just try to make a safe-ish guess,
		//	and hope for the best.
		theMaxTextureSize =  8192;	//	UNDOCUMENTED GUESS
	}
	else
	if ([aDevice supportsFamily:MTLGPUFamilyCommon3]
	 || [aDevice supportsFamily:MTLGPUFamilyCommon2]
	 || [aDevice supportsFamily:MTLGPUFamilyCommon1])
	{
		//	If we're running on something other than an Apple Silicon GPU
		//	or a standard Mac GPU, then we'll end up here.
		//	Alas as of 3 November 2019, the documentation
		//	for the three "Common" GPU families gives
		//	feature availability but no implementation limits.
		//	Again, let's take a guess and hope for the best.
		theMaxTextureSize =  8192;	//	UNDOCUMENTED GUESS
	}
	else
	{
		//	We should never get to this point,
		//	under any circumstances.
		exit(1);
	}
	
	return theMaxTextureSize;
}


CGImageRef CreateGreyscaleMaskWithString(	//	caller must free the returned CGImageRef
	const Char16	*aString,		//	null-terminated UTF-16 string
	unsigned int	aWidthPx,		//	in pixels (not points);  must be a power of two
	unsigned int	aHeightPx,		//	in pixels (not points);  must be a power of two
	const Char16	*aFontName,		//	null-terminated UTF-16 string
	unsigned int	aFontSize,		//	height in pixels, excluding descent
	unsigned int	aFontDescent,	//	vertical space below baseline, in pixels
	bool			aCenteringFlag,	//	Center the text horizontally in the texture image?
	unsigned int	aMargin,		//	If aCenteringFlag == false, what horizontal inset to use?
	ErrorText		*anError)		//	may be NULL
{
	ErrorText				theErrorMessage		= NULL;
	CGColorSpaceRef			theColorSpace		= NULL;
	CGContextRef			theBitmapContext	= NULL;
	CFStringRef				theFontName			= NULL;
	CTFontDescriptorRef		theFontDescriptor	= NULL;
	CTFontRef				theFont				= NULL;
	CFStringRef				theString			= NULL;
	CGColorRef				theTextColor		= NULL;
	CFDictionaryRef			theAttributes		= NULL;
	CFAttributedStringRef	theAttributedString	= NULL;
	CTLineRef				theLine				= NULL;
	CGFloat					theTextWidth		= 0.0,
							theOffset			= 0.0;
	CGImageRef				theImage			= NULL;
	
	//	Work in a linear grey color space.
	theColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceLinearGray);
	
	//	Create a Core Graphics bitmap context.
	//
	//		Note:  CGBitmapContextCreate() supports only
	//		certain combinations of the following parameters,
	//		as shown in the section Supported Pixel Formats
	//		(Table 2-1) of the page
	//
	//			https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/dq_context/dq_context.html
	//
	theBitmapContext = CGBitmapContextCreate(
							NULL,
							aWidthPx,
							aHeightPx,
							8,
							0,
							theColorSpace,
							(CGBitmapInfo) kCGImageAlphaNone );
	if (theBitmapContext == NULL)
	{
		theErrorMessage = u"Couldn't create theBitmapContext.";
		goto CleanUpCreateGreyscaleMaskWithString;
	}
	
	//	Clear the frame.
	//
	//		Note:  CGContextClearRect() could be replaced with code like
	//
	//			CGContextSetGrayFillColor(theBitmapContext, 0.75, 1.0);
	//			CGContextFillRect(theBitmapContext, (CGRect) { {0, 0}, {aWidthPx, aHeightPx} } );
	//
	//		if we wanted to fill the rectangle with some other shade of grey.
	//
	CGContextClearRect(theBitmapContext, (CGRect) { {0, 0}, {aWidthPx, aHeightPx} } );
	
	//	Create a CFStringRef containing the font name.
	theFontName = CFStringCreateWithCharacters(NULL, aFontName, Strlen16(aFontName));
	if (theFontName == NULL)
	{
		theErrorMessage = u"Couldn't create theFontName.";
		goto CleanUpCreateGreyscaleMaskWithString;
	}
	
	//	Create a font descriptor.
	theFontDescriptor = CTFontDescriptorCreateWithNameAndSize(theFontName, 0.0);
	if (theFontDescriptor == NULL)
	{
		theErrorMessage = u"Couldn't create theFontDescriptor.";
		goto CleanUpCreateGreyscaleMaskWithString;
	}
	
	//	Create a font.
	//	(I'm hoping that Core Text caches fonts, so it will be fast
	//	to create and release the same font over and over.)
	theFont = CTFontCreateWithFontDescriptor(theFontDescriptor, aFontSize, NULL);
	if (theFont == NULL)
	{
		theErrorMessage = u"Couldn't create theFont.";
		goto CleanUpCreateGreyscaleMaskWithString;
	}

	//	Create a CFStringRef containing the text to be rendered.
	theString = CFStringCreateWithCharacters(NULL, aString, Strlen16(aString));
	if (theString == NULL)
	{
		theErrorMessage = u"Couldn't create theString.";
		goto CleanUpCreateGreyscaleMaskWithString;
	}
	
	//	Create a white color with which to draw the text.
	theTextColor = CGColorCreate(theColorSpace, (const CGFloat [2]) {1.0, 1.0});
	if (theTextColor == NULL)
	{
		theErrorMessage = u"Couldn't create theTextColor.";
		goto CleanUpCreateGreyscaleMaskWithString;
	}

	//	Create a CFDictionaryRef specifying theFont and theTextColor.
	theAttributes = CFDictionaryCreate(
		NULL,
		(const void * [2]){kCTFontAttributeName,	kCTForegroundColorAttributeName	},
		(const void * [2]){theFont,					theTextColor					},
		2,
		&kCFTypeDictionaryKeyCallBacks,
		&kCFTypeDictionaryValueCallBacks);
	if (theAttributes == NULL)
	{
		theErrorMessage = u"Couldn't create theAttributes.";
		goto CleanUpCreateGreyscaleMaskWithString;
	}

	//	Create a CFAttributedStringRef containing the text to be rendered.
	theAttributedString = CFAttributedStringCreate(NULL, theString, theAttributes);
	if (theAttributedString == NULL)
	{
		theErrorMessage = u"Couldn't create theAttributedString.";
		goto CleanUpCreateGreyscaleMaskWithString;
	}
	
	//	Create a line of text.
	theLine = CTLineCreateWithAttributedString(theAttributedString);
	if (theLine == NULL)
	{
		theErrorMessage = u"Couldn't create theLine.";
		goto CleanUpCreateGreyscaleMaskWithString;
	}
	
	//	Center the text?  Or use a predetermined margin?
	if (aCenteringFlag)
	{
		theTextWidth = CTLineGetTypographicBounds(theLine, NULL, NULL, NULL);
		if (theTextWidth <= aWidthPx)
			theOffset = 0.5 * (aWidthPx - theTextWidth);
		else
			theOffset = 0.0;
	}
	else
	{
		theOffset = aMargin;
	}
	
	//	Draw theLine into theBitmapContext.
	CGContextSetTextPosition(theBitmapContext, theOffset, aFontDescent);
	CTLineDraw(theLine, theBitmapContext);
	
	//	Create a CGImage from the pixel data in theBitmapContext.
	theImage = CGBitmapContextCreateImage(theBitmapContext);

CleanUpCreateGreyscaleMaskWithString:

	if (theLine != NULL)
		CFRelease(theLine);

	if (theAttributedString != NULL)
		CFRelease(theAttributedString);

	if (theAttributes != NULL)
		CFRelease(theAttributes);
	
	if (theTextColor != NULL)
		CFRelease(theTextColor);

	if (theString != NULL)
		CFRelease(theString);

	if (theFont != NULL)
		CFRelease(theFont);

	if (theFontDescriptor != NULL)
		CFRelease(theFontDescriptor);

	if (theFontName != NULL)
		CFRelease(theFontName);

	CGContextRelease(theBitmapContext);	//	OK to pass NULL

	CGColorSpaceRelease(theColorSpace);	//	OK to pass NULL

	//	Report theErrorMessage, if any.
	if (anError != NULL)
		*anError = theErrorMessage;

	return theImage;
}


NSString *GetFilePath(
	const Char16	*aDirectory,	//	input,  zero-terminated UTF-16 string, may be NULL
	const Char16	*aFileName)		//	input,  zero-terminated UTF-16 string, may be NULL (?!)
{
	//	Assemble an absolute path of the form
	//
	//		<base path>/<directory name>/<file name>
	//
	//	where
	//
	//		<base path> says where the application lives,
	//			and won't be known until runtime,
	//
	//		<directory name> specifies the directory of interest,
	//			for example "Languages", "Sounds - m4a" or "Textures - low resolution".
	//
	//		<file name> specifies the particular file,
	//			for example "TorusGames-ja.txt" or "Clouds.png".

	NSString	*thePath;
	
	thePath = [[NSBundle mainBundle] resourcePath];
	if (aDirectory != NULL)
	{
		thePath = [[thePath
					stringByAppendingString:
						@"/"]
					stringByAppendingString:
						GetNSStringFromZeroTerminatedString(aDirectory)];
	}
	if (aFileName != NULL)
	{
		thePath = [[thePath
					stringByAppendingString:
						@"/"]
					stringByAppendingString:
						GetNSStringFromZeroTerminatedString(aFileName)];
	}
	
	return thePath;
}

NSURL *GetFileURL(
	const Char16	*aDirectory,	//	input,  zero-terminated UTF-16 string, may be NULL
	const Char16	*aFileName)		//	input,  zero-terminated UTF-16 string, may be NULL (?!)
{
	NSURL	*theURL;
	
	theURL = [NSURL fileURLWithPath:GetFilePath(aDirectory, aFileName)];

	return theURL;
}

ErrorText GetFileContents(
	const Char16	*aDirectory,	//	input,  zero-terminated UTF-16 string, may be NULL
	const Char16	*aFileName,		//	input,  zero-terminated UTF-16 string, may be NULL (?!)
	unsigned int	*aNumRawBytes,	//	output, the file size in bytes
	Byte			**someRawBytes)	//	output, the file's contents as raw bytes;
									//		call FreeFileContents() when no longer needed
{
	return GetPathContents(GetFilePath(aDirectory, aFileName), aNumRawBytes, someRawBytes);
}

static ErrorText GetPathContents(
	NSString		*aPathName,		//	input,  absolute path name
	unsigned int	*aNumRawBytes,	//	output, the file size in bytes
	Byte			**someRawBytes)	//	output, the file's contents as raw bytes;
									//		call FreeFileContents() when no longer needed
{
	//	Technical Note:  I had hoped that setlocale() + fopen() would
	//	let me read the file within the platform-independent part
	//	of the code, but alas on WinXP it works when aPathName 
	//	contains only ASCII characters but fails when aPathName 
	//	contains non-trivial Unicode characters, for example when
	//	I temporarily change "Textures" to "Textures日本".
	//	So I reluctantly resorted to platform-dependent code
	//	to read the file.

	NSData	*theFileContents;
	
	//	Just to be safe...
	if (aNumRawBytes == NULL || *aNumRawBytes != 0
	 || someRawBytes == NULL || *someRawBytes != NULL)
		return u"Bad input in GetPathContents()";
	
	//	Read the file.
	theFileContents = [NSData dataWithContentsOfFile:aPathName];
	if (theFileContents == nil)
		return u"Couldn't get file contents as NSData in GetPathContents()";
	
	//	Note the number of bytes.
	*aNumRawBytes = (unsigned int) [theFileContents length];
	if (*aNumRawBytes == 0)
		return u"File contains 0 bytes in GetPathContents()";

	//	Copy the data.  The caller will own this copy, and must
	//	eventually free it with a call to FreeFileContents().
	*someRawBytes = GET_MEMORY(*aNumRawBytes);
	if (*someRawBytes == NULL)
	{
		*aNumRawBytes = 0;
		return u"Couldn't allocate buffer in GetPathContents()";
	}
	[theFileContents getBytes:(void *)(*someRawBytes) length:(*aNumRawBytes)];
	
	//	Success!
	return NULL;
}

void FreeFileContents(
	unsigned int	*aNumRawBytes,	//	may be NULL
	Byte			**someRawBytes)
{
	if (aNumRawBytes != NULL)
		*aNumRawBytes = 0;

	FREE_MEMORY_SAFELY(*someRawBytes);
}


bool GetUserPrefBool(
	const Char16	*aKey)
{
	//	The program's app delegate should have already 
	//	set a default value, so aKey's value should always exist.
	return [[NSUserDefaults standardUserDefaults]
			boolForKey:GetNSStringFromZeroTerminatedString(aKey)];
}

void SetUserPrefBool(
	const Char16	*aKey,
	bool			aValue)
{
	[[NSUserDefaults standardUserDefaults]
		setBool:	aValue
		forKey:		GetNSStringFromZeroTerminatedString(aKey)];
}

int GetUserPrefInt(
	const Char16	*aKey)
{
	//	The program's app delegate should have already 
	//	set a default value, so aKey's value should always exist.
	return (int) [[NSUserDefaults standardUserDefaults]
					integerForKey:GetNSStringFromZeroTerminatedString(aKey)];
}

void SetUserPrefInt(
	const Char16	*aKey,
	int				aValue)
{
	[[NSUserDefaults standardUserDefaults]
		setInteger:	aValue
		forKey:		GetNSStringFromZeroTerminatedString(aKey)];
}

float GetUserPrefFloat(
	const Char16	*aKey)
{
	//	The program's app delegate should have already 
	//	set a default value, so aKey's value should always exist.
	return [[NSUserDefaults standardUserDefaults]
			floatForKey:GetNSStringFromZeroTerminatedString(aKey)];
}

void SetUserPrefFloat(
	const Char16	*aKey,
	float			aValue)
{
	[[NSUserDefaults standardUserDefaults]
		setFloat:	aValue
		forKey:		GetNSStringFromZeroTerminatedString(aKey)];
}

const Char16 *GetUserPrefString(	//	returns aBuffer as a convenience to the caller
	const Char16	*aKey,
	Char16			*aBuffer,
	unsigned int	aBufferLength)
{
	NSString	*theValueAsNSString;
	
	//	The program's app delegate should have already 
	//	set a default value, so aKey's value should always exist.

	theValueAsNSString = [[NSUserDefaults standardUserDefaults]
		stringForKey:GetNSStringFromZeroTerminatedString(aKey)];
	
	return GetZeroTerminatedStringFromNSString(theValueAsNSString, aBuffer, aBufferLength);
}

void SetUserPrefString(
	const Char16	*aKey,
	const Char16	*aString)	//	zero-terminated UTF-16 string
{
	[[NSUserDefaults standardUserDefaults]
		setObject:	GetNSStringFromZeroTerminatedString(aString)
		forKey:		GetNSStringFromZeroTerminatedString(aKey)	];
}


//	Functions with iOS/Mac-specific declarations.


NSString *GetPreferredLanguage(void)	//	Returns two-letter code without modifiers,
										//	for example "de", "en" or "vi".
										//	Uses an ad hoc convention for Chinese:
										//	"zs" = Mandarin in simplified  characters
										//	"zt" = Mandarin in traditional characters
{
	NSArray<NSString *>	*thePreferredLanguages;
	NSString			*thePreferredLanguage;

	//	Determine the user's default language.
	//
	//	Note #1.  preferredLocalizations determines language availability
	//	based on what localizations it finds in our program's application bundle.
	//	Thus, as a practical matter, localizing InfoPList.strings to a new language
	//	will bring that language to the system's attention.
	//	
	//	Note #2.  On macOS, one would expect preferredLocalizations to return
	//	an NSArray<NSString *> containing all localizations supported by our mainBundle
	//	and acceptable to the user, listed in order of the user's preferences.
	//	In practice, however, preferredLocalizations always returns a 1-element array,
	//	even when several acceptable languages are available.  Apple's documentation 
	//	is evasive on this question, saying only that preferredLocalizations
	//
	//		Returns one or more localizations contained in the receiver’s bundle 
	//		that the receiver uses to locate resources based on the user’s preferences.
	//
	//	Fortunately preferredLocalizations reliably returns the user's most preferred
	//	localization, from among those supported.
	//
	//	2020-07-09  Re-reading that statement, I now see that NSBundle is simply
	//	reporting the various localizations that it would use to load resources.
	//	So if an app offered
	//
	//		Resource A in {de, en, fr}
	//		Resource B in {ar, fr, ja}
	//
	//	and the user's preferred languages were (ar, fr, en),
	//	then preferredLocalizations would (I'm guessing)
	//	return {ar, fr}, because NSBundle would load
	//	Resource A in French and Resource B in Arabic.
	//	I'm guessing that ar would be listed first because
	//	the user prefers it over fr, but I haven't tested
	//	that hypothesis.
	//
	thePreferredLanguages	= [[NSBundle mainBundle] preferredLocalizations];
	thePreferredLanguage	= ([thePreferredLanguages count] > 0 ?			//	If a preferred language exists...
								[thePreferredLanguages objectAtIndex:0] :	//	...use it.
								@"en");										//	Otherwise fall back to English.

	//	Note #3.  For Chinese, the infoPlist.strings file must
	//	contain a localization for "zh-Hans" and/or "zh-Hant".
	//	If the infoPlist.strings file contained only "zh",
	//	then -preferredLocalizations would report "en", not "zh".
	//	In general, -preferredLocalizations treats "zh-Hans" and "zh-Hant"
	//	as separate languages.  If the infoPlist.strings file contained
	//	"zh-Hans" without "zh-Hant", and the user had preferred languages
	//	{zh-Hant, en, … }, then -preferredLocalizations would report "en",
	//	not "zh-Hant".  For best results, infoPlist.strings must contain
	//	localizations for both "zh-Hans" and "zh-Hant".
	//
	//		Special language codes:  To accommodate "zh-Hans" and "zh-Hant",
	//		the Geometry Games software uses the non-standard 2-letter language codes
	//
	//			zs = zh-Hans = Mandarin Chinese in simplified characters
	//			zt = zh-Hant = Mandarin Chinese in traditional characters
	//
	if ([thePreferredLanguage hasPrefix:@"zh-Hans"])
		thePreferredLanguage = @"zs";
	if ([thePreferredLanguage hasPrefix:@"zh-Hant"])
		thePreferredLanguage = @"zt";

	//	Note #4.  -preferredLocalizations seems to automatically strip off country codes.
	//	If the app contains a "pt" localization, then whenever the user prefers
	//	either "pt-BR" or "pt-PT", the system will report plain "pt".
	//
	//	Ignore any unexpected suffixes. For example, if -preferredLocalizations
	//	reported "sr-Cyrl" or "sr-Latn", at present we'd keep only "sr".
	//	Support for alternative scripts could be added later if the need arises.
	//
	if ([thePreferredLanguage length] > 2)
		thePreferredLanguage = [thePreferredLanguage substringToIndex:2];
	
	return thePreferredLanguage;
}


NSString *GetLocalizedTextAsNSString(
	const Char16	*aKey)
{
	const Char16	*theLocalizedText;
	
	theLocalizedText = GetLocalizedText(aKey);

	return GetNSStringFromZeroTerminatedString(theLocalizedText);
}

NSString *GetNSStringFromZeroTerminatedString(
	const Char16	*anInputString)	//	zero-terminated UTF-16 string;  may be NULL
{
	if (anInputString != NULL)
		return [NSString stringWithCharacters:anInputString length:Strlen16(anInputString)];
	else
		return nil;
}

Char16 *GetZeroTerminatedStringFromNSString(	//	returns anOutputBuffer as a convenience to the caller
	NSString		*anInputString,
	Char16			*anOutputBuffer,		//	will include a terminating zero
	unsigned int	anOutputBufferLength)	//	maximum number of characters (including terminating zero),
											//		not number of bytes
{
	NSUInteger	theNumCharacters;
	
	//	Insist on enough buffer space for at least one regular character plus a terminating zero.
	GEOMETRY_GAMES_ASSERT(anOutputBufferLength >= 2, "output buffer too small");
	
	//	We hope to copy all of anInputString's characters, but...
	theNumCharacters = [anInputString length];
	
	//	... if anOutputBufferLength isn't big enough,
	//	then we'll copy only as many characters as will fit,
	//	while still leaving room for a terminating zero.
	if (theNumCharacters > anOutputBufferLength - 1)
		theNumCharacters = anOutputBufferLength - 1;
	
	//	Copy the regular characters
	[anInputString getCharacters:anOutputBuffer range:(NSRange){0, theNumCharacters}];
	
	//	Append the terminating zero.
	anOutputBuffer[theNumCharacters] = 0;
	
	//	Return anOutputBuffer as a convenience to the caller.
	return anOutputBuffer;
}


Char16 ToLowerCase(
	Char16	aCharacter)
{
	NSString	*theUppercaseString,
				*theLowercaseString;

	theUppercaseString = [NSString stringWithCharacters:&aCharacter length:1];
	theLowercaseString = [theUppercaseString lowercaseString];
	
	if ([theLowercaseString length] == 1)	//	should never fail?
		return [theLowercaseString characterAtIndex:0];
	else
		return aCharacter;
}

Char16 ToUpperCase(
	Char16	aCharacter)
{
	NSString	*theLowercaseString,
				*theUppercaseString;
				
	theLowercaseString = [NSString stringWithCharacters:&aCharacter length:1];
	theUppercaseString = [theLowercaseString uppercaseString];
	
	if ([theUppercaseString length] == 1)	//	could fail for "ß" → "SS" (not "ẞ")
		return [theUppercaseString characterAtIndex:0];
	else
		return aCharacter;
}


CGImageRef CreateBevelImage(	//	caller must call CGImageRelease() to release the returned CGImage
	CGColorSpaceRef	aColorSpace,
	const float		aBaseColorRGB[3],	//	(r,g,b) in aColorSpace; each component in [0.0, 1.0]
	NSUInteger		anImageWidthPx,		//	in pixels, not points
	NSUInteger		anImageHeightPx,	//	in pixels, not points
	NSUInteger		aBevelThicknessPx,	//	in pixels, not points
	NSUInteger		aScale)
{
	NSUInteger		theNumBytesPerPixel,
					theNumBitsPerComponent,
					theNumBytesPerRow;
	CGBitmapInfo	theBitmapInfo;
	CGContextRef	theContext	= NULL;
	uint32_t		*thePixelBuffer;
	uint8_t			theBaseColorRGB[3];
	NSUInteger		thePixelCount,
					theRow,
					theCol;
	CGImageRef		theImage	= NULL;
	
	//	The scale should be 1.0, 2.0 or 3.0
	//	(and for sure never a non-integer "native scale").
	if (aScale != 1 && aScale != 2 && aScale != 3)
		return nil;

	theNumBytesPerPixel		= 4;
	theNumBitsPerComponent	= 8;
	theNumBytesPerRow		= theNumBytesPerPixel * anImageWidthPx;
	theBitmapInfo			= (	kCGImageAlphaPremultipliedLast	//	opacity is 1.0 so pre-multiplied is moot
							   | kCGBitmapByteOrder32Little);

	theContext = CGBitmapContextCreate(	NULL,
										anImageWidthPx,
										anImageHeightPx,
										theNumBitsPerComponent,
										theNumBytesPerRow,
										aColorSpace,
										theBitmapInfo);
	if (theContext == NULL)
		goto CleanUpCreateBevelImage;
	
	thePixelBuffer = (uint32_t *) CGBitmapContextGetData(theContext);
	if (thePixelBuffer == NULL)
		goto CleanUpCreateBevelImage;

	//	Convert aBaseColorRGB from floating point
	//	to unsigned integer values.
	//
	//		Note:  We could clamp to [0.0, 1.0], but
	//		instead we assume the input color components
	//		already lie in that range.
	//
	theBaseColorRGB[0] = (uint8_t) (aBaseColorRGB[0] * 255.0);
	theBaseColorRGB[1] = (uint8_t) (aBaseColorRGB[1] * 255.0);
	theBaseColorRGB[2] = (uint8_t) (aBaseColorRGB[2] * 255.0);

	//	As we pass from one row of pixels to the next,
	//	how far should we advance in the shading pattern?
	//	For consistency we define the shading pattern in terms of points:
	//
	//		The first 2 points (coming inward from any edge)
	//		form a "transition region", while the rest
	//		of the image all gets colored the same.
	//
	//	According to whether scale = 1, 2 or 3,
	//	it will take 2, 4 or 6 rows of pixels to fill
	//	the 2-point-wide transition region along each edge.
	thePixelCount = 0;
	for (theRow = 0; theRow < anImageHeightPx; theRow++)
	{
		for (theCol = 0; theCol < anImageWidthPx; theCol++)
		{
			thePixelBuffer[thePixelCount] = BevelPixelColor(
												theBaseColorRGB,
												(uint32_t) anImageWidthPx,
												(uint32_t) anImageHeightPx,
												(uint32_t) aBevelThicknessPx,
												(uint32_t) aScale,
												(uint32_t) theRow,
												(uint32_t) theCol);
			thePixelCount += 1;
		}
	}
	
	theImage = CGBitmapContextCreateImage(theContext);
	
CleanUpCreateBevelImage:

	CGContextRelease(theContext);	//	OK to pass NULL

	return theImage;	//	caller must call CGImageRelease() to release theImage
}

static uint32_t BevelPixelColor(
	uint8_t		aBaseColorRGB[3],
	uint32_t	anImageWidthPx,
	uint32_t	anImageHeightPx,
	uint32_t	aBevelThicknessPx,
	uint32_t	aScale,
	uint32_t	aRow,
	uint32_t	aCol)
{
	uint32_t	theRowRev,
				theColRev,
				t,
				theBlend,
				r,
				g,
				b,
				theBlendedColor;

	theRowRev = (anImageHeightPx - 1) - aRow;	//	row count from bottom of image
												//		(assuming top-down coordinates)
	theColRev = (anImageWidthPx  - 1) - aCol;	//	col count from right side of image

	//	Blend t parts of black (0x00) or white (0xFF)
	//	with (32 - t) parts of aBaseColor.
	
	if (aRow >= aBevelThicknessPx && theRowRev >= aBevelThicknessPx
	 && aCol >= aBevelThicknessPx && theColRev >= aBevelThicknessPx)
	{
		//	generic center region
		t			= 0;
		theBlend	= 0x00;
	}
	else
	if (aCol >= aRow && theColRev >= aRow)
	{
		//	northern quadrant, including pixels on the diagonal
		
		if (aCol == aRow || theColRev == aRow)
		{	//	diagonal
			t			= 0;
			theBlend	= 0x00;
		}
		else
		{	//	non-diagonal
			switch (aScale)
			{
				case 1:
					switch (aRow)
					{
						case 0:		t =  1;	break;
						case 1:		t =  4;	break;
						default:	t =  8;	break;
					}
					break;

				case 2:
					switch (aRow)
					{
						case 0:		t =  1;	break;
						case 1:		t =  2;	break;
						case 2:		t =  4;	break;
						case 3:		t =  6;	break;
						default:	t =  8;	break;
					}
					break;

				case 3:
					switch (aRow)
					{
						case 0:		t =  1;	break;
						case 1:		t =  2;	break;
						case 2:		t =  3;	break;
						case 3:		t =  4;	break;
						case 4:		t =  5;	break;
						case 5:		t =  7;	break;
						default:	t =  8;	break;
					}
					break;
				
				default: return 0x00000000;	//	should never occur
			}
			theBlend = 0x00;
		}
	}
	else
	if (aCol >= theRowRev && theColRev >= theRowRev)
	{
		//	southern quadrant, including pixels on the diagonal

		if (aCol == theRowRev || theColRev == theRowRev)
		{	//	diagonal
			switch (aScale)
			{
				case 1:
					switch (theRowRev)
					{
						case 0:		t =  2;	break;
						case 1:		t =  6;	break;
						default:	t = 12;	break;
					}
					break;

				case 2:
					switch (theRowRev)
					{
						case 0:		t =  2;	break;
						case 1:		t =  4;	break;
						case 2:		t =  6;	break;
						case 3:		t =  9;	break;
						default:	t = 12;	break;
					}
					break;

				case 3:
					switch (theRowRev)
					{
						case 0:		t =  2;	break;
						case 1:		t =  3;	break;
						case 2:		t =  4;	break;
						case 3:		t =  6;	break;
						case 4:		t =  8;	break;
						case 5:		t = 10;	break;
						default:	t = 12;	break;
					}
					break;
				
				default: return 0x00000000;	//	should never occur
			}
		}
		else
		{	//	non-diagonal
			switch (aScale)
			{
				case 1:
					switch (theRowRev)
					{
						case 0:		t =  2;	break;
						case 1:		t =  8;	break;
						default:	t = 16;	break;
					}
					break;
				
				case 2:
					switch (theRowRev)
					{
						case 0:		t =  2;	break;
						case 1:		t =  4;	break;
						case 2:		t =  8;	break;
						case 3:		t = 12;	break;
						default:	t = 16;	break;
					}
					break;
				
				case 3:
					switch (theRowRev)
					{
						case 0:		t =  2;	break;
						case 1:		t =  4;	break;
						case 2:		t =  6;	break;
						case 3:		t =  8;	break;
						case 4:		t = 10;	break;
						case 5:		t = 13;	break;
						default:	t = 16;	break;
					}
					break;
				
				default: return 0x00000000;	//	should never occur
			}
		}
		theBlend = 0xFF;
	}
	else
	if (aCol < aBevelThicknessPx)
	{
		//	western quadrant, excluding pixels on the diagonal
		switch (aScale)
		{
			case 1:
				switch (aCol)
				{
					case 0:		t =  1;	break;
					case 1:		t =  4;	break;
					default:	t =  8;	break;
				}
				break;

			case 2:
				switch (aCol)
				{
					case 0:		t =  1;	break;
					case 1:		t =  2;	break;
					case 2:		t =  4;	break;
					case 3:		t =  6;	break;
					default:	t =  8;	break;
				}
				break;

			case 3:
				switch (aCol)
				{
					case 0:		t =  1;	break;
					case 1:		t =  2;	break;
					case 2:		t =  3;	break;
					case 3:		t =  4;	break;
					case 4:		t =  5;	break;
					case 5:		t =  7;	break;
					default:	t =  8;	break;
				}
				break;
			
			default: return 0x00000000;	//	should never occur
		}
		theBlend = 0xFF;
	}
	else
	if (theColRev < aBevelThicknessPx)
	{
		//	eastern quadrant, excluding pixels on the diagonal
		switch (aScale)
		{
			case 1:
				switch (theColRev)
				{
					case 0:		t =  1;	break;
					case 1:		t =  4;	break;
					default:	t =  8;	break;
				}
				break;

			case 2:
				switch (theColRev)
				{
					case 0:		t =  1;	break;
					case 1:		t =  2;	break;
					case 2:		t =  4;	break;
					case 3:		t =  6;	break;
					default:	t =  8;	break;
				}
				break;

			case 3:
				switch (theColRev)
				{
					case 0:		t =  1;	break;
					case 1:		t =  2;	break;
					case 2:		t =  3;	break;
					case 3:		t =  4;	break;
					case 4:		t =  5;	break;
					case 5:		t =  7;	break;
					default:	t =  8;	break;
				}
				break;
			
			default: return 0x00000000;	//	should never occur
		}
		theBlend = 0xFF;
	}
	else
	{
		//	should never reach this point
		t			= 32;
		theBlend	= 0x00;
	}
	
	//	Compute the blended color.
	
	r = ((32 - t) * (uint32_t)(aBaseColorRGB[0])
		+    t    * theBlend)
		/ 32;

	g = ((32 - t) * (uint32_t)(aBaseColorRGB[1])
		+    t    * theBlend)
		/ 32;

	b = ((32 - t) * (uint32_t)(aBaseColorRGB[2])
		+    t    * theBlend)
		/ 32;

	theBlendedColor =
		(
			(r << 24)
		  | (g << 16)
		  | (b <<  8)
		  | 0x000000FF	//	alpha is always 0xFF here
		);

	return theBlendedColor;
}


void LogMemoryUsage(void)
{
	struct task_basic_info	theInfo;
	mach_msg_type_number_t	theSize = sizeof(theInfo);
	kern_return_t			theKernelError;
	
	if ((theKernelError = task_info(
			mach_task_self(), TASK_BASIC_INFO, (task_info_t)&theInfo, &theSize))
		== KERN_SUCCESS)
	{
		NSLog(@"resident memory = %u, virtual memory = %u\n",
				(unsigned int)theInfo.resident_size,
				(unsigned int)theInfo.virtual_size);
	}
	else
	{
		NSLog(@"task_info() failed with error %s\n",
				mach_error_string(theKernelError));
	}
}

