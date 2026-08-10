//	GeometryGamesGraphicsViewiOS.m
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#import "GeometryGamesGraphicsViewiOS.h"
#import "GeometryGamesModel.h"
#import "GeometryGamesRenderer.h"
#import "GeometryGamesUtilities-Common.h"
#import "GeometryGamesUtilities-Mac-iOS.h"
#import "GeometryGamesUtilities-iOS.h"


//	Privately-declared methods
@interface GeometryGamesGraphicsViewiOS()
@end


@implementation GeometryGamesGraphicsViewiOS
{
}


+ (Class)layerClass
{
#ifdef SUPPRESS_METAL_VIEWS

	//	Return a default CALayer so the app may run on the iOS simulator
	//	which doesn't support all the Metal features that KaleidoPaint needs.
	//	For KaliedoPaint, the simulator might be needed
	//	as a starting point for screenshots at the largest iPhone
	//	and iPad display sizes:  the simulator provides the UI elements,
	//	which we superimpose onto the graphics content manually
	//	(the graphics get exported from the macOS version of the app
	//	at the required sizes).
	return [super layerClass];

#else

	//	Specify the class we want to use to create the Core Animation layer for this view.
	//	Instead of the default CALayer, request a CAMetalLayer.
	return [CAMetalLayer class];

#endif
}


- (id)initWithModel:(GeometryGamesModel *)aModel frame:(CGRect)aFrame
{
	self = [super initWithFrame:aFrame];
	if (self != nil)
	{
		itsModel = aModel;
		if (itsModel == nil)
		{
			self = nil;	//	might not be necessary to set self = nil
			return nil;
		}
		
		itsRenderer	= nil;	//	subclass will create itsRenderer

		//	Let's draw all Metal graphics at the display's full native scale.
		//	The Geometry Games apps use pretty simple fragment functions,
		//	so the cost of evaluating all those pixels isn't so bad.
		//
		//		Note:  The iPhone 6+, 6s+, 7+ and 8+ normally
		//		draw their 412×736 pt layout at exactly 3×
		//		into a virtual 1242×2208 px screen, which then
		//		gets downsampled to the physical 1080×1920 display.
		//		See
		//
		//			https://www.paintcodeapp.com/news/ultimate-guide-to-iphone-resolutions
		//
		//		for a well-illustrated explanation.  Thus on those phones,
		//
		//				scale		= 3.0
		//				nativeScale	= 2.60869565217391
		//
		//		The page
		//
		//			https://oleb.net/blog/2014/11/iphone-6-plus-screen/
		//
		//		goes on to explain that by setting a view's contentScaleFactor
		//		to nativeScale rather than plain scale, it can avoid
		//		the downsampling phase altogether (and thus also render fewer pixels).
		//
		//		See also Apple's Technical Q&A QA1909
		//			https://developer.apple.com/library/content/qa/qa1909/_index.html
		//
		[self setContentScaleFactor:[[UIScreen mainScreen] nativeScale]];
	}
	return self;
}


- (void)setUpGraphics
{
	ModelData	*md	= NULL;

	[itsModel lockModelData:&md];
	[itsRenderer setUpGraphicsWithModelData:md];
	[itsModel unlockModelData:&md];
}

- (void)shutDownGraphics
{
	ModelData	*md	= NULL;

	[itsModel lockModelData:&md];
	[itsRenderer shutDownGraphicsWithModelData:md];
	[itsModel unlockModelData:&md];
}


