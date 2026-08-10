//	GeometryGamesUtilities-Mac-iOS.h
//
//	Declares Geometry Games functions with the same implementation on macOS and iOS.
//	The file GeometryGamesUtilities-Mac-iOS.c implements these functions.
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#pragma once

#import "GeometryGames-Common.h"
#import <CoreImage/CoreImage.h>
#import <simd/simd.h>	//	for simd_float4x4
#import <Metal/Metal.h>


__attribute__((annotate("returns_localized_nsstring"))) static inline NSString
	*LocalizationNotNeeded(NSString *aString)
	{return aString;}


extern unsigned int		GetMaxFramebufferSizeOnDevice(id<MTLDevice> aDevice);

extern CGImageRef		CreateGreyscaleMaskWithString(const Char16 *aString,
							unsigned int aWidthPx, unsigned int aHeightPx,
							const Char16 *aFontName, unsigned int aFontSize, unsigned int aFontDescent,
							bool aCenteringFlag, unsigned int aMargin, ErrorText *anError);

extern NSString			*GetFilePath(const Char16 *aDirectory, const Char16 *aFileName);
extern NSURL			*GetFileURL(const Char16 *aDirectory, const Char16 *aFileName);

extern NSString			*GetPreferredLanguage(void);
extern NSString			*GetLocalizedTextAsNSString(const Char16 *aKey) __attribute__((annotate("returns_localized_nsstring")));
extern NSString			*GetNSStringFromZeroTerminatedString(const Char16 *anInputString);
extern Char16			*GetZeroTerminatedStringFromNSString(NSString *anInputString, Char16 *anOutputBuffer, unsigned int anOutputBufferLength);

extern CGImageRef		CreateBevelImage(CGColorSpaceRef aColorSpace, const float aBaseColorRGB[3],
							NSUInteger anImageWidthPx, NSUInteger anImageHeightPx, NSUInteger aBevelThicknessPx, NSUInteger aScale);

extern void				LogMemoryUsage(void);
