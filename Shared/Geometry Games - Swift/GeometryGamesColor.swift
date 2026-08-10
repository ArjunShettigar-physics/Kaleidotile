//	GeometryGamesColor.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import Foundation
import SwiftUI	//	for makeLinearXRsRGBColor() and makeSwiftUIColor()
import simd


// MARK: -
// MARK: Basic definitions

struct GeometryGamesChromaticity {

	//	The CIE 1931 x and y values are the "source of truth" for a chromaticity.
	let x: Double
	let y: Double
			
	//	The CIE 1931 z value follows easily as z = 1 - (x + y).
	let z: Double
	
	init(
		x: Double,
		y: Double
	) {
		self.x = x
		self.y = y
		self.z = 1.0 - (x + y)
	}
}

struct GeometryGamesTristimulus {

	//	The CIE 1931 (X,Y,Z) vector is a multiple
	//	of the CIE 1931 chromaticity (x,y,z).  (See above)
	//	The multiple depends not on a single chromaticity alone,
	//	but on a set of colors {Red, Green, Green, WhitePoint},
	//	with lengths chosen so that
	//
	//		Red + Green + Green = WhitePoint
	//	and
	//		the WhitePoint's Y component is 1.
	//
	let X: Double
	let Y: Double
	let Z: Double
	
	init (
		chromaticity: GeometryGamesChromaticity,
		multiple: Double
	) {
		X = multiple * chromaticity.x
		Y = multiple * chromaticity.y
		Z = multiple * chromaticity.z
	}
}

struct GeometryGamesColorProfile {

	let red: GeometryGamesTristimulus
	let green: GeometryGamesTristimulus
	let blue: GeometryGamesTristimulus
	let white: GeometryGamesTristimulus
	
	init(
		rawRed: GeometryGamesChromaticity,
		rawGreen: GeometryGamesChromaticity,
		rawBlue: GeometryGamesChromaticity,
		rawWhite: GeometryGamesChromaticity)
	{
		//	Let the white point's (X,Y,Z) be (x/y, y/y, z/y),
		//	to satisfy the convention that Y = 1 for the white point.
		white = GeometryGamesTristimulus(
			chromaticity: rawWhite,
			multiple: 1.0 / rawWhite.y)	//	no risk of division by zero

		//	We now need to find what multiples (mR, mG, mB)
		//	of the red, green and blue primitives, that is
		//
		//		(Xr, Yr, Zr) = mR * (xr, yr, zr)
		//		(Xg, Yg, Zg) = mG * (xg, yg, zg)
		//		(Xb, Yb, Zb) = mB * (xb, yb, zb)
		//
		//	are required to get the red, green and blue (X,Y,Z) vectors
		//	to sum to the (X,Y,Z) vector of the white point.
		//	That is, we need to solve
		//
		//		(xr xg xb)(mR)   (Xw)
		//		(yr yg yb)(mG) = (Yw)
		//		(zr xg zb)(mB)   (Zw)
		//
		let theMatrix = simd_double3x3(	//	columns of the matrix above are rows here
			SIMD3<Double>(  rawRed.x,   rawRed.y,   rawRed.z),
			SIMD3<Double>(rawGreen.x, rawGreen.y, rawGreen.z),
			SIMD3<Double>( rawBlue.x,  rawBlue.y,  rawBlue.z)
		)
		let theRHS = SIMD3<Double>(white.X, white.Y, white.Z)
		let theMultiples = theMatrix.inverse * theRHS
		
		red   = GeometryGamesTristimulus(chromaticity: rawRed,   multiple: theMultiples[0])
		green = GeometryGamesTristimulus(chromaticity: rawGreen, multiple: theMultiples[1])
		blue  = GeometryGamesTristimulus(chromaticity: rawBlue,  multiple: theMultiples[2])
	}
	
	func colorSpaceToXYZ(
	) -> simd_double3x3 {
	
		return simd_double3x3(
			SIMD3<Double>(   red.X,   red.Y,   red.Z ),
			SIMD3<Double>( green.X, green.Y, green.Z ),
			SIMD3<Double>(  blue.X,  blue.Y,  blue.Z )
		)
	}
}


// MARK: -
// MARK: sRGB and P3 gamuts

