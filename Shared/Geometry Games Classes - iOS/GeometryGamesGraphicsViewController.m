//	GeometryGamesGraphicsViewController.m
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#import "GeometryGamesGraphicsViewController.h"
#import "GeometryGamesGraphicsViewiOS.h"
#import "GeometryGamesPopover.h"
#import "GeometryGamesModel.h"
#import "GeometryGamesUtilities-Mac-iOS.h"
#import "GeometryGamesUtilities-Common.h"
#import "GeometryGamesSound.h"
#import "GeometryGamesLocalization.h"
#import <QuartzCore/CADisplayLink.h>


//	Privately-declared properties and methods
@interface GeometryGamesGraphicsViewController()
@end


@implementation GeometryGamesGraphicsViewController
{
	//	itsAnimationTimer keeps a strong reference to its target,
	//	namely this GeometryGamesGraphicsViewController.
	//	If this GeometryGamesGraphicsViewController also
	//	kept a strong reference to itsAnimationTimer,
	//	we'd have a strong reference cycle and neither object
	//	would ever get deallocated.  So keep a weak reference instead.
	//	The run loop will keep a strong reference to itsAnimationTimer
	//	as long as its valid, so there's no danger
	//	of it getting deallocated too soon.
	//
	//		Note:  Because itsAnimationTimer retains this view controller,
	//		the view controller would never get deallocated
	//		if we merely paused itsAnimationTimer when not needed.
	//		Instead we must invalidate (and therefore deallocate)
	//		the timer when not needed, and recreate it when needed again.
	//
	CADisplayLink	* __weak itsAnimationTimer;

	//	What was the value of the ModelData's display change count
	//	the last time we refreshed our view(s)?
	uint64_t	itsPreviousDisplayChangeCount;
}


#pragma mark -
#pragma mark lifecycle

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
	self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
	if (self != nil)
	{
		//	Create the model.
		itsModel = [[GeometryGamesModel alloc] init];

		//	Create itsAnimationTimer later,
		//	when -viewWillAppear: calls -startAnimation.
		itsAnimationTimer = nil;

		//	The ModelData initializes itsDisplayChangeCount to 0,
		//	so we should initialize itsPreviousDisplayChangeCount
		//	to a different value to ensure an initial update.
		itsPreviousDisplayChangeCount = 0xFFFFFFFFFFFFFFFF;

		//	The subclass's -viewDidLoad method typically (but optionally)
		//	assigns a view to itsMainView to take advantage
		//	of this GeometryGamesGraphicsViewController's calls
		//	to [itsMainView setUpGraphics], [itsMainView refreshGraphicsView]
		//	and [itsMainView shutDownGraphics].
		itsMainView = nil;

		//	Listen for application life-cycle events.
		//
		//	Use -addObserver:selector:name:object: instead of
		//	-addObserverForName:object:queue:usingBlock: .
		//	When I saw the block-based version, my first reaction was that
		//	it was an invitation for dangerous not-at-all-obvious object retentions.
		//	So I looked on the internet and indeed the site
		//
		//		https://sealedabstract.com/code/nsnotificationcenter-with-blocks-considered-harmful/
		//
		//	also finds -addObserverForName:object:queue:usingBlock: to be
		//	a dangerous mess.  So let's stick with -addObserver:selector:name:object: .
		//
		[[NSNotificationCenter defaultCenter]
			addObserver:	self
			selector:		@selector(applicationWillResignActive:)
			name:			UIApplicationWillResignActiveNotification
			object:			nil];
		[[NSNotificationCenter defaultCenter]
			addObserver:	self
			selector:		@selector(applicationDidEnterBackground:)
			name:			UIApplicationDidEnterBackgroundNotification
			object:			nil];
		[[NSNotificationCenter defaultCenter]
			addObserver:	self
			selector:		@selector(applicationWillEnterForeground:)
			name:			UIApplicationWillEnterForegroundNotification
			object:			nil];
		[[NSNotificationCenter defaultCenter]
			addObserver:	self
			selector:		@selector(applicationDidBecomeActive:)
			name:			UIApplicationDidBecomeActiveNotification
			object:			nil];
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
}


