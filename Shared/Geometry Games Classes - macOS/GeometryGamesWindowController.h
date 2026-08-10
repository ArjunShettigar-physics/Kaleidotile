//	GeometryGamesWindowController.h
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#import <Cocoa/Cocoa.h>


@class GeometryGamesWindowController;

@protocol GeometryGamesWindowControllerDelegate
- (NSArray<GeometryGamesWindowController *> *)geometryGamesWindowControllers;
- (void)removeReferenceToWindowController:(GeometryGamesWindowController *)aGeometryGamesWindowController;
@end


@class	GeometryGamesModel,
		GeometryGamesWindowMac,
		GeometryGamesGraphicsViewMac;

@interface GeometryGamesWindowController : NSResponder <NSWindowDelegate>
{
	id<GeometryGamesWindowControllerDelegate> __weak	itsDelegate;

	GeometryGamesModel				*itsModel;
	GeometryGamesWindowMac			*itsWindow;
	GeometryGamesGraphicsViewMac	*itsMainView;	//	may be nil
}

- (id)initWithDelegate:(id<GeometryGamesWindowControllerDelegate>)aDelegate;
- (void)createToolbar;
- (void)createSubviews;
- (void)handlePossibleGPUChangeNotification:(NSNotification *)aNotification;
- (void)windowWillClose:(NSNotification *)aNotification;

- (BOOL)validateMenuItem:(NSMenuItem *)aMenuItem;
- (void)commandCopyImageRGB:(id)sender;
- (void)commandCopyImageRGBA:(id)sender;
- (void)commandSaveImageRGB:(id)sender;
- (void)commandSaveImageRGBA:(id)sender;

- (void)languageDidChange;

@end
