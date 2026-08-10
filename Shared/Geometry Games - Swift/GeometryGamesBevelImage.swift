//	GeometryGamesBevelImage.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import SwiftUI

func geometryGamesBevelImage(
	bevelThickness: Int,	//	in points
	displayScale: CGFloat	//	pixels per point
) -> Image  {

	let theFailureImage = Image("failure")

	//	The displayScale is the scale at which iOS is rendering our app.
	//	It should be an integer like 2.0 or 3.0, never a non-integer "native scale".
	//	It appears to be unaffected by any Window Zoom (an Accessibility feature).
	let theDisplayScale = Int(floor(displayScale))
	if displayScale != Double(theDisplayScale) {
		assertionFailure("geometryGamesBevelImage() received unexpected non-integer displayScale")
		return theFailureImage
	}
	
	guard let theColorSpace = CGColorSpace(name: CGColorSpace.displayP3) else {
		assertionFailure("geometryGamesBevelImage() failed to create theColorSpace")
		return theFailureImage
	}

	//	Create an image that's almost all bevel,
	//	with just a 1pt × 1pt square center region.
	let theImageSizePt = bevelThickness + 1 + bevelThickness
	let theImageSizePx = theDisplayScale * theImageSizePt
	let thePixelCount = theImageSizePx * theImageSizePx
	
	var thePixels = [UInt32](repeating: 0xFF00FFFF, count: thePixelCount)
	
	thePixels.withUnsafeMutableBufferPointer(){ pixels in
		for col in 0 ..< theImageSizePx {
			for row in 0 ..< theImageSizePx {
				pixels[col*theImageSizePx + row] = bevelColor(
													col: col,
													row: row,
													size: theImageSizePx)
			}
		}
	}

	guard let theCGImage = thePixels.withUnsafeMutableBytes(
		{ (ptr) -> CGImage? in
		
			guard let theCGContext = CGContext(
				data: ptr.baseAddress,
				width: theImageSizePx,
				height: theImageSizePx,
				bitsPerComponent: 8,
				bytesPerRow: 4 * theImageSizePx,
				space: theColorSpace,
				bitmapInfo:
					CGBitmapInfo.byteOrder32Little.rawValue
				+ CGImageAlphaInfo.premultipliedLast.rawValue
			) else {
				assertionFailure("geometryGamesBevelImage() failed to create theCGContext")
				return nil
			}
			
			return theCGContext.makeImage()
		}
	) else {
		assertionFailure("geometryGamesBevelImage() failed to create theCGImage")
		return theFailureImage
	}
	
	let theBevelImage = Image(	theCGImage,
								scale: displayScale,
								label: Text("Bevel"))

	return theBevelImage
}

func bevelColor(
	col: Int,	//	columns run top to bottom
	row: Int,
	size: Int	//	in pixels, of course
) -> UInt32 {

	//	Extracting the color components from Color("MatteColor")
	//	is more complicated than one would expect.
	//	So I simply copied the component here by hand.
	//	Easier for me and perhaps also more reliable.
	let matteColor = SIMD3<UInt>(0xC0, 0xE0, 0xFF)

	//	Adding multiples of 'black' obviously has no effect,
	//	but it keeps our thinking conceptually clear.
	let black = SIMD3<UInt>(0x00, 0x00, 0x00)
	let white = SIMD3<UInt>(0xFF, 0xFF, 0xFF)
	
	//	Swift takes about 119ms to type-check expressions like
	//		(5 &* matteColor  &+  3 &* black) / 8
	//	and completely times out before successfully type-checking the plain version
	//		(5 * matteColor  +  3 * black) / 8
	//	So let's define our own function to break things down
	//	for the Swift type checker. And let's hope the compiler
	//	is willing to use our mult() function to compute the various
	//	constants at compile time, and not once per pixel.
	func mult(
		_ n: UInt,
		_ color: SIMD3<UInt>
	) ->  SIMD3<UInt> {
		let r = n * color.x
		let g = n * color.y
		let b = n * color.z
		return SIMD3<UInt>(r,g,b)
	}
	
	//	Note: SIMD3<UInt> doesn't support '+' so we have
	//	to use '&+' instead, even though there's no risk of overflow.
	
	let top		= (mult(5, matteColor) &+ mult(3, black)) / 8
	let left	= (mult(7, matteColor) &+ mult(3, black)) / 8
	let bottom	= (mult(6, matteColor) &+ mult(2, white)) / 8
	let right	= (mult(7, matteColor) &+ mult(3, black)) / 8
	
	let topLeft		= ( top   &+ left ) / 2
	let topRight	= ( top   &+ right) / 2
	let bottomLeft	= (bottom &+ left ) / 2
	let bottomRight	= (bottom &+ right) / 2

	let theBevelColor: SIMD3<UInt>
	if col == row {
		if col + row > size - 1 {
			theBevelColor = bottomRight
		} else {
			theBevelColor = topLeft
		}
	}
	else if col + row == size - 1 {
		if col > row {
			theBevelColor = bottomLeft
		} else {
			theBevelColor = topRight
		}
	}
	else if col < row {
		if col + row > size - 1 {
			theBevelColor = right
		} else {
			theBevelColor = top
		}
	}
	else {	//	col > row
		if col + row > size - 1 {
			theBevelColor = bottom
		} else {
			theBevelColor = left
		}
	}

	let r = theBevelColor.x << 24
	let g = theBevelColor.y << 16
	let b = theBevelColor.z <<  8
	let a = UInt(0x000000FF)
	let theMergedColor = UInt32(r + g + b + a)

	return theMergedColor
}
