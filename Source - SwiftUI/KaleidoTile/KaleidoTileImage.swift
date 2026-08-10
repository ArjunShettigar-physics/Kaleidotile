//  KaleidoTileImage.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import SwiftUI


//	KTImage is, in effect, a platform-independent
//	replacement for UIImage and NSImage.
//
struct KTImage {

	let cgImage: CGImage
	let scale: CGFloat	//	pixelsPerPoint
	let orientation: Image.Orientation
	
	init(
		cgImage: CGImage,
		scale: CGFloat,	//	pixelsPerPoint
		orientation: Image.Orientation
	) {
		self.cgImage = cgImage
		self.scale = scale
		self.orientation = orientation
	}

#if os(iOS)
	init?(
		uiImage: UIImage
	) {
	
		guard let theCGImage = uiImage.cgImage else {
			assertionFailure("Failed to extract theCGImage from theUIImage in KTImage.init().")
			return nil
		}

		self.cgImage = theCGImage
		self.scale = uiImage.scale
		self.orientation = convertImageOrientation(from: uiImage.imageOrientation)
	
		func convertImageOrientation(
			from uiImageOrientation: UIImage.Orientation
		) -> Image.Orientation {
		
			switch uiImageOrientation {
			
			case .up:				return .up
			case .down:				return .down
			case .left:				return .left
			case .right:			return .right
			case .upMirrored:		return .upMirrored
			case .downMirrored:		return .downMirrored
			case .leftMirrored:		return .leftMirrored
			case .rightMirrored:	return .rightMirrored
			@unknown default:
				assertionFailure("Unknown uiImageOrientation in convertImageOrientation()")
				return .up
			}
		}
	}
#endif
#if os(macOS)
	init?(
		nsImage: NSImage
	) {
	
		var theImageRect = CGRect(
							x: 0,
							y: 0,
							width: nsImage.size.width,
							height: nsImage.size.height)
		guard let theCGImage = nsImage.cgImage(
			forProposedRect: &theImageRect,
			context: nil,
			hints: nil)
		else {
			assertionFailure("Couldn't extract theCGImage from theNSImage in setTexture()")
			return nil
		}
		self.cgImage = theCGImage
		
		//	Apple's documentation at
		//		https://developer.apple.com/documentation/appkit/nsimage/recommendedlayercontentsscale(_:)
		//	says
		//
		//		preferredContentsScale
		//			...
		//			If the image is resolution independent the return value
		//			will be the same as the input. If you specify 0.0
		//			for this parameter, the method uses the scale factor
		//			for the default screen.
		//
		self.scale = nsImage.recommendedLayerContentsScale(0.0)
		
		//	NSImage doesn't seem to carry an orientation,
		//	so let's assign .up and hope for the best.
		self.orientation = .up
	}
#endif

	init?(
		data: Data
	) {
#if os(iOS)
		guard let theUIImage = UIImage(data: data)
		else {return nil}

		self.init(uiImage: theUIImage)
#endif
#if os(macOS)
		guard let theNSImage = NSImage(data: data)
		else {return nil}

		self.init(nsImage: theNSImage)
#endif
	}
}
