//	GeometryGamesWindowController.m
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#import "GeometryGamesWindowController.h"
#import "GeometryGamesModel.h"
#import "GeometryGamesWindowMac.h"
#import "GeometryGamesGraphicsViewMac.h"
#import "GeometryGamesUtilities-Mac.h"
#import "GeometryGamesUtilities-Mac-iOS.h"
#import "GeometryGamesUtilities-Common.h"


//	Privately-declared properties and methods
@interface GeometryGamesWindowController()
- (void)commandCopyImageWithAlphaChannel:(bool)anAlphaChannelIsDesired;
- (void)commandSaveImageWithAlphaChannel:(bool)anAlphaChannelIsDesired;
@end


@implementation GeometryGamesWindowController
{
}


- (id)initWithDelegate:(id<GeometryGamesWindowControllerDelegate>)aDelegate
{
	self = [super init];
	if (self != nil)
	{
		//	Keep a weak reference to the delegate.
		itsDelegate = aDelegate;
		
		//	Create the model.
		itsModel = [[GeometryGamesModel alloc] init];

		//	Create the window.
		itsWindow = [[GeometryGamesWindowMac alloc]
			initWithContentRect:	(NSRect){{0, 0}, {512, 384}}	//	temporary size
			styleMask:				NSWindowStyleMaskTitled
									 | NSWindowStyleMaskClosable
									 | NSWindowStyleMaskMiniaturizable
									 | NSWindowStyleMaskResizable
			backing:				NSBackingStoreBuffered
			defer:					YES];
		[itsWindow setReleasedWhenClosed:NO];	//	ARC will release itsWindow
												//	when no object has a strong reference to it.

		//	Using a layer-backed view is probably a good idea in any case,
		//	and in macOS 10.13.4 it's essential to work around a macOS bug:
		//	If the main content view isn't layer-backed but contains a Metal subview,
		//	then when the user sends the window fullscreen, macOS enlarges
		//	the Metal subview as much as possible and centers it on the screen (!).
		//	Mouse events still get interpreted relative to where the Metal subview
		//	should have been, it's just where that subview gets drawn that's wrong.
		//
		[[itsWindow contentView] setWantsLayer:YES];
		
		[itsWindow setDelegate:self];
		[itsWindow setContentMinSize:(NSSize){256, 256}];	//	Subclass may override.
		[itsWindow setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
		
		//	Give the subclass a chance to create a toolbar.
		//	Call -createToolbar before -createSubviews,
		//	so -createSubviews will see the expected content view bounds.
		[self createToolbar];

		//	Let the subclass populate itsWindow's contentView with subviews.
		//	The subclass may optionally assign a view to itsMainView
		//	to take advantage of this GeometryGamesWindowController's
		//	standard behaviour for copy, save, miniaturize/deminiaturize, etc.
		itsMainView = nil;
		[self createSubviews];
		
		//	Zoom the window.  As a happy side-effect,
		//	this triggers a call to -windowDidResize:,
		//	which gives the subclass a chance to arrange its subviews.
		[itsWindow zoom:self];
		
		//	Refresh all text in the current language.
		[self languageDidChange];
		
		//	Let itsMainView be itsWindow's first responder,
		//	so it will receive keystrokes.
		[itsWindow setInitialFirstResponder:itsMainView];

		//	Show itsWindow.
		[itsWindow makeKeyAndOrderFront:nil];

//		[itsWindow toggleFullScreen:self];

		//	Register for GPU-change notifications.
		[[NSNotificationCenter defaultCenter]
			addObserver:	self
			selector:		@selector(handlePossibleGPUChangeNotification:)
			name:			NSApplicationDidChangeScreenParametersNotification
			object:			nil];
	}
	return self;
}

- (void)createToolbar
{
	//	Subclasses may override this method to create a toolbar.
}

- (void)createSubviews
{
	//	Subclasses may override this method
	//	to populate [itsWindow contentView] with subviews,
	//	and may optionally assign a view to itsMainView
	//	to take advantage of this GeometryGamesWindowController's
	//	standard behaviour for copy, save, miniaturize/deminiaturize, etc.

	//	If the subclass's -createSubviews method calls
	//	-setAutoresizingMask: for the subviews that it creates,
	//	then the subclass needn't implement -windowDidResize:.
	//
	//	If the subclass's -createSubviews method does not call
	//	-setAutoresizingMask: for the subviews that it creates,
	//	then the subclass should implement -windowDidResize:
	//	to arrange its subviews within the window's newly resized
	//	content view.
}

- (void)handlePossibleGPUChangeNotification:(NSNotification *)aNotification
{
	NSArray<NSView *>	*theSubviews;
	NSView				*theSubview;
	
	//	Note:
	//
	//		The following code works fine for its originally
	//		intended purpose for letting a high-end MacBook switch
	//		between its low-power GPU and its high-performance GPU.
	//
	//		Alas this code also get called when clicking back and forth
	//		between a full-screen window on an external monitor
	//		and a regular window on a built-in monitor.
	//		In this case click to the full-screen window
	//		always generates a strange sequence
	//		of pauseAnimation/resumeAnimation calls,
	//		and sometimes leaves the animation running
	//		when it shouldn't.  In particular, when I slide
	//		the full-screen window away with a 3-finger swipe,
	//		its animation often (always?) keeps running -- and
	//		keeps eating both GPU and CPU cycles -- even though
	//		the window isn't visible and the animation should be paused.
	//
	//		So for now I'll just disable the following code.
	//		In the not-too-distant future I'll most likely be
	//		writing SwiftUI versions of the GeometryGames apps.
	//		Those SwiftUI versions will, I'm guessing, essentially
	//		be iOS apps that can also be run on MacOS.
	//		So with luck the SwiftUI framework will automatically
	//		deal with on-the-fly GPU changes.  We'll see!
	//
#warning Review the above comment from time to time, \
and decide what if anything to do with the following code.
	return;

	//	Remove subviews from [itsWindow contentView].
	//
	//		Make a copy of the contentView's subviews array,
	//		to avoid iterating over it directly
	//		while removing objects from it.
	//
	theSubviews = [NSArray<NSView *> arrayWithArray:[[itsWindow contentView] subviews]];
	for (theSubview in theSubviews)
		[theSubview removeFromSuperview];

	//	Create new subviews using the possibly newly-selected GPU.
	//
	//		createSubviews should replace itsMainView along with all of the subclass's
	//		references to subviews (for example, several subclasses keep
	//		an instance variable that points to the same view as itsMainView
	//		but as a specific subclass of a GeometryGamesGraphicsViewMac).
	//		Once all references have been cleared, the old subviews
	//		will get deallocated.
	//
	[self createSubviews];

	//	In theory firstResponder is a weak reference,
	//	but in practice if we don't clear it
	//	the previous graphics view won't get released
	//	until we click on the new one.
	[itsWindow makeFirstResponder:nil];
	
	//	Some of the Geometry Games apps let their createSubviews method
	//	place the various subviews arbitrarily, and then set
	//	the correct subview placements in windowDidResize:.
	//	So let's simulate a windowDidResize: notification now.
	if ([self respondsToSelector:@selector(windowDidResize:)])
	{
		[self windowDidResize:[NSNotification
				notificationWithName:	NSWindowDidResizeNotification
				object:					self]];
	}
	
	//	Subclasses may override this method to handle
	//	any additional subview setup they may require.
	//	For example, the TorusGamesWindowController needs
	//	to call exitTorusCursorMode before replacing the subviews,
	//	and refreshHanziView after replacing them.
}

- (void)windowWillClose:(NSNotification *)aNotification
{
	UNUSED_PARAMETER(aNotification);

	//	Be careful: NSWindow does not use zeroing weak references,
	//	because it must run on macOS 10.7, which doesn't support them.
	//	So let's clear itsWindow's delegate manually.
	//	Someday, when NSWindow replaces
	//		@property (nullable, assign) id<NSWindowDelegate> delegate;
	//	with
	//		@property (nullable, weak) id<NSWindowDelegate> delegate;
	//	we'll probably be able to delete this call to [itsWindow setDelegate:nil].
	//	(Or, in Swift, when
	//		unowned(unsafe) var delegate: NSWindowDelegate?
	//	gets replaced with a safe version.)
	//
	[itsWindow setDelegate:nil];

	[itsWindow makeFirstResponder:nil];	//	maybe also unnecessary?

	//	The window holds no more pointers to this controller,
	//	so the app delegate may clear its reference to the controller,
	//	and let the controller get deallocated.  This will, in turn,
	//	clear the strong references to itsModel, itsWindow and itsMainView,
	//	along with any additional strong references that the subclass might hold.
	[itsDelegate removeReferenceToWindowController:self];
}


- (BOOL)validateMenuItem:(NSMenuItem *)aMenuItem
{
	SEL	theAction;

	theAction = [aMenuItem action];

	if (theAction == @selector(commandCopyImageRGB: ))
		return YES;

	if (theAction == @selector(commandCopyImageRGBA:))
		return YES;

	if (theAction == @selector(commandSaveImageRGB: ))
		return YES;

	if (theAction == @selector(commandSaveImageRGBA:))
		return YES;

	return NO;
}

//	Note #1:  When people save an image from KaleidoPaint and then later
//	resize it in Photoshop, Photoshop screws up the pixels along the edges
//	if and only if the image has an alpha channel.  To work around that
//	Photoshop bug, this shared GeometryGames code provides separate commands
//	to copy itsMainView's image with or without an alpha channel.
//	At present KaleidoPaint and Curved Spaces copy their images with no alpha channel,
//	the other apps copy their images with an alpha channel included.
//
//	Note #2:  ModelData must not be locked, to avoid deadlock
//	when waiting for a possible CVDisplayLink callback to complete.

- (void)commandCopyImageRGB:(id)sender
{
	[self commandCopyImageWithAlphaChannel:false];
}

- (void)commandCopyImageRGBA:(id)sender
{
	[self commandCopyImageWithAlphaChannel:true];
}

- (void)commandCopyImageWithAlphaChannel:(bool)anAlphaChannelIsDesired
{
	NSData			*thePNG					= nil;
	NSPasteboard	*theGeneralPasteboard	= nil;
	
	thePNG = [itsMainView imageAsPNGWithAlphaChannel:anAlphaChannelIsDesired];
	
	if (thePNG != nil)
	{
		theGeneralPasteboard = [NSPasteboard generalPasteboard];
		
		[theGeneralPasteboard declareTypes:@[@"public.png"] owner:nil];
		[theGeneralPasteboard setData:thePNG forType:@"public.png"];
	}
}

//	See Notes #1 and #2 above, which apply to Save as well as Copy.

- (void)commandSaveImageRGB:(id)sender
{
	[self commandSaveImageWithAlphaChannel:false];
}

- (void)commandSaveImageRGBA:(id)sender
{
	[self commandSaveImageWithAlphaChannel:true];
}

- (void)commandSaveImageWithAlphaChannel:(bool)anAlphaChannelIsDesired
{
	NSSavePanel						*theSavePanel			= nil;
	NSSize							theViewSizePt,		//	the view size in points
									theViewSizePx;		//	the view size in pixels
	NSView							*theImageSizeView		= nil;
	NSTextField						*theImageWidthLabel		= nil,
									*theImageWidthValue		= nil,
									*theImageHeightLabel	= nil,
									*theImageHeightValue	= nil;
	GeometryGamesGraphicsViewMac	*theMainView			= nil;
	
	//	Pause the animation while the user selects a file name, 
	//	so the saved image will contain the desired frame.
	[itsMainView pauseAnimation];	//	ModelData must not be locked, to avoid deadlock
									//	when waiting for a possible CVDisplayLink callback to complete.

	theSavePanel = [NSSavePanel savePanel];
	[theSavePanel setAllowedFileTypes:@[@"png"]];
//	[theSavePanel setTitle:GetLocalizedTextAsNSString(u"SavePanelTitle")];	Sheet shows no title
	[theSavePanel setNameFieldStringValue:GetLocalizedTextAsNSString(u"DefaultFileName")];
	
	//	Add a custom view to the Save panel
	//	so the user may specify the image width and height.
	MakeImageSizeView(	&theImageSizeView,
						&theImageWidthLabel,  &theImageWidthValue,
						&theImageHeightLabel, &theImageHeightValue);
	[theImageWidthLabel  setStringValue:GetLocalizedTextAsNSString(u"WidthLabel" )];
	[theImageHeightLabel setStringValue:GetLocalizedTextAsNSString(u"HeightLabel")];
	theViewSizePt = [itsMainView bounds].size;
	theViewSizePx = [itsMainView convertSizeToBacking:theViewSizePt];
	[theImageWidthValue  setIntValue:theViewSizePx.width];
	[theImageHeightValue setIntValue:theViewSizePx.height];
	[theSavePanel setAccessoryView:theImageSizeView];

	//	The completion handler is an Objective-C “block”.
	//	For a good discussion of how blocks make it easy
	//	to create strong reference cycles, see
	//
	//		https://blackpixel.com/writing/2014/03/capturing-myself.html
	//
	//	For more background on the intricacies of blocks,
	//	and how they retain the objects they refer to, see
	//
	//		developer.apple.com/library/ios/#documentation/cocoa/Conceptual/Blocks/Articles/00_Introduction.html
	//	and
	//		cocoawithlove.com/2009/10/how-blocks-are-implemented-and.html
	//
	
	//	Copy the instance variable itsMainView to the local variable theMainView,
	//	and pass it to the block.  This way the block will hold a strong reference
	//	to the view and not to "self".  (If the block accessed
	//	the instance variable "itsMainView" directly, it would need
	//	a strong reference to "self", which would create a strong reference cycle.
	//	Such a strong reference cycle might be harmless in this case --
	//	it would be broken when the user dismissed the modal sheet --
	//	but even still it makes me nervous.  At the very least it would
	//	require extra effort on the part of the programmer to think through
	//	what would happen if, say, the user closed the window before dismissing
	//	the sheet.)
	theMainView = itsMainView;
	
	[theSavePanel beginSheetModalForWindow:itsWindow
		completionHandler:^(NSInteger result)
		{
			NSData	*thePNG	= nil;

			if (result == NSModalResponseOK)
			{
#ifdef SAVE_FOUR_SIZES_WITH_MAGENTA_TOOLBAR_AREA
				NSURL			*theRawURL;
				NSURL			*theDirectoryURL;
				NSString		*theBaseFileName;
				unsigned int	i;
				NSString		*thePrefix,
								*theFileName;
				NSURL			*theFileURL;
				
				struct
				{
					Char16			*itsPrefix;
					NSSize			itsTotalSize;
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
				
				theRawURL		= [theSavePanel URL];
				theDirectoryURL	= [theRawURL URLByDeletingLastPathComponent];
				theBaseFileName	= [theRawURL lastPathComponent];
				
				for (i = 0; i < BUFFER_LENGTH(theSizes); i++)
				{
					thePrefix	= GetNSStringFromZeroTerminatedString(theSizes[i].itsPrefix);
					theFileName	= [thePrefix stringByAppendingString:theBaseFileName];
					theFileURL	= [theDirectoryURL URLByAppendingPathComponent:theFileName isDirectory:NO];

					thePNG = [theMainView
								imageAsPNGofSize:	theSizes[i].itsTotalSize
								alphaChannel:		anAlphaChannelIsDesired
								navBarHeight:		theSizes[i].itsNavBarHeight
								toolbarHeight:		theSizes[i].itsToolbarHeight];

					if (thePNG != nil)
					{
						if ([thePNG writeToURL:theFileURL atomically:YES] == NO)
							GeometryGamesErrorMessage(u"Couldn't save resized image under requested filename.", u"Save failed");
					}
				}
				
#else	//	! SAVE_FOUR_SIZES_WITH_MAGENTA_TOOLBAR_AREA
				NSSize	theDesiredViewSize;

				theDesiredViewSize.width  = [theImageWidthValue  intValue];
				theDesiredViewSize.height = [theImageHeightValue intValue];

				thePNG = [theMainView
							imageAsPNGofSize:	theDesiredViewSize
							alphaChannel:		anAlphaChannelIsDesired];

				if (thePNG != nil)
				{
					if ([thePNG writeToURL:[theSavePanel URL] atomically:YES] == NO)
						GeometryGamesErrorMessage(u"Couldn't save image under requested filename.", u"Save failed");
				}
#endif
			}

			[theMainView resumeAnimation];
		}
	];
}


- (void)languageDidChange
{
	[itsWindow setTitle:GetLocalizedTextAsNSString(u"WindowTitle")];
}


@end