//	sRGB gamut from
//
//		https://en.wikipedia.org/wiki/SRGB#The_sRGB_gamut
//
let gColorProfileSRGB = GeometryGamesColorProfile(
	//	exact numbers, by definition (I hope!)
	rawRed:   GeometryGamesChromaticity(x: 0.64, y: 0.33),
	rawGreen: GeometryGamesChromaticity(x: 0.30, y: 0.60),
	rawBlue:  GeometryGamesChromaticity(x: 0.15, y: 0.06),
	rawWhite: GeometryGamesChromaticity(x: 0.3127, y: 0.3290))

//	P3 gamut from
//
//		https://en.wikipedia.org/wiki/DCI-P3#System_colorimetry
//
let gColorProfileDisplayP3 = GeometryGamesColorProfile(
	rawRed:   GeometryGamesChromaticity(x: 0.680, y: 0.320),
	rawGreen: GeometryGamesChromaticity(x: 0.265, y: 0.690),
	rawBlue:  GeometryGamesChromaticity(x: 0.150, y: 0.060),	//	same blue  as in sRGB
	rawWhite: GeometryGamesChromaticity(x: 0.3127, y: 0.3290))	//	same white as in sRGB


// MARK: -
// MARK: sRGB <-> P3 conversion

func colorConversionMatrix(
	from profileA: GeometryGamesColorProfile,
	  to profileB: GeometryGamesColorProfile
) -> simd_double3x3 {

	//	Each color profile defines the transformation matrix
	//	from its color space to CIE XYZ coordinates.
	//
	//	A-to-XYZ
	//		( A.red.X, A.green.X, A.blue.X )
	//		( A.red.Y, A.green.Y, A.blue.Y )
	//		( A.red.Z, A.green.Z, A.blue.Z )
	//
	//	B-to-XYZ
	//		( B.red.X, B.green.X, B.blue.X )
	//		( B.red.Y, B.green.Y, B.blue.Y )
	//		( B.red.Z, B.green.Z, B.blue.Z )
	//
	//	In the matrix equation
	//
	//		(  A  )   (  B  )(  A   )
	//		( to  ) = ( to  )(  to  )
	//		( XYZ )   ( XYZ )(  B   )
	//
	//	we know sRGB-to-XYZ and P3-to-XYZ,
	//	so we may solve for P3-to-sRGB.
	
	let AtoXYZ = profileA.colorSpaceToXYZ()
	let BtoXYZ = profileB.colorSpaceToXYZ()
	let AtoB = BtoXYZ.inverse * AtoXYZ

	return AtoB
}


//	The following matrices serve to convert between Linear sRGB
//	and Linear Display P3.  Although it would work fine to simply
//	hard code these two matrices, for future reference and flexibility
//	I'm including the code that produces these matrices, and indeed
//	am letting that code re-create the matrices each time the app is run.
//
//		gP3toSRGB = simd_double3x3(
//			SIMD3<Double>( 1.22494017628056, -0.04205695470969, -0.01963755459033),
//			SIMD3<Double>(-0.22494017628056,  1.04205695470969, -0.07863604555063),
//			SIMD3<Double>( 0.00000000000000,  0.00000000000000,  1.09827360014097)
//		)
//
//		gSRGBtoP3 = simd_double3x3(
//			SIMD3<Double>( 0.82246196871436,  0.03319419885096,  0.01708263072112),
//			SIMD3<Double>( 0.17753803128564,  0.96680580114904,  0.07239744066396),
//			SIMD3<Double>( 0.00000000000000,  0.00000000000000,  0.91051992861492)
//		)
//
//	Those matrices also agree with the values one gets by letting
//	Core Graphics do the conversions (using CGColors and CGColorSpaces).
//	Well, they agree to ~4 decimal places, which I'm guessing is
//	all the precision that Core Graphics keeps for color components,
//	because in practice that's all that's needed.
//
let gP3toSRGB = colorConversionMatrix(from: gColorProfileDisplayP3, to: gColorProfileSRGB)
let gSRGBtoP3 = colorConversionMatrix(from: gColorProfileSRGB, to: gColorProfileDisplayP3)

