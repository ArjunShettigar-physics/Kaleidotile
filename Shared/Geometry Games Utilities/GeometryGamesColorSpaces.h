//	GeometryGamesColorSpaces.h
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#pragma once

extern double	GammaEncode(double aLinearValue);
extern double	GammaDecode(double aGammaEncodedValue);

extern void		ConvertXRsRGBLinearToDisplayP3Linear(const double anXRsRGBColor[3], double aDisplayP3Color[3]);
extern void		ConvertDisplayP3LinearToXRsRGBLinear(const double aDisplayP3Color[3], double anXRsRGBColor[3]);
extern void		ClampExtendedSRGBLinearToNonExtended(const double aColorXRsRGBLinear[4], double aClampedColor[4]);
