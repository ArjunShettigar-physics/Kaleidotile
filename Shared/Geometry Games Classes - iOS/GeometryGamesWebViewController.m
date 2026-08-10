//	GeometryGamesWebViewController.m
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#import <WebKit/WebKit.h>
#import "GeometryGamesWebViewController.h"
#import "GeometryGamesUtilities-iOS.h"


//	DISABLE_TEXT_SELECTION_IN_SCIENCE_CENTER_VERSION is useful
//	for the science center version of Torus Games,
//	to prevent exhibit visitors from getting access to the iOS Notes app.
//	Otherwise it's best to leave text selection enabled,
//	mainly to allow ordinary users to copy text from the Help pages,
//	but also to keep JavaScript disabled for better performance.
//#define DISABLE_TEXT_SELECTION_IN_SCIENCE_CENTER_VERSION
#ifdef DISABLE_TEXT_SELECTION_IN_SCIENCE_CENTER_VERSION
#warning DISABLE_TEXT_SELECTION_IN_SCIENCE_CENTER_VERSION is enabled (should be enabled only for the science center versions of the Torus Games)
#endif


#ifdef DISABLE_TEXT_SELECTION_IN_SCIENCE_CENTER_VERSION

@interface GeometryGamesWebViewController() <WKNavigationDelegate>
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler;
- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler;
@end

#else

@interface GeometryGamesWebViewController()
@end

#endif


@implementation GeometryGamesWebViewController
{
	NSString		*itsDirectoryName,	//	keeps a private copy
					*itsFileName;		//	keeps a private copy
	UIBarButtonItem	*itsCloseButton;
	BOOL			itsShowCloseButtonAlways;
	BOOL			itsPrefersStatusBarHidden;
	WKWebView		*itsWebView;
}

- (id)	initWithDirectory:		(NSString *)aDirectoryName
		page:					(NSString *)aFileName
		closeButton:			(UIBarButtonItem *)aCloseButton
		showCloseButtonAlways:	(BOOL)aShowCloseButtonAlways	//	So the user can close a popover that has passthrough views.
																//		Currently always "YES", so parameter could be eliminated.
		hideStatusBar:			(BOOL)aPrefersStatusBarHidden
{
	self = [super init];
	if (self != nil)
	{
		itsDirectoryName			= [aDirectoryName copy];
		itsFileName					= [aFileName copy];
		itsCloseButton				= aCloseButton;
		itsShowCloseButtonAlways	= aShowCloseButtonAlways;
		
		itsPrefersStatusBarHidden = aPrefersStatusBarHidden;
		
		//	The web page itself will contain a title,
		//	so leave the navigation bar's title area empty.
		[self setTitle:@""];

		[self setPreferredContentSize:(CGSize){HELP_PICKER_WIDTH, HELP_PICKER_HEIGHT}];
	}
	return self;
}

- (BOOL)prefersStatusBarHidden
{
	return itsPrefersStatusBarHidden;
}

- (void)loadView
{
	WKPreferences			*thePreferences;
	WKWebViewConfiguration	*theConfiguration;
#ifdef DISABLE_TEXT_SELECTION_IN_SCIENCE_CENTER_VERSION
	NSString				*theUserScriptSource;
	WKUserScript			*theUserScript;
	WKUserContentController	*theUserContentController;
#endif

	//	-loadView merely decides what subclass of UIView to load, and then loads it.
	//	-viewDidLoad will handle all subsequent view setup.

	thePreferences = [[WKPreferences alloc] init];

#ifdef DISABLE_TEXT_SELECTION_IN_SCIENCE_CENTER_VERSION
	//	At a science center, suppress "callouts", which are
	//	the little bubbles appear when you long-press a word,
	//	offering you a choice of Copy, Paste, etc.
	//	This code was adapted from
	//
	//		https://paulofierro.com/blog/2015/7/13/disabling-callouts-in-wkwebview
	//
	theUserScriptSource =
		@"var style = document.createElement('style'); \
		style.type = 'text/css'; \
		style.innerText = '* { -webkit-user-select: none; -webkit-touch-callout: none; }'; \
		var head = document.getElementsByTagName('head')[0]; \
		head.appendChild(style);";
	theUserScript = [[WKUserScript alloc]
		initWithSource:		theUserScriptSource
		injectionTime:		WKUserScriptInjectionTimeAtDocumentEnd
		forMainFrameOnly:	YES];
	theUserContentController = [[WKUserContentController alloc] init];
	[theUserContentController addUserScript:theUserScript];
#endif

	theConfiguration = [[WKWebViewConfiguration alloc] init];
	[theConfiguration setPreferences:thePreferences];	//	maybe unnecessary
#ifdef DISABLE_TEXT_SELECTION_IN_SCIENCE_CENTER_VERSION
	[theConfiguration setUserContentController:theUserContentController];
#endif
	itsWebView = [[WKWebView alloc]
		initWithFrame:	CGRectZero	//	frame will get set automatically
		configuration:	theConfiguration];
#ifdef DISABLE_TEXT_SELECTION_IN_SCIENCE_CENTER_VERSION
	[itsWebView setNavigationDelegate:self];
#endif
	[itsWebView setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];
	[self setView:itsWebView];
}

