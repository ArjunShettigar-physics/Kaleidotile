//	GeometryGamesUtilities-Mac.m
//
//	Implements
//
//		functions declared in GeometryGamesUtilities-Common.h that have 
//		platform-independent declarations but platform-dependent implementations
//	and
//		all functions declared in GeometryGamesUtilities-Mac.h.
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#import "GeometryGamesUtilities-Mac.h"
#import "GeometryGamesUtilities-Mac-iOS.h"	//	for GetLocalizedTextAsNSString()
#import "GeometryGamesUtilities-Common.h"
#import "GeometryGamesLocalization.h"


#pragma mark -
#pragma mark functions with Mac-specific declarations

id<MTLDevice> CurrentMainScreenGPU(void)
{
	CGDirectDisplayID	theMainScreenDisplayID;
	id<MTLDevice>		theMainScreenMetalDevice;

	//	Apple's page
	//
	//		https://developer.apple.com/documentation/metal/fundamental_components/about_multi_gpu_and_multi_display_setups?language=objc
	//
	//	says
	//
	//		All built-in or connected displays are driven
	//		by only one built-in GPU at any given time
	//		(different built-in GPUs can't drive different displays).
	//
	//	so on most systems the caller may select the GPU
	//	that's driving the main screen, knowing that it will
	//	also be driving whatever screen the caller's own view
	//	happens to end up on.
	//
	//		Caution:  This approach will not work on screens
	//		connected to an external GPU.  To handle such screens
	//		correctly, the caller would need to wait until the view
	//		has been assigned to a window, and the window has been
	//		assigned to a screen, before selecting the GPU that's
	//		driving that screen.
	//
	theMainScreenDisplayID		= (CGDirectDisplayID) [[[[NSScreen mainScreen] deviceDescription]
										objectForKey:@"NSScreenNumber"] unsignedIntegerValue];
	theMainScreenMetalDevice	= CGDirectDisplayCopyCurrentMetalDevice(theMainScreenDisplayID);

	return theMainScreenMetalDevice;
}


NSMenu *AddSubmenuWithTitle(
	NSMenu	*aParentMenu,
	Char16	*aSubmenuTitleKey)
{
	NSString	*theLocalizedTitle;
	NSMenuItem	*theNewParentMenuItem;
	NSMenu		*theNewMenu;

	//	Technical Note:  For top-level menus (i.e. those attached to the menu bar),
	//	theNewMenu's title gets displayed while theNewParentMenuItem's title gets ignored.
	//	For submenus, the reverse is true.  To be safe, pass the same title to both.

	//	Localize aSubmenuTitle to the current language.
	theLocalizedTitle = GetLocalizedTextAsNSString(aSubmenuTitleKey);

	//	Create a new item for aParentMenu, and a new menu to attach to it.
	theNewParentMenuItem	= [[NSMenuItem alloc] initWithTitle:theLocalizedTitle action:NULL keyEquivalent:@""];
	theNewMenu				= [[NSMenu alloc] initWithTitle:theLocalizedTitle];
	
	//	Attach theNewMenu to theNewParentMenuItem.
	[theNewParentMenuItem setSubmenu:theNewMenu];
	
	//	Add theNewParentMenuItem to aParentMenu.
	[aParentMenu addItem:theNewParentMenuItem];
	
	//	Return theNewMenu.
	return theNewMenu;
}

NSMenuItem *MenuItemWithTitleActionTag(
	NSString	*aTitle,
	SEL			anAction,
	NSInteger	aTag)
{
	return MenuItemWithTitleActionKeyTag(aTitle, anAction, 0, aTag);
}

NSMenuItem *MenuItemWithTitleActionKeyTag(
	NSString	*aTitle,
	SEL			anAction,
	unichar		aKeyEquivalent,	//	pass 0 if no key equivalent is needed
	NSInteger	aTag)
{
	NSString	*theKeyEquivalent;
	NSMenuItem	*theMenuItem;
	
	if (aKeyEquivalent != 0)
		theKeyEquivalent = [[NSString alloc] initWithCharacters:&aKeyEquivalent length:1];
	else
		theKeyEquivalent = [[NSString alloc] init];
	
	theMenuItem = [[NSMenuItem alloc] initWithTitle:aTitle action:anAction keyEquivalent:theKeyEquivalent];
	[theMenuItem setTag:aTag];
	
	return theMenuItem;
}


