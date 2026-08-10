//	GeometryGamesBevelViewMac.h
//
//	© 2021 by Jeff Weeks
//	See TermsOfUse.txt

#import <Cocoa/Cocoa.h>

@interface GeometryGamesBevelView : NSView

- (id)initWithFrame:(NSRect)aFrame bevelThickness:(unsigned int)aBevelThicknessPt red:(float)aRed green:(float)aGreen blue:(float)aBlue;
- (void)drawRect:(NSRect)dirtyRect;

@end