- (void)viewDidLoad
{
	NSString	*theResourcePath,
				*theDirectoryPath,
				*theFilePath;

	[super viewDidLoad];
	
	theResourcePath		= [[NSBundle mainBundle] resourcePath];
	theDirectoryPath	= [theResourcePath  stringByAppendingPathComponent:itsDirectoryName];
	theFilePath			= [theDirectoryPath stringByAppendingPathComponent:itsFileName		];

	[itsWebView
		loadFileURL:				[NSURL fileURLWithPath:theFilePath      isDirectory:NO ]
		allowingReadAccessToURL:	[NSURL fileURLWithPath:theDirectoryPath isDirectory:YES]];
}

- (void)viewWillAppear:(BOOL)animated
{
	[super viewWillAppear:animated];

	[self adaptNavBarForHorizontalSize:
		[[RootViewController(self) traitCollection] horizontalSizeClass]];
}


#ifdef DISABLE_TEXT_SELECTION_IN_SCIENCE_CENTER_VERSION

#pragma mark -
#pragma mark WKNavigationDelegate (science center only)

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
	//	In the science center version of the Torus Games,
	//	allow navigation only to
	//
	//		- the app's own internal Help files
	//		- external files at www.geometrygames.org
	//
	if ([[[navigationAction request] URL] isFileURL]
	 || [[[[navigationAction request] URL] host] hasPrefix:@"www.geometrygames.org"])
	{
		decisionHandler(WKNavigationActionPolicyAllow);
	}
	else
	{
		decisionHandler(WKNavigationActionPolicyCancel);
	}
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler
{
	//	In the science center version of the Torus Games,
	//	allow navigation only to files of MIME type "text/html",
	//	never to other files (for example, of type "application/zip").
	//
	if ([[[navigationResponse response] MIMEType] isEqualToString:@"text/html"])
		decisionHandler(WKNavigationResponsePolicyAllow);
	else
		decisionHandler(WKNavigationResponsePolicyCancel);
}

#endif	//	DISABLE_TEXT_SELECTION_IN_SCIENCE_CENTER_VERSION


#pragma mark -
#pragma mark GeometryGamesPopover

- (void)adaptNavBarForHorizontalSize:(UIUserInterfaceSizeClass)aHorizontalSizeClass
{
	if (itsShowCloseButtonAlways)
	{
		//	The Help popover apparently includes the main game area
		//	in its set of passthrough views, to let the user play
		//	with the game while reading the Help page.
		//	So it's asked us to show itsCloseButton
		//	even in a horizontally regular layout.
		[[self navigationItem] setRightBarButtonItem:itsCloseButton animated:NO];
	}
	else
	{
		//	Show itsCloseButton only in a horizontally compact layout,
		//	where the Help panel will cover the whole window.
		[[self navigationItem]
			setRightBarButtonItem:	(aHorizontalSizeClass == UIUserInterfaceSizeClassCompact ?
										itsCloseButton : nil)
			animated:				NO];
	}
}


@end