- (void)layoutSubviews	//	View size may have changed
{
	CGSize		theNativeSizePx,
				theIntegerSizePx;
	CGFloat		theTolerance;
	ModelData	*md	= NULL;
	
	//	In the case of a GeometryGamesGraphicsViewiOS, a call to -layoutSubviews
	//	has absolutely nothing to do with subviews, because the view has no subviews.
	//	Rather the call is telling us that the view's dimensions may have changed.
	//	In response we should replace the framebuffer with a new framebuffer of the correct size.
	//
	theNativeSizePx.width	= [self contentScaleFactor] * [self bounds].size.width;
	theNativeSizePx.height	= [self contentScaleFactor] * [self bounds].size.height;

	//	Caution:  The iPhone 6 Plus has
	//
	//		nativeScale	= 2.60869565217391
	//
	//	so in principle it seems there could be some risk that by time
	//
	//		- the UIKit starts with the view's size in pixels,
	//		- divides by 2.60869565217391 to get the view's size in points,
	//		- tells us that size in points, and then
	//		- we multiply by 2.60869565217391 to get the size in pixels
	//
	//	there could be an off-by-one error.  For example, if we got
	//	a view width of 127.999999999999 which got rounded down to 127 pixels.
	//	Apple might already allow for this and round correctly.
	//	But just to be safe, let's nudge almost-integer width and height
	//	to exact integer width and height.
	//	(But I hesitate to explicitly round all values to the nearest integer,
	//	just in case Apple devises some other screwy convention in the future,
	//	which might *require* a non-integer pixel size here.)

	if (sizeof(CGFloat) >= 8)	//	CGFloat has a 53-bit mantissa (~16 decimal digits) on 64-bit systems
		theTolerance = 1e-4;
	else						//	CGFloat has a 24-bit mantissa (~ 7 decimal digits) on 32-bit systems
		theTolerance = 1e-2;

	theIntegerSizePx.width  = (CGFloat) floor(theNativeSizePx.width  + 0.5);
	if (fabs(theNativeSizePx.width  - theIntegerSizePx.width ) < theTolerance)
		theNativeSizePx.width  = theIntegerSizePx.width;

	theIntegerSizePx.height = (CGFloat) floor(theNativeSizePx.height + 0.5);
	if (fabs(theNativeSizePx.height - theIntegerSizePx.height) < theTolerance)
		theNativeSizePx.height = theIntegerSizePx.height;
	
	
	//	Note:  -viewSizeOrScaleFactorDidChange:modelData: doesn't need
	//	the ModelData's contents, but does rely on it as a lock for thread safety
	//	in the macOS version, where the CVDisplayLink runs the animation
	//	on a separate thread.  So for consistency we pass the ModelData here
	//	in the iOS version as well, even though our CADisplayLink runs
	//	the animation on the main thread.
	[itsModel lockModelData:&md];
	[itsRenderer viewSizeOrScaleFactorDidChange:theNativeSizePx modelData:md];
	[itsModel unlockModelData:&md];
}


- (void)refreshGraphicsView
{
	ModelData	*md	= NULL;

	//	None of the Geometry Games apps ever call setHidden
	//	on a GeometryGamesGraphicsViewiOS,
	//	so there's no need to check isHidden here.
	//	But if we ever want to start doing those things,
	//	we'd also need to make arrangement to re-draw a view
	//	whenever it gets un-hidden.

	[itsModel lockModelData:&md];
	[itsRenderer drawViewWithModelData:md];
	[itsModel unlockModelData:&md];
}


#pragma mark -
#pragma mark Export actions

- (void)saveImageWithAlphaChannel:(bool)anAlphaChannelIsDesired
{
	NSData	*thePNGData;
	
#ifdef SAVE_FOUR_SIZES_WITH_MAGENTA_TOOLBAR_AREA

	unsigned int	i;
	ModelData		*md	= NULL;

	struct
	{
		Char16			*itsPrefix;
		CGSize			itsTotalSize;
		unsigned int	itsNavBarHeight,
						itsToolbarHeight;
	} theSizes[4] =
#if (SAVE_FOUR_SIZES_WITH_MAGENTA_TOOLBAR_AREA == 2)
	{
		{u"phone-HomeBtn - ",	{1242.0, 2208.0}, 132, 132},
		{u"phone-HomeInd - ",	{1242.0, 2688.0}, 264, 249},
		{u"pad-HomeBtn - ",		{2048.0, 2732.0}, 100, 100},
		{u"pad-HomeInd - ",		{2048.0, 2732.0}, 100, 140}
	};
#else
	{
		{u"phone-HomeBtn - ",	{1242.0, 2208.0},   0, 132},
		{u"phone-HomeInd - ",	{1242.0, 2688.0},   0, 234},
		{u"pad-HomeBtn - ",		{2048.0, 2732.0},   0,  88},
		{u"pad-HomeInd - ",		{2048.0, 2732.0},   0, 128}
	};
#endif

	for (i = 0; i < BUFFER_LENGTH(theSizes); i++)
	{
		[itsModel lockModelData:&md];
		thePNGData = UIImagePNGRepresentation(
			[self imageWithSize:	theSizes[i].itsTotalSize
					alphaChannel:	anAlphaChannelIsDesired
					navBarHeight:	theSizes[i].itsNavBarHeight
					toolbarHeight:	theSizes[i].itsToolbarHeight
					modelData:		md]);
		[itsModel unlockModelData:&md];

		thePNGImage	= [UIImage imageWithData:thePNGData];
		UIImageWriteToSavedPhotosAlbum(thePNGImage, nil, nil, nil);
	}

#else	//	! SAVE_FOUR_SIZES_WITH_MAGENTA_TOOLBAR_AREA

	//	To write a JPEG...
//	UIImageWriteToSavedPhotosAlbum([self image], nil, nil, nil);

	//	To write a PNG...
	thePNGData	= UIImagePNGRepresentation([self imageWithAlphaChannel:anAlphaChannelIsDesired]);
#if TARGET_OS_MACCATALYST
	NSFileManager *theFileManager = NSFileManager.defaultManager;
	NSURL *theTemporaryDirectory = theFileManager.temporaryDirectory;
	NSURL *theFileURL = [theTemporaryDirectory URLByAppendingPathComponent: @"temp.png"];
	if ([thePNGData writeToURL:theFileURL atomically:YES]) {
		//	initForExportingURLs is available in MacCatalyst 14.0 and up,
		//	which should correspond to macOS 11.0 and up.
		UIDocumentPickerViewController *thePickerController
			= [[UIDocumentPickerViewController alloc] initForExportingURLs:
				[NSArray arrayWithObject:theFileURL]];
		
		//	Now we need to figure out how to present theController.
		//	UIKit is a bit messy in this respect.
		UIViewController *theTopController
			= [UIApplication sharedApplication].keyWindow.rootViewController;
		while (theTopController.presentedViewController != nil) {
			theTopController = theTopController.presentedViewController;
		}
		
		[theTopController presentModalViewController:thePickerController animated:NO];
	}
#else
	UIImage	*thePNGImage = [UIImage imageWithData:thePNGData];
	UIImageWriteToSavedPhotosAlbum(thePNGImage, nil, nil, nil);
#endif

#endif
}

