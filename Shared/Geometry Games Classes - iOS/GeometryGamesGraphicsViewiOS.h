//	GeometryGamesGraphicsViewiOS.h
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt


#import <UIKit/UIKit.h>
#import "GeometryGames-Common.h"

@class GeometryGamesModel;
@class GeometryGamesRenderer;

@interface GeometryGamesGraphicsViewiOS : UIView
{
	GeometryGamesModel		*itsModel;
	GeometryGamesRenderer	*itsRenderer;
}

+ (Class)layerClass;

- (id)initWithModel:(GeometryGamesModel *)aModel frame:(CGRect)aFrame;

- (void)setUpGraphics;
- (void)shutDownGraphics;

- (void)layoutSubviews;

- (void)refreshGraphicsView;

- (void)saveImageWithAlphaChannel:(bool)anAlphaChannelIsDesired;
- (void)copyImageWithAlphaChannel:(bool)anAlphaChannelIsDesired;
- (UIImage *)imageWithAlphaChannel:(bool)anAlphaChannelIsDesired;
- (UIImage *)imageWithSize:(CGSize)aPreferredImageSizePx alphaChannel:(bool)anAlphaChannelIsDesired
#ifdef SAVE_FOUR_SIZES_WITH_MAGENTA_TOOLBAR_AREA
	navBarHeight:(unsigned int)aNavBarHeightPx toolbarHeight:(unsigned int)aToolbarHeightPx
#endif
	modelData:(ModelData *)md;
- (unsigned int)maxExportedImageMagnificationFactor;

@end
