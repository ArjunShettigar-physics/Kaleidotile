//	GeometryGamesBevelViewMac.m
//
//	© 2021 by Jeff Weeks
//	See TermsOfUse.txt

#import "GeometryGamesBevelViewMac.h"
#import "GeometryGames-Common.h"
#import "GeometryGamesUtilities-Mac-iOS.h"


@implementation GeometryGamesBevelView
{
	unsigned int	itsBevelThicknessPt;	//	in points
	float			itsRed,		//	in gamma-encoded Display P3 coordinates
					itsGreen,	//	in gamma-encoded Display P3 coordinates
					itsBlue;	//	in gamma-encoded Display P3 coordinates
}


- (id)initWithFrame:(NSRect)aFrame bevelThickness:(unsigned int)aBevelThicknessPt
	red:(float)aRed green:(float)aGreen blue:(float)aBlue	//	in gamma-encoded Display P3 coordinates
{
	self = [super initWithFrame:aFrame];
	if (self != nil)
	{
		itsBevelThicknessPt = aBevelThicknessPt;

		itsRed		= aRed;
		itsGreen	= aGreen;
		itsBlue		= aBlue;
	}
	return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
	CGColorSpaceRef	theColorSpaceRef	= NULL;
	CGSize			theViewSizePx;
	CGFloat			theBevelThicknessPx,
					theScalePxPerPt;
	CGImageRef		theImageRef			= NULL;
	
	UNUSED_PARAMETER(dirtyRect);
	
	//	Get the view's size and the bevel width in pixels (not points).
	theViewSizePx		= [self convertSizeToBacking:[self bounds].size];
	theBevelThicknessPx	= [self convertSizeToBacking:NSMakeSize(itsBevelThicknessPt, itsBevelThicknessPt)].width;
	theScalePxPerPt		= [self convertSizeToBacking:NSMakeSize(1.0, 1.0)].width;

	theColorSpaceRef	= CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
	theImageRef			= CreateBevelImage(	theColorSpaceRef,
											(float [3]){itsRed, itsGreen, itsBlue},
											theViewSizePx.width,
											theViewSizePx.height,
											theBevelThicknessPx,
											(NSUInteger)theScalePxPerPt);

	CGContextDrawImage(	[[NSGraphicsContext currentContext] CGContext],
						NSRectToCGRect([self bounds]),
						theImageRef);

	//	Clean up

	//	ARC does *not* automatically release Core Graphics references.
	//	This is documented at
	//
	//		https://developer.apple.com/library/content/releasenotes/ObjectiveC/RN-TransitioningToARC/Introduction/Introduction.html
	//
	CGColorSpaceRelease(theColorSpaceRef);	//	OK to pass NULL
	CGImageRelease(theImageRef);			//	OK to pass NULL
}

@end