- (void)applicationWillResignActive:(NSNotification *)notification
{
	UNUSED_PARAMETER(notification);

	if ([[self view] window] != nil)	//	Is window visible?
		[self stopAnimation];
}

- (void)applicationDidEnterBackground:(NSNotification *)notification
{
	UNUSED_PARAMETER(notification);

	[itsMainView shutDownGraphics];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification
{
	UNUSED_PARAMETER(notification);

	[itsMainView setUpGraphics];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
	UNUSED_PARAMETER(notification);

	if ([[self view] window] != nil)	//	Is window visible?
		[self startAnimation];
}


#pragma mark -
#pragma mark view appearance/disappearance

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	//	If we called [self startAnimation] here,
	//	and the view were slow to render
	//	(for example, a complex drawing in KaleidoPaint),
	//	then the view would hesitate as it slid into place
	//	over any underlying view.  So let's call
	//	[self startAnimation] in -viewDidAppear: instead,
	//	so that the view may slide fully into place
	//	before its potentially slow first render.
}

- (void)viewDidAppear:(BOOL)animated
{
	[super viewDidAppear:animated];

	//	See comments in -viewDidDisappear below.
	//	(Re)start the animation here.
	[self startAnimation];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
	//	Apple says that -viewDidDisappear:
	//
	//		Notifies the view controller that its view
	//		was removed from a view hierarchy.
	//
	//	On an iPhone or iPod Touch, the AppKit will call -viewDidDisappear:
	//	whenever a presented view (such as a Language, Preferences or Help panel)
	//	covers the GeometryGamesGraphicsView.  In this situation,
	//	responding to viewWillAppear/viewDidDisappear gives a smoother effect
	//	than responding to viewDidAppear/viewWillDisappear.

	//	In apps such as KaleidoPaint and 4D Draw, where
	//	a GeometryGamesGraphicsViewController-based view controller
	//	gets pushed onto a navigation controller's stack,
	//	when it gets popped off the navigation stack,
	//	the AppKit will call -viewDidDisappear: to let us know.
	//	At this point it's essential to stop the animation.
	//	Otherwise the run loop would keep a strong reference to itsAnimationTimer
	//	and itsAnimationTimer would keep a strong reference to this view controller,
	//	which would never get deallocated.
	//
	[self stopAnimation];
	
	//	Must call superclass implementation.
	[super viewDidDisappear:animated];
}


#pragma mark -
#pragma mark animation

- (void)startAnimation
{
	CADisplayLink	*theAnimationTimer;	//	strong reference
	
	if (itsAnimationTimer == nil)
	{
		//	The run loop will keep a strong reference to theAnimationTimer.
		//	theAnimationTimer will keep a strong reference to its target,
		//	namely this GeometryGamesGraphicsViewController.
		//
		//	Unlike a macOS display link,
		//	this iOS display link runs in the main thread.
		//
		theAnimationTimer = [CADisplayLink
			displayLinkWithTarget:	self
			selector:				@selector(animationTimerFired:)];
		[theAnimationTimer addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];

		itsAnimationTimer = theAnimationTimer;	//	copy strong reference to weak reference
	}
}

- (void)stopAnimation
{
	//	Note:  itsAnimationTimer is a weak reference, but that's OK here.
	//	No other thread will clear it (and even if it could suddenly be cleared
	//	in a different thread, nothing bad would happen here).
	
	if (itsAnimationTimer != nil)	//	unnecessary, but makes our intentions clear
	{
		//	-invalidate clears the run loop's strong reference to the CADisplayLink,
		//	which deallocates the CADisplayLink and thus automatically
		//	clears our weak reference to it (that is, it automatically
		//	sets itsAnimationTimer to nil).
		[itsAnimationTimer invalidate];
	}
}

