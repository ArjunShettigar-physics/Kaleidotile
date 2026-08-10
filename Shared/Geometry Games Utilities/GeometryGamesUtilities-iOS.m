//	GeometryGamesUtilities-iOS.m
//
//	Implements
//
//		functions declared in GeometryGamesUtilities-Common.h that have 
//		platform-independent declarations but platform-dependent implementations
//	and
//		all functions declared in GeometryGamesUtilities-iOS.h.
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#import "GeometryGamesUtilities-Common.h"
#import "GeometryGamesUtilities-iOS.h"
#import "GeometryGamesUtilities-Mac-iOS.h"
#import <Photos/Photos.h>


//	How big should a thumbnail image be?
#define THUMBNAIL_IMAGE_SIZE_IPAD	128.0	//	in points, not pixels
#define THUMBNAIL_IMAGE_SIZE_IPHONE	 64.0	//	in points, not pixels


#pragma mark -
#pragma mark functions with platform-independent declarations


#pragma mark -
#pragma mark functions with iOS-specific declarations

bool MainScreenSupportsP3(void)
{
#if TARGET_OS_SIMULATOR
#warning Re-evaluate this code (and comment) once the simulator is running on an Apple Silicon Mac.
	//	The iOS simulator will claim to support Display P3
	//	whenever the simulated device does, but in reality
	//	it renders only in non-extended sRGB.
	return false;
#else
	return ([[[UIScreen mainScreen] traitCollection] displayGamut] == UIDisplayGamutP3);
#endif
}

#pragma mark -
#pragma mark popovers

void PresentPopoverFromToolbarButton(
	UIViewController	*aPresentingViewController,
	UIViewController	*aPresentedViewController,	//	OK to pass nil
	UIBarButtonItem		*anAnchorButton,
	NSArray<UIView *>	*somePassthroughViews)		//	OK to pass nil
{
	UIPopoverPresentationController	*thePresentationController;
	
	if (aPresentedViewController != nil)
	{
		//	Apple's official documentation for a UIViewController's
		//	popoverPresentationController property
		//
		//		https://developer.apple.com/documentation/uikit/uiviewcontroller/1621428-popoverpresentationcontroller?language=objc
		//
		//	says that:
		//
		//		"If you created the view controller but have not yet presented it,
		//		accessing this property creates a popover presentation controller
		//		when the value in the modalPresentationStyle property is
		//		UIModalPresentationPopover. If the modal presentation style
		//		is a different value, this property is nil."
		//

		[aPresentedViewController setModalPresentationStyle:UIModalPresentationPopover];
		thePresentationController = [aPresentedViewController popoverPresentationController];
		//		Note:  The UIKit will automatically add all siblings of anAnchorButton
		//		to somePassthroughViews, but not anAnchorButton itself, which is
		//		just the behavior we want in most circumstances, so that a second tap
		//		on anAnchorButton automatically dismisses the popover.
		[thePresentationController setBarButtonItem:anAnchorButton];
		[thePresentationController setPassthroughViews:somePassthroughViews];

		[aPresentingViewController
			presentViewController:	aPresentedViewController
			animated:				YES
			completion:				nil];
	}
}

void PresentPopoverFromRectInView(
	UIViewController		*aPresentingViewController,
	UIViewController		*aPresentedViewController,	//	OK to pass nil
	CGRect					anAnchorRect,
	UIView					*anAnchorView,
	UIPopoverArrowDirection	somePermittedArrowDirections,
	NSArray<UIView *>		*somePassthroughViews)		//	OK to pass nil
{
	UIPopoverPresentationController	*thePresentationController;
	
	if (aPresentedViewController != nil)
	{
		//	See comments in PresentPopoverFromToolbarButton() confirming that
		//	the call to [aPresentedViewController popoverPresentationController]
		//	will create the required popover presentation controller.

		[aPresentedViewController setModalPresentationStyle:UIModalPresentationPopover];
		thePresentationController = [aPresentedViewController popoverPresentationController];
		[thePresentationController setSourceRect:anAnchorRect];
		[thePresentationController setSourceView:anAnchorView];
		[thePresentationController setPermittedArrowDirections:somePermittedArrowDirections];
		[thePresentationController setPassthroughViews:somePassthroughViews];

		[aPresentingViewController
			presentViewController:	aPresentedViewController
			animated:				YES
			completion:				nil];
	}
}


