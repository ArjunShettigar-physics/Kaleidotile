//	GeometryGamesAppDelegate-Mac.h
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#import <Cocoa/Cocoa.h>
#import "GeometryGamesWindowController.h"
#import "GeometryGames-Common.h"	//	for Char16


typedef struct
{
	const Char16	*itsTitleKey,
					*itsDirectoryName,
					*itsFileBaseName;	//	just "Foo", not "Foo.html" or "Foo-xx.html"
	const bool		itsFileIsLocalized;
} HelpPageInfo;


@class GeometryGamesWindowController;

@interface GeometryGamesAppDelegate : NSObject
	<NSApplicationDelegate, GeometryGamesWindowControllerDelegate>
{
	NSMutableArray<GeometryGamesWindowController *>		*itsWindowControllers;	//	visible only to subclasses;
															//	other classes may call windowControllers (see below)
	CGSize												itsHelpPanelSize;
	unsigned int										itsNumHelpPages,		//	typically including a "null page"
														itsHelpPageIndex;		//	typically page 0 is the "null page"
	const HelpPageInfo									*itsHelpPageInfo;
	bool												itsQuitWhenAllWindowsHaveClosedFlag;
}

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification;
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification;

- (NSMenu *)buildLocalizedMenuBar;
- (BOOL)validateMenuItem:(NSMenuItem *)aMenuItem;
- (void)commandHelp:(id)sender;
- (void)showHelpPageWithIndex:(unsigned int)aHelpPageIndex;
- (void)refreshHelpText;

- (void)lastModelDidDeallocate;
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)anApplication;
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender;
- (void)applicationWillTerminate:(NSNotification *)aNotification;

//	GeometryGamesWindowControllerDelegate
- (NSArray<GeometryGamesWindowController *> *)geometryGamesWindowControllers;
- (void)removeReferenceToWindowController:(GeometryGamesWindowController *)aGeometryGamesWindowController;

@end
