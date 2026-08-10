//	GeometryGamesGraphicsViewMac.h
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#import "GeometryGames-Common.h"
#import <Cocoa/Cocoa.h>
#import <Metal/Metal.h>


//	Virtual key codes
#define       ENTER_KEY		 36
#define         TAB_KEY		 48
#define    SPACEBAR_KEY		 49
#define      DELETE_KEY		 51
#define	     ESCAPE_KEY		 53
#define  LEFT_ARROW_KEY		123
#define	RIGHT_ARROW_KEY		124
#define  DOWN_ARROW_KEY		125
#define    UP_ARROW_KEY		126


@class GeometryGamesModel;
@class GeometryGamesRenderer;

@interface GeometryGamesGraphicsViewMac : NSView
{
	GeometryGamesModel		*itsModel;

	GeometryGamesRenderer	*itsRenderer;

	CVDisplayLinkRef		itsDisplayLink;
	double					itsLastUpdateTime;		//	in seconds, from arbitrary start time
}

- (id)initWithModel:(GeometryGamesModel *)aModel frame:(NSRect)aFrame;
- (void)dealloc;

- (void)setUpGraphics;
- (void)shutDownGraphics;

- (void)viewDidMoveToWindow;

- (void)handleApplicationWillResignActiveNotification:(NSNotification *)aNotification;
- (void)handleApplicationDidBecomeActiveNotification:(NSNotification *)aNotification;
- (void)handleWindowDidMiniaturizeNotification:(NSNotification *)aNotification;
- (void)handleWindowDidDeminiaturizeNotification:(NSNotification *)aNotification;

- (BOOL)acceptsFirstResponder;
- (void)keyDown:(NSEvent *)anEvent;

- (void)setFrameSize:(NSSize)newSize;
- (void)setBoundsSize:(NSSize)newSize;
- (void)viewDidChangeBackingProperties;

- (void)setUpDisplayLink;
- (void)shutDownDisplayLink;
- (void)pauseAnimation;
- (void)resumeAnimation;
- (void)updateAnimation;

- (DisplayPointInC)mouseLocation:(NSEvent *)anEvent;
- (DisplayPointMotionInC)mouseDisplacement:(NSEvent *)anEvent;

- (NSData *)imageAsPNGWithAlphaChannel:(bool)anAlphaChannelIsDesired;
- (NSData *)imageAsPNGofSize:(CGSize)aPreferredImageSizePx alphaChannel:(bool)anAlphaChannelIsDesired
#ifdef SAVE_FOUR_SIZES_WITH_MAGENTA_TOOLBAR_AREA
	navBarHeight:(unsigned int)aNavBarHeightPx toolbarHeight:(unsigned int)aToolbarHeightPx
#endif
	;

@end