#pragma mark -
#pragma mark root view controller

UIViewController *RootViewController(
	UIViewController	*aViewController)
{
	UIViewController	*theRootController;

	//	Start at aViewController and work our way up the stack.
	theRootController = aViewController;
	while ([theRootController presentingViewController] != nil)
		theRootController = [theRootController presentingViewController];
	
	return theRootController;
}


#pragma mark -
#pragma mark images

UIImage *CreateSolidColorImage(
	UIColor	*aColor,
	CGSize	aSizePt)	//	size in points (not pixels)
{
	CGColorSpaceRef	theColorSpace		= NULL;
	CGContextRef	theBitmapContext	= NULL;
	CGImageRef		theCGImage			= NULL;
	UIImage			*theSolidColorImage	= NULL;
	
	//	CGBitmapContextCreate() uses non-negative color coordinates,
	//	so we should work in kCGColorSpaceDisplayP3, rather than
	//	in kCGColorSpaceExtendedSRGB or kCGColorSpaceExtendedLinearSRGB.
	theColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);

	theBitmapContext = CGBitmapContextCreate(
						NULL,
						aSizePt.width,
						aSizePt.height,
						8,
						0,
						theColorSpace,
						kCGImageAlphaPremultipliedLast);	//	must be last, not first
	CGColorSpaceRelease(theColorSpace);
	theColorSpace = NULL;
	
	CGContextSetFillColorWithColor(theBitmapContext, [aColor CGColor]);
	CGContextFillRect(theBitmapContext, (CGRect){CGPointZero, aSizePt});

	theCGImage = CGBitmapContextCreateImage(theBitmapContext);

	CGContextRelease(theBitmapContext);
	theBitmapContext = NULL;
	
	theSolidColorImage = [UIImage imageWithCGImage:theCGImage];
	
	CGImageRelease(theCGImage);
	theCGImage = NULL;

	return theSolidColorImage;
}


#pragma mark -
#pragma mark file paths

NSString *GetFullFilePath(
	NSString	*aFileName,
	NSString	*aFileExtension)	//	includes the leading '.'
									//		for example ".txt" or ".png"
{
	NSURL		*theDirectory;
	NSString	*theExtendedFileName,
				*theFullFilePath;
	
	theDirectory = [[NSFileManager defaultManager]
		URLForDirectory:NSDocumentDirectory inDomain:NSUserDomainMask
		appropriateForURL:nil create:YES error:NULL];
		
	theExtendedFileName = [aFileName stringByAppendingString:aFileExtension];
	
	theFullFilePath = [[theDirectory URLByAppendingPathComponent:theExtendedFileName] path];
	
	return theFullFilePath;
}


#pragma mark -
#pragma mark thumbnails

UIImage *LoadScaledThumbnailImage(
	NSString	*aFileName)	//	file name without path and without ".png" extension
{
	UIImage	*theThumbnailRaw,
			*theThumbnailScaled;

	theThumbnailRaw	= [UIImage imageWithContentsOfFile:GetFullFilePath(aFileName, @".png")];
	
	if (theThumbnailRaw != nil)
	{
		theThumbnailScaled	= [UIImage	imageWithCGImage:	theThumbnailRaw.CGImage
										scale:				[[UIScreen mainScreen] scale]
										orientation:		theThumbnailRaw.imageOrientation];
	}
	else
	{
		theThumbnailScaled = nil;
	}

	if (theThumbnailScaled != nil)
		return theThumbnailScaled;
	else
		return [UIImage imageNamed:@"asterisk.png"];
}

CGFloat GetThumbnailSizePt(void)
{
	//	This could someday become an app-specific function,
	//	if different apps ever want to use different thumbnail sizes.
	
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
		return THUMBNAIL_IMAGE_SIZE_IPAD;
	else
		return THUMBNAIL_IMAGE_SIZE_IPHONE;
}

CGFloat GetThumbnailSizePx(void)
{
	return GetThumbnailSizePt()					//	thumbnail size in points
			* [[UIScreen mainScreen] scale];	//	pixels/point;
}