- (void)animationTimerFired:(CADisplayLink *)sender
{
	double		theElapsedTime;
	ModelData	*md	= NULL;
	uint64_t	theDisplayChangeCount;
	bool		theViewsNeedRefresh;

	//	If the device is managing to keep up with the full frame rate,
	//	then [sender duration] gives the elapsed time between frames.
	//	If the device can't keep up with the frame rate, then the animation
	//	will visibly slow down.
	//
	//		Advantage:  If we skip a frame, we get back on track immediately.
	//
	//		Disadvantage:  If the user runs the app on slower hardware
	//		than I'm testing it on, the animation could run visibly slowly.
	//
	theElapsedTime = [sender duration];


	[itsModel lockModelData:&md];

	//	Update the ModelData as needed.
	if (SimulationWantsUpdates(md))
		SimulationUpdate(md, theElapsedTime);	//	increments itsDisplayChangeCount

	//	Note whether the view needs to get refreshed.
	theDisplayChangeCount			= GetDisplayChangeCount(md);
	theViewsNeedRefresh				= (theDisplayChangeCount != itsPreviousDisplayChangeCount);
	itsPreviousDisplayChangeCount	= theDisplayChangeCount;

	[itsModel unlockModelData:&md];

	//	Refresh views if necessary.
	if (theViewsNeedRefresh)
		[self refreshAllViews];
	
	//	Play any pending sound.
	PlayPendingSound();
}

- (void)refreshAllViews
{
	[itsMainView refreshGraphicsView];

	//	Subclasses may override this method
	//	to refresh other views as well.
}


#pragma mark -
#pragma mark size change

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
	[super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
	
	//	Apple says
	//
	//		You can use a transition coordinator object
	//		to perform tasks that are related to a transition
	//		but that are separate from what the animator objects are doing.
	//		During a transition, the animator objects are responsible
	//		for putting the new view controller content onscreen,
	//		but there may be other visual elements that need to be displayed too.
	//		For example, a presentation controller might want to animate
	//		the appearance or disappearance of decoration views that are
	//		separate from the view controller content.  In that case,
	//		it uses the transition coordinator to perform those animations.

	//	Place code here to run before the transition begins.
	
	[coordinator
		animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> _Nonnull context)
		{
			UNUSED_PARAMETER(context);

			//	Place code here to perform animations during the transition.
		}
		completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context)
		{
			UNUSED_PARAMETER(context);
			
			//	Place code here to run before the transition ends.
		}];
}


//	This same identical traitCollectionDidChange: code appears in both
//	GeometryGamesPortfolioController and GeometryGamesGraphicsViewController.
//	If these two classes ever get any other methods in common,
//	we can pull it out into common GeometryGamesViewController superclass.
//	However at the moment it doesn't seem worth creating a superclass
//	for this one small method alone.
//
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
	UIViewController	*thePresentedViewController,
						*theContentViewController;
	
	[super traitCollectionDidChange:previousTraitCollection];
	
	//	To let a presented view adapt to a new size class,
	//	we must check the new size class here
	//	in the full-window *presenting* view controller,
	//	not in the *presented* view's own view controller.
	//	The presented view's own view controller gets told
	//	only the size class of its own view, which
	//	for a popover-style view is always horizontally compact.
	
	if ([[self traitCollection] horizontalSizeClass] != [previousTraitCollection horizontalSizeClass])
	{
		thePresentedViewController = [self presentedViewController];

		if ([thePresentedViewController isKindOfClass:[UINavigationController class]])
		{
			//	Calling adaptNavBarForHorizontalSize: for the topViewController
			//	is good enough.  If the user later taps the back button
			//	to return to an earlier view controller on the navigation controller's stack,
			//	that earlier view controller's viewWillAppear: method
			//	will call adaptNavBarForHorizontalSize if necessary.
			
			theContentViewController = [((UINavigationController *)thePresentedViewController) topViewController];

			if ([theContentViewController conformsToProtocol:@protocol(GeometryGamesPopover)])
			{
				[((id<GeometryGamesPopover>)theContentViewController)
					adaptNavBarForHorizontalSize:[[self traitCollection] horizontalSizeClass]];
			}
		}
	}
}


@end
