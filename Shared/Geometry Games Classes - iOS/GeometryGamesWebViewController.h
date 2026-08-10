//	GeometryGamesWebViewController.h
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#import <UIKit/UIKit.h>
#import "GeometryGamesPopover.h"

//	The app’s HelpChoiceController and this GeometryGamesWebViewController
//	must both see these values.  It's also possible for the size to vary, see
//
//		https://stackoverflow.com/questions/2752394/popover-with-embedded-navigation-controller-doesnt-respect-size-on-back-nav
//
#define HELP_PICKER_WIDTH	320
#define HELP_PICKER_HEIGHT	512	//	480 suffices for English, but not for French or Chinese


@interface GeometryGamesWebViewController : UIViewController
	<GeometryGamesPopover>

- (id)initWithDirectory:(NSString *)aDirectoryName page:(NSString *)aFileName
		closeButton:(UIBarButtonItem *)aCloseButton
		showCloseButtonAlways:(BOOL)aShowCloseButtonAlways
		hideStatusBar:(BOOL)aPrefersStatusBarHidden;
- (void)loadView;
- (void)viewDidLoad;
- (void)viewWillAppear:(BOOL)animated;

//	GeometryGamesPopover
- (void)adaptNavBarForHorizontalSize:(UIUserInterfaceSizeClass)aHorizontalSizeClass;

@end
