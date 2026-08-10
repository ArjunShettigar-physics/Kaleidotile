//	GeometryGamesBevelImage-iOS.h
//
//	Creates a stretchable bevel image.
//
//	© 2021 by Jeff Weeks
//	See TermsOfUse.txt

#import <UIKit/UIKit.h>

extern UIImage *StretchableBevelImage(const float aBaseColor[3], unsigned int aBevelThicknessPt,
										double aScale, UIDisplayGamut aGamut);