- (void)copyImageWithAlphaChannel:(bool)anAlphaChannelIsDesired
{
	[[UIPasteboard generalPasteboard]
		setData:			UIImagePNGRepresentation([self imageWithAlphaChannel:anAlphaChannelIsDesired])
		forPasteboardType:	@"public.png"];
}

- (UIImage *)imageWithAlphaChannel:(bool)anAlphaChannelIsDesired
{
	CGSize			theImageSizePt,
					theExportImageSize;
	unsigned int	theMagnificationFactor;
	ModelData		*md = NULL;
	UIImage			*theImage;

	theImageSizePt			= [self bounds].size;
	theMagnificationFactor	= GetUserPrefInt(u"exported image magnification factor");
	theExportImageSize		= (CGSize) {
								theMagnificationFactor * theImageSizePt.width,
								theMagnificationFactor * theImageSizePt.height };

	[itsModel lockModelData:&md];
	theImage = [self imageWithSize:theExportImageSize alphaChannel:anAlphaChannelIsDesired
#ifdef SAVE_FOUR_SIZES_WITH_MAGENTA_TOOLBAR_AREA
		navBarHeight:0 toolbarHeight:0
#endif
		modelData:md];
	[itsModel unlockModelData:&md];
	
	return theImage;
}

- (UIImage *)imageWithSize: (CGSize)aPreferredImageSizePx	//	in pixels, not points
			  alphaChannel: (bool)anAlphaChannelIsDesired
#ifdef SAVE_FOUR_SIZES_WITH_MAGENTA_TOOLBAR_AREA
#error Will need to use UIGraphicsBeginImageContext() etc. or some other way \
	of combining the magenta areas with the rendered image of the app's content.
			  navBarHeight:	(unsigned int)aNavBarHeightPx
			 toolbarHeight:	(unsigned int)aToolbarHeightPx
#endif
			     modelData: (ModelData *)md
{
	CGImageRef	theCGImage	= NULL;
	UIImage		*theUIImage	= nil;

	//	Let itsRenderer render the offscreen image and convert it to a CGImage.
	theCGImage = [itsRenderer newOffscreenImageWithSize:aPreferredImageSizePx modelData:md];

	//	Convert the CGImage to a UIImage.
	if (theCGImage != NULL)
		theUIImage = [UIImage imageWithCGImage:theCGImage];

	//	Release theCGImage.
	CGImageRelease(theCGImage);
	theCGImage = NULL;

	return theUIImage;
}

- (unsigned int)maxExportedImageMagnificationFactor
{
	CGSize			theViewImageSizePt;
	CGFloat			theLargerSidePt;
	GLuint			theMaxFramebufferSizePx;
	unsigned int	theMaxExportedImageMagnificationFactor;

	theViewImageSizePt	= [self bounds].size;
	theLargerSidePt		= MAX(theViewImageSizePt.width, theViewImageSizePt.height);
	if (theLargerSidePt <= 0.0)
		return 1;	//	should never occur

	theMaxFramebufferSizePx = [itsRenderer maxFramebufferSize];
	
	theMaxExportedImageMagnificationFactor
		= (unsigned int) floor(theMaxFramebufferSizePx / theLargerSidePt);
	
	if (theMaxExportedImageMagnificationFactor < 1)	//	should never occur
		theMaxExportedImageMagnificationFactor = 1;
	
	return theMaxExportedImageMagnificationFactor;
}


@end
