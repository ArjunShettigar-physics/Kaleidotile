//	GeometryGamesGraphicsViewMac.m
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#import "GeometryGamesGraphicsViewMac.h"
#import "GeometryGamesModel.h"
#import "GeometryGamesRenderer.h"
#import "GeometryGames-Common.h"
#import "GeometryGamesUtilities-Common.h"
#import "GeometryGamesUtilities-Mac-iOS.h"
#import "GeometryGamesSound.h"
#import <QuartzCore/QuartzCore.h>	//	for CAMetalLayer


static CVReturn WrapperForDrawOneFrame(CVDisplayLinkRef displayLink,
	const CVTimeStamp *now, const CVTimeStamp *outputTime, 
	CVOptionFlags flagsIn, CVOptionFlags *flagsOut, void *displayLinkContext);


//	Privately-declared methods
@interface GeometryGamesGraphicsViewMac()
- (void)updateRendererWithViewSize:(NSSize)aNewSizePt;
@end


@implementation GeometryGamesGraphicsViewMac
{
	bool		itsSizeOrScaleFactorDidChange;

	//	What was the value of the ModelData's display change count
	//	the last time we rendered this view?
	uint64_t	itsPreviousDisplayChangeCount;
}

- (id)initWithModel:(GeometryGamesModel *)aModel frame:(NSRect)aFrame
{
	CAMetalLayer	*theMetalLayer;
	CGColorSpaceRef	theColorSpaceRef	= NULL;

	self = [super initWithFrame:aFrame];
	if (self != nil)
	{
		//	Create a CAMetalLayer.
		theMetalLayer = [CAMetalLayer layer];
		
		//	Let theMetalLayer know that we'll be rendering our content
		//	in the (gamma-encoded) Display P3 color space.
		//	The compositor will then adjust our rendered images
		//	to the display's color space.
		//
		//	Warning:
		//		MTKTextureLoader's newTextureWithName
		//		works differently on macOS than on iOS.
		//
		//	  On iOS,
		//		all rendering (in Metal) is done
		//		in extended-range sRGB, and so when newTextureWithName
		//		loads a source texture from the asset catalog,
		//		it converts the colors from the source texture's
		//		own internal color space (typically non-extended sRGB
		//		or Display P3) to extended-range sRGB.
		//		Thus, no matter what the source texture's internal
		//		color space might be, newTextureWithName returns
		//		a MTLTexture with the correct colors.
		//
		//	  On macOS,
		//		by contrast, Metal has no default
		//		working color space.  Instead, the working color space
		//		is whatever we want it to be.
		//
		//		On the "downstream end", the following call to
		//
		//			[theMetalLayer setColorspace:theColorSpaceRef]
		//
		//		tells the compositor how to interpret our rendered image,
		//		so it can correctly convert our colors to the current
		//		display's color space.
		//
		//		On the "upstream end", alas, the color space
		//		is left ambiguous.  When the MTKTextureLoader's
		//		newTextureWithName loads a texture,
		//		it simply copies the source texture's RGB values,
		//		ignoring the color space.  For example,
		//		if one texture is stored in the Display P3 color space
		//		and contains a square of color P3(1,0,0), and
		//		another texture is stored in the sRGB color space
		//		and contains a square of color sRGB(1,0,0),
		//		newTextureWithName will map both those colors
		//		to the same thing, namely a color (1,0,0)
		//		whose color space is left unspecified.
		//
		//		To ensure correct colors on macOS, we would need
		//		to convert all our source textures to Display P3.
		//		Given that Apple is about to migrate its Mac line
		//		to its own Apple Silicon processors and let
		//		apps written for iOS run on macOS as well,
		//		the likely future for my Geometry Games
		//		will be a single "iOS version" of each app
		//		that runs on Macs as well as on iPhones and iPads.
		//		In other words, the current macOS versions
		//		of the Geometry Games apps are likely
		//		to get retired within the next year or two.
		//		So I'm not going to go through and convert
		//		all source textures to Display P3.  Instead,
		//		textures that make sense in sRGB will be left in sRGB.
		//		As a result, the colors in such images will look
		//		slightly too saturated, but the effect shouldn't be too bad,
		//		and in any case the problem will go away when
		//		the macOS-only versions of the Geometry Games apps
		//		get retired.
		//
		theColorSpaceRef = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);
		[theMetalLayer setColorspace:theColorSpaceRef];
		CGColorSpaceRelease(theColorSpaceRef);	//	OK to pass NULL
		theColorSpaceRef = NULL;

		//	According to Apple's NSView documentation at
		//
		//		https://developer.apple.com/reference/appkit/nsview/1483695-wantslayer?language=objc
		//
		//	it's essential that we call -setLayer: before calling -setWantsLayer:
		//	in order to get a "layer-hosting view" as required here.
		//
		[self setLayer:theMetalLayer];
		[self setWantsLayer:YES];

		itsModel = aModel;
		if (itsModel == nil)
		{
			self = nil;	//	might not be necessary to set self = nil
			return nil;
		}
		
		itsRenderer				= nil;	//	subclass will create itsRenderer

		itsDisplayLink			= NULL;	//	caller will call setUpDisplayLink
		itsLastUpdateTime		= CFAbsoluteTimeGetCurrent();
		
		itsSizeOrScaleFactorDidChange	= false;


		//	The ModelData initializes itsDisplayChangeCount to 0,
		//	so we should initialize itsPreviousDisplayChangeCount
		//	to a different value to ensure an initial update.
		//
		itsPreviousDisplayChangeCount = 0xFFFFFFFFFFFFFFFF;


		//	Rather than routing messages from
		//
		//		GeometryGamesAppDelegate
		//			-applicationWillResignActive:
		//			-applicationDidBecomeActive:
		//
		//		GeometryGamesWindowController
		//			-windowDidMiniaturize:
		//			-windowDidDeminiaturize:
		//
		//	let's receive the corresponding notifications directly.

		[[NSNotificationCenter defaultCenter]
			addObserver:	self
			selector:		@selector(handleApplicationWillResignActiveNotification:)
			name:			NSApplicationWillResignActiveNotification
			object:			nil];

		[[NSNotificationCenter defaultCenter]
			addObserver:	self
			selector:		@selector(handleApplicationDidBecomeActiveNotification:)
			name:			NSApplicationDidBecomeActiveNotification
			object:			nil];

		[[NSNotificationCenter defaultCenter]
			addObserver:	self
			selector:		@selector(handleWindowDidMiniaturizeNotification:)
			name:			NSWindowDidMiniaturizeNotification
			object:			nil];	//	See comment in -handleWindowDidMiniaturizeNotification: .

		[[NSNotificationCenter defaultCenter] 
			addObserver:	self
			selector:		@selector(handleWindowDidDeminiaturizeNotification:)
			name:			NSWindowDidDeminiaturizeNotification
			object:			nil];	//	See comment in -handleWindowDidDeminiaturizeNotification: .
	}
	return self;
}