//	Note:  The results found here are completely consistent
//	with Wikipedia's summary of the standards,
//	including the sRGB Y values shown in the table at
//
//		https://en.wikipedia.org/wiki/SRGB#The_sRGB_gamut
//
//	Moreover, they almost agree to 4 decimal places
//	with results obtained from explicit color conversions
//	performed in macOS's built-in ColorSync Utility.
//	But they disagree significantly with results obtained
//	from the color profiles available in ColorSync Utility.
//	(ColorSync Utility's profiles are inconsistent
//	with its own color conversion feature, so our results here
//	can't possibly agree with both.)


// MARK: -
// MARK: HSV <-> RGB conversion

func HSVtoRGB(
	hue: Double,
	saturation: Double,
	value: Double
) -> simd_half3 {

	let theBaseColors: [SIMD3<Double>] = [
							SIMD3<Double>(1.0, 0.0, 0.0),	//	red
							SIMD3<Double>(1.0, 1.0, 0.0),	//	yellow
							SIMD3<Double>(0.0, 1.0, 0.0),	//	green
							SIMD3<Double>(0.0, 1.0, 1.0),	//	cyan
							SIMD3<Double>(0.0, 0.0, 1.0),	//	blue
							SIMD3<Double>(1.0, 0.0, 1.0)	//	magenta
						]

	let theHue        = max(0.0, min(1.0, hue       ))
	let theSaturation = max(0.0, min(1.0, saturation))
	let theValue      = max(0.0, min(1.0, value     ))

	//	Divide the color circle into six equal segments, to be delimited
	//	by the colors {red, yellow, green, cyan, blue, magenta, red}.
	let theHue6 = 6.0 * theHue		//	∈ [0.0, 6.0]
	let theSegment = floor(theHue6)	//	∈ {0,1,2,3,4,5,6}
	let theInterpolator	= theHue6 - theSegment

	let theLeftHue	= theBaseColors[   Int(theSegment)   % 6 ]	//	cast from Double to Int
	let theRightHue	= theBaseColors[ Int(theSegment + 1) % 6 ]

	var theRGBColor: simd_half3 = simd_half3.zero
	for i in 0...2 {	//	iterate over r,g,b components
	
		let theRawColor			= (1.0 - theInterpolator) * theLeftHue [i]
								+     theInterpolator     * theRightHue[i]
		
		let theDesaturatedColor	=     theSaturation     * theRawColor
								+ (1.0 - theSaturation) *     1.0
		
		let theDarkenedColor	= theValue * theDesaturatedColor
		
		theRGBColor[i] = Float16(theDarkenedColor)
	}
	
	return theRGBColor
}


// MARK: -
// MARK: Premultiplied alpha

//	The geometry games apps (along with most other modern software) internally
//	store colors as (αR, αG, αB, α) instead of the traditional (R,G,B,α)
//	to facilitate blending and mipmap generation.
//
//	1.	Rigorously correct blending requires
//
//					   αs*(Rs,Gs,Bs) + (1 - αs)*αd*(Rd,Gd,Bd)
//			(R,G,B) = ----------------------------------------
//							 αs      +      (1 - αs)*αd
//
//				  α = αs + (1 - αs)*αd
//
//		Replacing the traditional (R,G,B,α) with the premultiplied (αR,αG,αB,α)
//		simplifies the formula to
//
//			(αR, αG, αB) = (αs*Rs, αs*Gs, αs*Bs) + (1 - αs)*(αd*Rd, αd*Gd, αd*Bd)
//
//					   α = αs + (1 - αs)*αd
//
//		Because they share the same coefficients,
//		we may merge the RGB and α parts into a single formula
//
//			(αR, αG, αB, α) = (αs*Rs, αs*Gs, αs*Bs, αs) + (1 - αs)*(αd*Rd, αd*Gd, αd*Bd, αd)
//
//
//	2.	When generating mipmaps, to average two (or more) pixels correctly
//		we must weight them according to their alpha values.
//		With traditional (R,G,B,α) the formula is a bit messy
//
//								 α0*(R0,G0,B0) + α1*(R1,G1,B1)
//			(Ravg, Gavg, Bavg) = -----------------------------
//								            α0 + α1
//
//								 α0 + α1
//						  αavg = -------
//									2
//
//		With premultiplied (αR,αG,αB,α) the formula becomes a simple average
//
//			(αavg*Ravg, αavg*Gavg, αavg*Bavg, αavg)
//
//				  (α0*R0, α0*G0, α0*B0, α0) + (α1*R1, α1*G1, α1*B1, α1)
//				= -----------------------------------------------------
//											2
//
//


