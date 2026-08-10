//	GeometryGamesBevelImage-iOS.m
//
//	© 2021 by Jeff Weeks
//	See TermsOfUse.txt

#import "GeometryGamesBevelImage-iOS.h"
#import "GeometryGamesUtilities-Common.h"
#import "GeometryGamesUtilities-Mac-iOS.h"


UIImage *StretchableBevelImage(
	const float		aBaseColor[3],		//	{r,g,b}, with components in range [0.0, 1.0]
	unsigned int	aBevelThicknessPt,	//	in points, not pixels
	double			aScale,				//	= [[UIScreen mainScreen] scale] = 1.0, 2.0 or 3.0,
										//		but never equals a non-integer "native scale"
	UIDisplayGamut	aGamut)
{
	CGColorSpaceRef	theColorSpaceRef		= NULL;
	unsigned int	theImageSizePt			= 0,
					theImageSizePx			= 0,
					theBevelThicknessPx		= 0;
	CGImageRef		theCGImageRef			= NULL;
	UIImage			*theUnstretchableImage	= nil;
	UIImage			*theStretchableImage	= nil;	//	Initialized to nil in case we return early.

	//	aScale should be 1.0, 2.0 or 3.0.  Never a non-integer "native scale".
	if (aScale != floor(aScale))
		goto CleanUpStretchableBevelImage;

	//	Create an appropriate CGColorSpaceRef.
	switch (aGamut)
	{
		case UIDisplayGamutP3:
			theColorSpaceRef = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
			break;
		
		case UIDisplayGamutSRGB:
		case UIDisplayGamutUnspecified:
			theColorSpaceRef = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
			break;
		
		default:
			GEOMETRY_GAMES_ABORT("unrecognized UIDisplayGamut value");
	}
	if (theColorSpaceRef == NULL)
		goto CleanUpStretchableBevelImage;

	//	Create an image that's almost all bevel, with just 
	//	a 1pt × 1pt (maybe 2px × 2px) square center region.
	theImageSizePt		= aBevelThicknessPt + 1 + aBevelThicknessPt;
	theImageSizePx		= theImageSizePt * (unsigned int)aScale;
	theBevelThicknessPx	= aBevelThicknessPt * (unsigned int)aScale;

	theCGImageRef = CreateBevelImage(	theColorSpaceRef,
										aBaseColor,
										theImageSizePx,
										theImageSizePx,
										theBevelThicknessPx,
										(NSUInteger)aScale);
	if (theCGImageRef == NULL)
		goto CleanUpStretchableBevelImage;
	
	theUnstretchableImage = ([[UIImage alloc] initWithCGImage:theCGImageRef scale:aScale orientation:UIImageOrientationUp]);
	if (theUnstretchableImage == nil)
		goto CleanUpStretchableBevelImage;
	
	theStretchableImage = [theUnstretchableImage resizableImageWithCapInsets:
							UIEdgeInsetsMake(aBevelThicknessPt, aBevelThicknessPt, aBevelThicknessPt, aBevelThicknessPt)];

CleanUpStretchableBevelImage:

	//	ARC does *not* automatically release Core Graphics references.
	//	This is documented at
	//
	//		https://developer.apple.com/library/content/releasenotes/ObjectiveC/RN-TransitioningToARC/Introduction/Introduction.html
	//
	CGColorSpaceRelease(theColorSpaceRef);	//	OK to pass NULL
	CGImageRelease(theCGImageRef);			//	OK to pass NULL

	return theStretchableImage;
}
