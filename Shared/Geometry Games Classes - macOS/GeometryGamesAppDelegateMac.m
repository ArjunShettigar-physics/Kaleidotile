//	GeometryGamesAppDelegate-Mac.m
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#import "GeometryGamesAppDelegateMac.h"
#import "GeometryGamesWindowController.h"
#import "GeometryGames-Common.h"
#import "GeometryGamesUtilities-Mac.h"
#import "GeometryGamesUtilities-Mac-iOS.h"
#import "GeometryGamesLocalization.h"
#import <WebKit/WebKit.h>


#define HELP_PANEL_MARGIN_H		16.0
#define HELP_PANEL_OVERLAP_H	 8.0
#define HELP_PANEL_MARGIN_V		16.0


//	Privately-declared methods
@interface GeometryGamesAppDelegate()
@end


@implementation GeometryGamesAppDelegate
{
	NSPanel		*itsHelpWindow;
	WKWebView	*itsHelpView;
}


- (void)applicationWillFinishLaunching:(NSNotification *)aNotification
{
	UNUSED_PARAMETER(aNotification);
	
	[[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"NSFullScreenMenuItemEverywhere"];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	static const HelpPageInfo	theNullHelpPageInfo = {u"", u"", u"", false};
	NSString					*theTwoLetterLanguageCodeAsNSString;
	Char16						theTwoLetterLanguageCode[3];

	UNUSED_PARAMETER(aNotification);
	
	//	Set up an empty array to keep strong references to window controllers.
	itsWindowControllers = [[NSMutableArray<GeometryGamesWindowController *> alloc] initWithCapacity:1];
	
	//	No Help window is present.
	itsHelpWindow	= nil;
	itsHelpView		= nil;
	
	//	Set safe temporary values,
	//	which the subclass may overwrite. 
	itsHelpPanelSize	= (CGSize){320.0, 436.0};
	itsNumHelpPages		= 0;
	itsHelpPageIndex	= 0;
	itsHelpPageInfo		= &theNullHelpPageInfo;

	//	Initialize the language code and dictionary to the user's default language.

	//	Get the user's preferred language as an NSString.
	theTwoLetterLanguageCodeAsNSString = GetPreferredLanguage();

	//	Convert the langauge code to a zero-terminated UTF-16 string.
	[theTwoLetterLanguageCodeAsNSString getCharacters:theTwoLetterLanguageCode range:(NSRange){0,2}];
	theTwoLetterLanguageCode[2] = 0;

	//	Record the language code and initialize a dictionary.
	
	SetCurrentLanguage(theTwoLetterLanguageCode);
	
	//	Suppress the search box that the AppKit inserts by default
	//	at the top of the Help menu.
	//
	//		Note:  That search box is more than just an annoyance.
	//		On macOS 10.11 and 10.12 with the search box present,
	//		merely opening the Help menu -- even without selecting anything --
	//		causes the Torus Games main graphics view
	//		to stop receiving trackpad touch events.
	//
	//	Apple's documentation for the NSApplication's helpMenu property, available at
	//
	//		https://developer.apple.com/reference/appkit/nsapplication/1428644-helpmenu
	//
	//	says that
	//
	//		To suppress Spotlight help items altogether,
	//		specify a menu that does not appear on the menu bar.
	//
	//	so that's what we'll do here.
	//
	[NSApp setHelpMenu:[[NSMenu alloc] initWithTitle:LocalizationNotNeeded(@"Dummy Spotlight Menu")]];

	//	Construct the menu bar in the user's preferred language.
	[NSApp setMainMenu:[self buildLocalizedMenuBar]];
	
	//	Normally we want to quit when the user closes the last (and perhaps only) window,
	//	but there may be exceptions, for example DRAW_4D_FOR_TALKS keeps
	//	the application open even when all windows have closed.
	itsQuitWhenAllWindowsHaveClosedFlag	= true;	//	subclass may override
	
	//	Clear Web Kit's cache, so that if the user clicks through
	//	to the Geometry Games site, s/he won't keep seeing an old version of the pages.
	[[WKWebsiteDataStore defaultDataStore]
		removeDataOfTypes:	[WKWebsiteDataStore allWebsiteDataTypes]
		modifiedSince:		[NSDate dateWithTimeIntervalSince1970:0]
		completionHandler:	^{}];
}

- (const Char16 *)languageFileBaseName
{
	//	Subclass must override this method to provide a language file base name.
	//	For example u"MyAppName", not u"MyAppName-xx.txt".
	GEOMETRY_GAMES_ABORT("languageFileBaseName must be overridden");
}


- (NSMenu *)buildLocalizedMenuBar
{
	NSMenu		*theMenuBar;
	NSMenuItem	*theMenuBarItem;
	NSMenu		*theMenu;

	//	The subclass will override this method, and won't call [super buildLocalizedMenuBar].
	//	In case I someday forget to do that, here's a fallback menu bar.

	theMenuBar		= [[NSMenu alloc] initWithTitle:LocalizationNotNeeded(@"menu bar")];
	theMenuBarItem	= [[NSMenuItem alloc] initWithTitle:LocalizationNotNeeded(@"app menu") action:NULL keyEquivalent:@""];
	theMenu			= [[NSMenu alloc] initWithTitle:LocalizationNotNeeded(@"app menu")];
	
	[theMenu addItemWithTitle:LocalizationNotNeeded(@"Quit") action:@selector(terminate:) keyEquivalent:@"q"];
	[theMenuBarItem setSubmenu:theMenu];
	[theMenuBar addItem:theMenuBarItem];

	return theMenuBar;
}

- (BOOL)validateMenuItem:(NSMenuItem *)aMenuItem
{
	SEL	theAction;
	
	theAction = [aMenuItem action];

	if (theAction == @selector(commandHelp:))
	{
		return YES;
	}

	return NO;
}

- (void)commandHelp:(id)sender
{
	[self showHelpPageWithIndex:(unsigned int)[sender tag]];
}

- (void)showHelpPageWithIndex:(unsigned int)aHelpPageIndex
{
	NSWindow				*theMainWindow;
	NSRect					theMainWindowContentRect,
							theHelpWindowContentRect;
	WKWebViewConfiguration	*theConfiguration;
	WKPreferences			*thePreferences;
	
	//	Create itsHelpWindow the first time it's needed,
	//	and then keep it around until the application quits.
	//
	if (itsHelpWindow == nil)
	{
		theMainWindow = [[NSApp orderedWindows] objectAtIndex:0];
		theMainWindowContentRect = [[theMainWindow contentView] frame];	//	in window coordinates
		theMainWindowContentRect = [theMainWindow convertRectToScreen:theMainWindowContentRect];
	
		theHelpWindowContentRect = (NSRect)
		{
			{
				theMainWindowContentRect.origin.x
					+ theMainWindowContentRect.size.width
//					- itsHelpPanelSize.width
//					- HELP_PANEL_MARGIN_H,
					- HELP_PANEL_OVERLAP_H,
				theMainWindowContentRect.origin.y
					+ HELP_PANEL_MARGIN_V
			},
			{
				itsHelpPanelSize.width,
				itsHelpPanelSize.height
			}
		};
		itsHelpWindow = [[NSPanel alloc]
			initWithContentRect:	theHelpWindowContentRect
			styleMask:				NSWindowStyleMaskTitled
										| NSWindowStyleMaskClosable
										| NSWindowStyleMaskUtilityWindow
			backing:				NSBackingStoreBuffered
			defer:					YES];
		theConfiguration = [[WKWebViewConfiguration alloc] init];
		thePreferences   = [[WKPreferences alloc] init];

		//	The Geometry Games own Help pages never use JavaScript,
		//	but some external links do (for example, the Amazon page
		//	for The Shape of Space, 3rd edition).
		//
		//	When DISABLE_TEXT_SELECTION_IN_SCIENCE_CENTER_VERSION
		//	is enabled, we also rely on JavaScript to suppress "callouts".
		//
//	On the one hand,
//
//		'setJavaScriptEnabled:' is deprecated:
//		first deprecated in macOS 11.0 -
//		Use WKWebPagePreferences.allowsContentJavaScript
//		to disable content JavaScript on a per-navigation basis
//
//	On the other hand, the default value of
//
//		WKWebPagePreferences.allowsContentJavaScript
//
//	is 'true', so we can simply comment out the following line
//	and all web pages will load correctly.
//
//		[thePreferences   setJavaScriptEnabled:YES];
		
		[theConfiguration setPreferences:thePreferences];
		itsHelpView = [[WKWebView alloc]
			initWithFrame:	[[itsHelpWindow contentView] bounds]
			configuration:	theConfiguration];
		[[itsHelpWindow contentView] addSubview:itsHelpView];
		[itsHelpView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];

		//	Setting a fake user agent tricks external servers
		//	into serving the mobile versions of their pages,
		//	which fit well into the Geometry Games' narrow Help window.
		//
		//		Warning:  This is a brittle solution.  If Apple
		//		someday revises WKWebView's default user-agent string,
		//		the changes won't be reflected here.
		//
		[itsHelpView setCustomUserAgent:@"Mozilla/5.0 (iPhone)"];

		itsHelpPageIndex = 0;	//	redundant but safe
	}
	
	//	Set the new HelpPageIndex.
	itsHelpPageIndex = aHelpPageIndex;

	//	Refresh the Help text.
	[self refreshHelpText];
	
	//	Show the window, if necessary,
	//	and bring it to the front.
	[itsHelpWindow orderFront:nil];
}
- (void)refreshHelpText
{
	const Char16	*theDirectoryName;
	NSString		*theDirectoryPath,
					*theLanguageSuffix,
					*theFilePath;

	//	Refresh the Help window using the current help page index and language.

	if (itsHelpWindow == nil)
		return;
	
	if (itsHelpPageIndex >= itsNumHelpPages)
		return;	//	should never occur
	
	theDirectoryName	= itsHelpPageInfo[itsHelpPageIndex].itsDirectoryName;
	theDirectoryPath	= [[[NSBundle mainBundle] resourcePath] stringByAppendingPathComponent:
							GetNSStringFromZeroTerminatedString(theDirectoryName)];
	
	if (itsHelpPageInfo[itsHelpPageIndex].itsFileIsLocalized)
	{
		//	My legacy system used a strictly 2-letter language code.
		//	To allow for simplified and traditional Chinese,
		//	it used two exceptional codes
		//
		//		zs -> zh-Hans
		//		zt -> zh-Hant
		//
		if (IsCurrentLanguage(u"zs"))
			theLanguageSuffix = @"zh-Hans";
		else
		if (IsCurrentLanguage(u"zt"))
			theLanguageSuffix = @"zh-Hant";
		else
			theLanguageSuffix = GetNSStringFromZeroTerminatedString(GetCurrentLanguage());

		theFilePath = [theDirectoryPath stringByAppendingPathComponent:
						[NSString stringWithFormat:@"%S-%@.html",
							itsHelpPageInfo[itsHelpPageIndex].itsFileBaseName,
							theLanguageSuffix]];
	}
	else
	{
		theFilePath = [theDirectoryPath stringByAppendingPathComponent:
						[NSString stringWithFormat:@"%S.html",
							itsHelpPageInfo[itsHelpPageIndex].itsFileBaseName]];
	}

	//	To see the user-agent headers, replace the loadFileURL call with
	//
	//		[itsHelpView loadRequest:
	//			[NSURLRequest requestWithURL:
	//				[NSURL URLWithString:@"https://httpbin.org/headers"]]];
	//
	[itsHelpView
		loadFileURL:				[NSURL fileURLWithPath:theFilePath isDirectory:NO]
		allowingReadAccessToURL:	[NSURL fileURLWithPath:theDirectoryPath isDirectory:YES]];

	[itsHelpWindow setTitle:GetLocalizedTextAsNSString(
		itsHelpPageInfo[itsHelpPageIndex].itsTitleKey)];
}


- (void)lastModelDidDeallocate
{
	if (itsQuitWhenAllWindowsHaveClosedFlag)
	{
		//	Close the Help window, if present, and clear our reference to it.
		if (itsHelpWindow != nil)
		{
			[itsHelpWindow orderOut:nil];
			[itsHelpWindow makeFirstResponder:nil];
			itsHelpWindow = nil;
		}

		//	Free memory used for localized dictionary.
		SetCurrentLanguage(u"--");

#ifdef DEBUG
		//	We should be clean.
		if (gMemCount != 0)
		{
			NSLog(@" ***************************");
			NSLog(@" ***                     ***");
			NSLog(@" ***     memory leak     ***");
			NSLog(@" ***   gMemCount == %d    ***", gMemCount);
			NSLog(@" ***                     ***");
			NSLog(@" ***************************");
		}
		else
		{
			NSLog(@"gMemCount == 0");
		}
#endif

		//	Quit.
		[NSApp terminate:self];
	}
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)anApplication
{
	UNUSED_PARAMETER(anApplication);

	//	If we want to check whether the platform-independent C code
	//	has freed all its memory correctly, we must give all windows
	//	a chance to deallocate their contents before terminating the application.
	//	Otherwise the AppKit -- in order to let an application
	//	shut down more quickly -- will intentionally avoid freeing UI objects
	//	when it knows the application as a whole is quitting.

	//	Wait for -lastModelDidDeallocate to check for leaks and quit the application.
	return NO;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
	UNUSED_PARAMETER(sender);

	return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
	UNUSED_PARAMETER(aNotification);
}


//	GeometryGamesWindowControllerDelegate

- (NSArray<GeometryGamesWindowController *> *)geometryGamesWindowControllers
{
	//	Return a reference to itsWindowControllers,
	//	but as an immutable NSArray, not an NSMutableArray.
	return (NSArray<GeometryGamesWindowController *> *) itsWindowControllers;
}

- (void)removeReferenceToWindowController:(GeometryGamesWindowController *)aGeometryGamesWindowController
{
	[itsWindowControllers removeObject:aGeometryGamesWindowController];
}


@end