- (void)dealloc
{
	//	Apple's Foundation Release Notes for macOS 10.11 and iOS 9 at
	//
	//		https://developer.apple.com/library/content/releasenotes/Foundation/RN-FoundationOlderNotes/index.html#10_11NotificationCenter
	//	says
	//		In OS X 10.11 and iOS 9.0 NSNotificationCenter and NSDistributedNotificationCenter
	//		will no longer send notifications to registered observers that may be deallocated.
	//		... This means that observers are not required to un-register in their deallocation method.
	//
//	[[NSNotificationCenter defaultCenter] removeObserver:self];

	//	-shutDownDisplayLink calls -pauseAnimation, which should block 
	//	until any currently executing callback function (WrapperForDrawOneFrame)
	//	has returned.
	[self shutDownDisplayLink];	//	ModelData must not be locked, to avoid deadlock
								//	when waiting for a possible CVDisplayLink callback to complete.
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


//	ModelData must not be locked, to avoid deadlock
//	when waiting for a possible CVDisplayLink callback to complete.
- (void)viewDidMoveToWindow
{
	if ([self window] != nil)
	{
		//	This view has been added to a Window.
		//	Start the animation running.
		[self resumeAnimation];
	}
	else
	{
		//	Apple's documentation for NSView's -viewDidMoveToWindow says that
		//
		//		If you call the window method and it returns nil,
		//		that result signifies that the view was removed from its window
		//		and does not currently reside in any window.
		//
		[self pauseAnimation];	//	ModelData must not be locked, to avoid deadlock
								//	when waiting for a possible CVDisplayLink callback to complete.
	}
}


//	ModelData must not be locked, to avoid deadlock
//	when waiting for a possible CVDisplayLink callback to complete.
- (void)handleApplicationWillResignActiveNotification:(NSNotification *)aNotification
{
	//	According to Apple's NSApplication Class Reference,
	//	NSApplicationWillResignActiveNotification is
	//
	//		Posted immediately before the application gives up
	//		its active status to another application.
	//		The notification object is sharedApplication.
	//		This notification does not contain a userInfo dictionary.
	//

	UNUSED_PARAMETER(aNotification);
	
	[self pauseAnimation];	//	ModelData must not be locked, to avoid deadlock
							//	when waiting for a possible CVDisplayLink callback to complete.
}

- (void)handleApplicationDidBecomeActiveNotification:(NSNotification *)aNotification
{
	//	According to Apple's NSApplication Class Reference,
	//	NSApplicationDidBecomeActiveNotification is
	//
	//		Posted immediately after the application becomes active.
	//		The notification object is sharedApplication.
	//		This notification does not contain a userInfo dictionary.
	//

	UNUSED_PARAMETER(aNotification);

	if ( ! [[self window] isMiniaturized] )
		[self resumeAnimation];
}

//	ModelData must not be locked, to avoid deadlock
//	when waiting for a possible CVDisplayLink callback to complete.
- (void)handleWindowDidMiniaturizeNotification:(NSNotification *)aNotification
{
	//	According to Apple's NSWindow Class Reference,
	//	NSWindowDidMiniaturizeNotification is
	//
	//		Posted whenever an NSWindow object is minimized.
	//		The notification object is the NSWindow object that has been minimized.
	//		This notification does not contain a userInfo dictionary.
	//

	//	NSNotificationCenter's -addObserver:selector:name:object: would let us
	//	pass a non-nil object for the notificationSender.  However, there's
	//	no guarantee that the sender is the NSWindow being minimized.
	//	Apple's documentation for NSNotification's -object method says that
	//
	//		[the returned object] is often the object that posted this notification
	//
	//	but allows for the possibility that the sender might be something
	//	other than [aNotification object].
	//	So to be safe, let's receive all NSWindowDidMiniaturizeNotifications
	//	and test each one to see whether it's our own window that's getting miniaturized.
	//
	if ([aNotification object] == [self window])
		[self pauseAnimation];	//	ModelData must not be locked, to avoid deadlock
								//	when waiting for a possible CVDisplayLink callback to complete.
}

- (void)handleWindowDidDeminiaturizeNotification:(NSNotification *)aNotification
{
	//	According to Apple's NSWindow Class Reference,
	//	NSWindowDidDeminiaturizeNotification is
	//
	//		Posted whenever an NSWindow object is deminimized.
	//		The notification object is the NSWindow object that has been deminimized.
	//		This notification does not contain a userInfo dictionary.
	//

	//	NSNotificationCenter's -addObserver:selector:name:object: would let us
	//	pass a non-nil object for the notificationSender.  However, there's
	//	no guarantee that the sender is the NSWindow being de-minimized.
	//	Apple's documentation for NSNotification's -object method says that
	//
	//		[the returned object] is often the object that posted this notification
	//
	//	but allows for the possibility that the sender might be something
	//	other than [aNotification object].
	//	So to be safe, let's receive all NSWindowDidMiniaturizeNotifications
	//	and test each one to see whether it's our own window that's getting de-miniaturized.
	//
	if ([aNotification object] == [self window]			//	essential
	 && [[NSApplication sharedApplication] isActive])	//	unnecessary but harmless
	{
		[self resumeAnimation];
	}
}


- (BOOL)acceptsFirstResponder
{
	return YES;	//	accept keystrokes and action messages
}

- (void)keyDown:(NSEvent *)anEvent
{
	switch ([anEvent keyCode])
	{
		//	Handle special keys, like the esc key
		//	and arrow keys, here in keyDown.
	//	case ESCAPE_KEY:
	//		break;

		default:
		
			//	Ignore the keystoke.
			//	Let the superclass pass it down the responder chain.
			[super keyDown:anEvent];

			//	Process the keystroke normally.
		//	[self interpretKeyEvents:@[anEvent]];

			break;
	}
}


#pragma mark -
#pragma mark resize

- (void)setFrameSize:(NSSize)newSize
{
	[super setFrameSize:newSize];
	
	[self updateRendererWithViewSize:newSize];
}

- (void)setBoundsSize:(NSSize)newSize
{
	[super setBoundsSize:newSize];

	[self updateRendererWithViewSize:newSize];
}

- (void)viewDidChangeBackingProperties
{
	[super viewDidChangeBackingProperties];

	[self updateRendererWithViewSize:[self bounds].size];
}

- (void)updateRendererWithViewSize:(NSSize)aNewSizePt	//	new size in points
{
	CGSize		theNativeSizePx;	//	new size in pixels (not points)
	ModelData	*md	= NULL;

	theNativeSizePx = [self convertSizeToBacking:aNewSizePt];
	
	//	Note:  -viewSizeOrScaleFactorDidChange:modelData: doesn't need
	//	the ModelData's contents, but does rely on it as a lock for thread safety.
	[itsModel lockModelData:&md];
	[itsRenderer viewSizeOrScaleFactorDidChange:theNativeSizePx modelData:md];
	[itsModel unlockModelData:&md];
	
	itsSizeOrScaleFactorDidChange = true;
}


#pragma mark -
#pragma mark animation

- (void)setUpDisplayLink
{
	if (itsDisplayLink == NULL)	//	unnecessary but safe
	{
		//	Create a display link capable of being used with all active displays.
		CVDisplayLinkCreateWithActiveCGDisplays(&itsDisplayLink);

		//	Set the renderer output callback function.
		CVDisplayLinkSetOutputCallback(itsDisplayLink, &WrapperForDrawOneFrame, (__bridge void *)self);

		//	Set the display link for the main display.
		CVDisplayLinkSetCurrentCGDisplay(itsDisplayLink, CGMainDisplayID());

		//	Let the subclass start the display link running
		//	once the model data is in place.
	}
}

//	ModelData must not be locked, to avoid deadlock
//	when waiting for a possible CVDisplayLink callback to complete.
- (void)shutDownDisplayLink
{
	if (itsDisplayLink != NULL)	//	unnecessary but safe
	{
		//	The call to -pauseAnimation should block until any currently 
		//	executing callback function (WrapperForDrawOneFrame) has returned.
		[self pauseAnimation];	//	ModelData must not be locked, to avoid deadlock
								//	when waiting for a possible CVDisplayLink callback to complete.
		CVDisplayLinkRelease(itsDisplayLink);
		itsDisplayLink = NULL;
	}
}

- (void)pauseAnimation
{
	//	In an online forum posting, a seemingly knowledgable guy
	//	says that CVDisplayLinkStop() will block until any currently 
	//	executing callback function (WrapperForDrawOneFrame) has returned.
	if (CVDisplayLinkIsRunning(itsDisplayLink))
		CVDisplayLinkStop(itsDisplayLink);	//	ModelData must not be locked, to avoid deadlock
											//	when waiting for a possible CVDisplayLink callback to complete.
}

- (void)resumeAnimation
{
	if ( ! CVDisplayLinkIsRunning(itsDisplayLink) )
		CVDisplayLinkStart(itsDisplayLink);
}

- (void)updateAnimation
{
	ModelData		*md	= NULL;
	double			theCurrentTime,	//	in seconds
					theElapsedTime;	//	in seconds
	uint64_t		theDisplayChangeCount;

	//	Get a lock on the ModelData, waiting, if necessary,
	//	for the main thread to finish with it first.
	[itsModel lockModelData:&md];

	//	Note theElapsedTime.
	theCurrentTime		= CFAbsoluteTimeGetCurrent();
	theElapsedTime		= theCurrentTime - itsLastUpdateTime;
	itsLastUpdateTime	= theCurrentTime;

	//	Update the ModelData as needed.
	//
	//		Design note:  I made a feeble attempt to move the CVDisplayLink
	//		from the GeometryGamesGraphicsViewMac to GeometryGamesWindowController,
	//		which would be a more natural place for it, especially in cases
	//		where two views display the same ModelData.  Alas things got messy
	//		in a hurry, so I retreated to the present organization.
	//		The present organization is tolerable, but will require that
	//		we let only the "primary" view call SimulationUpdate(),
	//		to avoid updating it twice.
	//
	if (SimulationWantsUpdates(md)
	 || itsSizeOrScaleFactorDidChange)
	{
		SimulationUpdate(md, theElapsedTime);	//	increments itsDisplayChangeCount
		itsSizeOrScaleFactorDidChange = false;
	}

	//	Redraw the view as needed.
	theDisplayChangeCount = GetDisplayChangeCount(md);
	if (theDisplayChangeCount != itsPreviousDisplayChangeCount)
	{
		[itsRenderer drawViewWithModelData:md];
		itsPreviousDisplayChangeCount = theDisplayChangeCount;
	}

	//	Unlock the ModelData.
	[itsModel unlockModelData:&md];


	//	Play any pending sound.
	PlayPendingSound();
}


#pragma mark -
#pragma mark mouse events

- (DisplayPointInC)mouseLocation:(NSEvent *)anEvent
{
	NSPoint			theMouseLocation;
	NSSize			theViewSize;
	DisplayPointInC	theMousePoint;

	//	mouse location in window coordinates (hmmm... this might be pixels)
	theMouseLocation = [anEvent locationInWindow];

	//	mouse location in view coordinates
	//	(0,0) to (theViewSize.width, theViewSize.height)
	theMouseLocation = [self convertPoint:theMouseLocation fromView:nil];

	//	view size in points (not pixels, but that's OK just so we're consistent)
	theViewSize = [self bounds].size;
	
	//	Package up the result.
	theMousePoint.itsX			= theMouseLocation.x;
	theMousePoint.itsY			= theMouseLocation.y;
	theMousePoint.itsViewWidth	= theViewSize.width;
	theMousePoint.itsViewHeight	= theViewSize.height;
	
	return theMousePoint;
}

- (DisplayPointMotionInC)mouseDisplacement:(NSEvent *)anEvent
{
	NSSize				theViewSize;
	DisplayPointMotionInC	theMouseMotion;

	//	view size in points (not pixels, but that's OK just so we're consistent)
	theViewSize = [self bounds].size;
	
	//	Package up the motion.
	//	Note that deltaY is reported in top-down coordinates, because 
	//	
	//		“NSEvent computes this delta value in device space, 
	//		which is flipped, but both the screen and the window’s 
	//		base coordinate system are not flipped.”
	//
	theMouseMotion.itsDeltaX		=   [anEvent deltaX];	//	(hmmm... is this in points or pixels?)
	theMouseMotion.itsDeltaY		= - [anEvent deltaY];	//	(hmmm... is this in points or pixels?)
	theMouseMotion.itsViewWidth		= theViewSize.width;
	theMouseMotion.itsViewHeight	= theViewSize.height;

	return theMouseMotion;
}


#pragma mark -
#pragma mark Image as PNG

- (NSData *)imageAsPNGWithAlphaChannel:(bool)anAlphaChannelIsDesired
{
	CGSize	theSizePt,	//	the view size in points
			theSizePx;	//	the view size in pixels

	//	The caller has not specified an image size,
	//	so, as a default, pass the view size in pixels (not points).
	
	theSizePt = [self bounds].size;
	theSizePx = [self convertSizeToBacking:theSizePt];
	
	return [self imageAsPNGofSize:theSizePx alphaChannel:anAlphaChannelIsDesired
#ifdef SAVE_FOUR_SIZES_WITH_MAGENTA_TOOLBAR_AREA
					 navBarHeight:0
					toolbarHeight:0
#endif
		];
}

- (NSData *)imageAsPNGofSize:(CGSize)aPreferredImageSizePx	//	size in pixels, not points
				alphaChannel:(bool)anAlphaChannelIsDesired
#ifdef SAVE_FOUR_SIZES_WITH_MAGENTA_TOOLBAR_AREA
#error Will need find some other way of combining the magenta areas \
 with the rendered image of the app's content.  (Maybe UIImage operations in iOS version?)
				navBarHeight:(unsigned int)aNavBarHeightPx
			   toolbarHeight:(unsigned int)aToolbarHeightPx
#endif
{
	ModelData			*md			= NULL;
	CGImageRef			theCGImage	= NULL;
	NSBitmapImageRep	*theBitmap	= nil;
	NSData				*thePNG		= nil;
	
	//	Let itsRenderer render the offscreen image and convert it to a CGImage.
	[itsModel lockModelData:&md];
	theCGImage = [itsRenderer newOffscreenImageWithSize:aPreferredImageSizePx modelData:md];
	[itsModel unlockModelData:&md];
	
	//	Convert the CGImage to an NSBitmapImageRep.
	if (theCGImage != NULL)
		theBitmap = [[NSBitmapImageRep alloc] initWithCGImage:theCGImage];
	
	//	Release theCGImage.
	CGImageRelease(theCGImage);
	theCGImage = NULL;

	//	Convert NSBitmapImageRep to a PNG (as NSData).
	thePNG = [theBitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];

	if (thePNG == nil)
		GeometryGamesErrorMessage(u"Couldn't create PNG representation.", u"Image Copying Error");

	return thePNG;
}

@end


static CVReturn WrapperForDrawOneFrame(
	CVDisplayLinkRef	displayLink,
	const CVTimeStamp	*now,					//	current time
	const CVTimeStamp	*outputTime,			//	time that frame will get displayed
	CVOptionFlags		flagsIn,
	CVOptionFlags		*flagsOut,
	void				*displayLinkContext)
{
	GeometryGamesGraphicsViewMac	*theView;
	
	UNUSED_PARAMETER(displayLink);
	UNUSED_PARAMETER(now);
	UNUSED_PARAMETER(outputTime);
	UNUSED_PARAMETER(flagsIn);
	UNUSED_PARAMETER(flagsOut);
	
	//	The CVDisplayLink runs in a separate thread,
	//	with no default autorelease pool, so we must
	//	provide our own autorelease pool to avoid leaking memory.
	@autoreleasepool
	{
		theView = (__bridge GeometryGamesGraphicsViewMac *) displayLinkContext;
		[theView updateAnimation];
	}

	return kCVReturnSuccess;
}

