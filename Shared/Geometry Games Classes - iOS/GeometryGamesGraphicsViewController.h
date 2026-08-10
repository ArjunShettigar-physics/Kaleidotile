//	GeometryGamesGraphicsViewController.h
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#import <UIKit/UIKit.h>


@class	GeometryGamesModel,
		GeometryGamesGraphicsViewiOS;

@interface GeometryGamesGraphicsViewController : UIViewController
{
	GeometryGamesModel				*itsModel;
	GeometryGamesGraphicsViewiOS	*itsMainView;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil;
- (void)dealloc;

- (void)applicationWillResignActive:(NSNotification *)notification;
- (void)applicationDidEnterBackground:(NSNotification *)notification;
- (void)applicationWillEnterForeground:(NSNotification *)notification;
- (void)applicationDidBecomeActive:(NSNotification *)notification;

- (void)viewWillAppear:(BOOL)animated;
- (void)viewDidAppear:(BOOL)animated;
- (void)viewWillDisappear:(BOOL)animated;
- (void)viewDidDisappear:(BOOL)animated;

- (void)startAnimation;
- (void)stopAnimation;
- (void)animationTimerFired:(CADisplayLink *)sender;
- (void)refreshAllViews;

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator;
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection;

@end