// MARK: -
// MARK: SwiftUI color conversion

func makeLinearXRsRGBColor(
	from swiftUIColor: Color
) -> SIMD4<Float16>? {	// linear extended-range sRGB color

	let theCGColor = swiftUIColor.cgColor ?? CGColor.init(
						red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0)

	//	Prepare a linear extended-range sRGB color space
	guard let theLinearXRsRGBColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else {
		assertionFailure("Failed to create theLinearXRsRGBColorSpace")
		return nil
	}
	
	//	theCGColor could be using any color space internally.
	//	Convert it to a CGColor that uses the linear extended-range sRGB color space.
	guard let theLinearXRsRGBColor = theCGColor.converted(
			to: theLinearXRsRGBColorSpace,
			intent: CGColorRenderingIntent.relativeColorimetric,	//	see comments in KaleidoPaint's LinearDisplayP3Color
			options: nil) else {
		assertionFailure("failed to convert to theLinearXRsRGBColor")
		return nil
	}
	if theLinearXRsRGBColor.numberOfComponents != 4 {
		assertionFailure("theLinearXRsRGBColor has the wrong number of components")
		return nil
	}
	if theLinearXRsRGBColor.colorSpace?.name != CGColorSpace.extendedLinearSRGB {
		assertionFailure("theLinearXRsRGBColor isn't based on extendedLinearSRGB")
		return nil
	}
	
	//	Extract theLinearXRsRGBColor's components as an array of CGFloats
	guard let theLinearXRsRGBColorComponents = theLinearXRsRGBColor.components else {
		assertionFailure("failed to retrieve the components of theLinearXRsRGBColorComponents")
		return nil
	}
	if theLinearXRsRGBColorComponents.count != 4 {
		assertionFailure("theLinearXRsRGBColorComponents has unexpected length")
		return nil
	}
	
	let theResult = SIMD4<Float16>(
		Float16(theLinearXRsRGBColorComponents[0]),
		Float16(theLinearXRsRGBColorComponents[1]),
		Float16(theLinearXRsRGBColorComponents[2]),
		Float16(theLinearXRsRGBColorComponents[3])
	)
	
	return theResult
}

func makeSwiftUIColor(
	from linearXRsRGBColor: SIMD4<Float16>	// linear extended-range sRGB color
) -> Color {

	let r = linearXRsRGBColor[0]
	let g = linearXRsRGBColor[1]
	let b = linearXRsRGBColor[2]
	let a = linearXRsRGBColor[3]

	//	Prepare a linear extended-range sRGB color space
	guard let theLinearXRsRGBColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else {
		assertionFailure("Failed to create theLinearXRsRGBColorSpace")
		return Color.red
	}
	
	var theLinearXRsRGBColor: [CGFloat] = [CGFloat(r), CGFloat(g), CGFloat(b), CGFloat(a)]
	guard let theCGColor = CGColor(colorSpace: theLinearXRsRGBColorSpace, components: &theLinearXRsRGBColor) else {
		assertionFailure("Failed to create theCGColor")
		return Color.yellow
	}
	let theColor = Color(cgColor: theCGColor)
	
	return theColor
}

func premultiplyAlpha(
	_ nonPremultipliedColor: SIMD4<Float16>
) -> SIMD4<Float16> {

	let r = nonPremultipliedColor[0]
	let g = nonPremultipliedColor[1]
	let b = nonPremultipliedColor[2]
	let a = nonPremultipliedColor[3]
	
	let thePremultipliedColor = SIMD4<Float16>(r*a, g*a, b*a, a)
	
	return thePremultipliedColor
}

func unPremultiplyAlpha(
	_ premultipliedColor: SIMD4<Float16>
) -> SIMD4<Float16> {

	let r = premultipliedColor[0]
	let g = premultipliedColor[1]
	let b = premultipliedColor[2]
	let a = premultipliedColor[3]
	
	let theUnPremultipliedColor =  ( a > 0.0 ?
		SIMD4<Float16>(r/a, g/a, b/a,  a ) :
		SIMD4<Float16>(0.0, 0.0, 0.0, 0.0) )
	
	return theUnPremultipliedColor
}