void MakeImageSizeView(
	NSView		* __strong *aView,			//	output
	NSTextField	* __strong *aWidthLabel,	//	output
	NSTextField	* __strong *aWidthValue,	//	output
	NSTextField	* __strong *aHeightLabel,	//	output
	NSTextField	* __strong *aHeightValue)	//	output
{
	NSTextField	*theWidthUnits,
				*theHeightUnits;

	//	Create a view
	//
	//		+--------------------------------------+
	//		|         +------+           +------+  |
	//		|   width:|012345|px  height:|012345|px|
	//		|         +------+           +------+  |
	//		+--------------------------------------+
	//
	//	that the caller may add to the Save Image… sheet,
	//	to let the user specify a custom image width and height.
	//
	//	Note:  An alternative approach would be to create the view
	//	in an XIB file and call -loadNibNamed:owner:topLevelObjects:
	//	to load it.  However, because we're in a plain C function
	//	here, we'd need to either
	//
	//		- create a temporary dummy object with IBOutlets
	//			to receive references to the various subviews
	//	or
	//		- iterate over the top-level object's subviews
	//			to recognize the various fields by their classes and tags.
	//
	//	The XIB-based approach -- when combined with autolayout --
	//	might ultimately offer more flexibility to accommodate
	//	different languages and different font sizes.
	//	For now, though, let's keep the follow code which
	//	creates the aView and its various subviews manually.
	
	*aView = [[NSView alloc] initWithFrame:(NSRect){{0.0, 0.0},{316.0, 38.0}}];
		
	*aWidthLabel = [[NSTextField alloc] initWithFrame:
		(NSRect){{-3.0, 11.0}, {79.0, 17.0}}];
	[*aView addSubview:*aWidthLabel];
	[*aWidthLabel setAlignment:NSTextAlignmentRight];
	[*aWidthLabel setBezeled:NO];
	[*aWidthLabel setEditable:NO];
	[*aWidthLabel setDrawsBackground:NO];
	[*aWidthLabel setFont:[NSFont systemFontOfSize:13.0]];
		
	*aWidthValue = [[NSTextField alloc] initWithFrame:
		(NSRect){{81.0, 8.0}, {50.0, 22.0}}];
	[*aView addSubview:*aWidthValue];
	[*aWidthValue setAlignment:NSTextAlignmentRight];
	[*aWidthValue setBezeled:YES];
	[*aWidthValue setEditable:YES];
	[*aWidthValue setDrawsBackground:YES];
	[*aWidthValue setFont:[NSFont systemFontOfSize:13.0]];
		
	theWidthUnits = [[NSTextField alloc] initWithFrame:
		(NSRect){{136.0, 11.0}, {21.0, 17.0}}];
	[*aView addSubview:theWidthUnits];
	[theWidthUnits setStringValue:LocalizationNotNeeded(@"px")];
	[theWidthUnits setAlignment:NSTextAlignmentLeft];
	[theWidthUnits setBezeled:NO];
	[theWidthUnits setEditable:NO];
	[theWidthUnits setDrawsBackground:NO];
	[theWidthUnits setFont:[NSFont systemFontOfSize:13.0]];
		
	*aHeightLabel = [[NSTextField alloc] initWithFrame:
		(NSRect){{159.0, 11.0}, {79.0, 17.0}}];
	[*aView addSubview:*aHeightLabel];
	[*aHeightLabel setAlignment:NSTextAlignmentRight];
	[*aHeightLabel setBezeled:NO];
	[*aHeightLabel setEditable:NO];
	[*aHeightLabel setDrawsBackground:NO];
	[*aHeightLabel setFont:[NSFont systemFontOfSize:13.0]];
		
	*aHeightValue = [[NSTextField alloc] initWithFrame:
		(NSRect){{243.0, 8.0}, {50.0, 22.0}}];
	[*aView addSubview:*aHeightValue];
	[*aHeightValue setAlignment:NSTextAlignmentRight];
	[*aHeightValue setBezeled:YES];
	[*aHeightValue setEditable:YES];
	[*aHeightValue setDrawsBackground:YES];
	[*aHeightValue setFont:[NSFont systemFontOfSize:13.0]];
		
	theHeightUnits = [[NSTextField alloc] initWithFrame:
		(NSRect){{298.0, 11.0}, {21.0, 17.0}}];
	[*aView addSubview:theHeightUnits];
	[theHeightUnits setStringValue:LocalizationNotNeeded(@"px")];
	[theHeightUnits setAlignment:NSTextAlignmentLeft];
	[theHeightUnits setBezeled:NO];
	[theHeightUnits setEditable:NO];
	[theHeightUnits setDrawsBackground:NO];
	[theHeightUnits setFont:[NSFont systemFontOfSize:13.0]];
}
