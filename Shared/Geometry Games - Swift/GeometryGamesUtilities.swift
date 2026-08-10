//	GeometryGamesUtilities.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import SwiftUI
import simd


//	Assuming a constant frame rate, and let gFramePeriod
//	be the time from the start of one frame to the start of the next.
//
#if os(iOS)
let gFramePeriod: CFTimeInterval
	= 1.0 / CFTimeInterval(UIScreen.main.maximumFramesPerSecond)	//	in seconds
#endif
#if os(macOS)
//	Could different displays be running at different rates?
//	Seems unlikely if they're running off the same GPU, but
//	some Macs can use multiple GPUs. Maybe don't worry about that?
let gFramePeriod: CFTimeInterval
	= 1.0 / (CGDisplayCopyDisplayMode(CGMainDisplayID())?.refreshRate ?? 60.0)
#endif


let gQuaternionIdentity = simd_quatd(real: 1.0, imag: .zero)


#if targetEnvironment(simulator)
	//	The iOS simulator will claim to support Display P3
	//	whenever the simulated device does, but in reality
	//	it renders only in non-extended sRGB.
	let gMainScreenSupportsP3: Bool = false
#else

#if os(iOS)
let gMainScreenSupportsP3: Bool
	= UIScreen.main.traitCollection.displayGamut == UIDisplayGamut.P3
#endif
#if os(macOS)
//	On macOS let's render in extended-range sRGB gamut color coordinates,
//	which can support Display P3, and hope for the best.
//	When I attach a narrow-color display to my MacBook everything
//	works as sit should: Starter Code shows its colors in Display P3
//	when I drag the window to my MacBook's internal display,
//	and then converts (clamps?) the colors to the sRGB gamut
//	when I drag the window to the external monitor.
let  gMainScreenSupportsP3: Bool = true
#endif

#endif


func convertDouble3x3toFloat3x3(
	_ m: simd_double3x3
) -> simd_float3x3 {

	let theFloat3x3 = simd_float3x3(
		SIMD3<Float>(m[0]),
		SIMD3<Float>(m[1]),
		SIMD3<Float>(m[2])
	)

	return theFloat3x3
}

func convertDouble4x4toFloat4x4(
	_ m: simd_double4x4
) -> simd_float4x4 {

	let theFloat4x4 = simd_float4x4(
		SIMD4<Float>(m[0]),
		SIMD4<Float>(m[1]),
		SIMD4<Float>(m[2]),
		SIMD4<Float>(m[3])
	)

	return theFloat4x4
}

func convertDouble4x3toFloat4x3(
	_ m: simd_double4x3
) -> simd_float4x3 {

	let theFloat4x3 = simd_float4x3(
		SIMD3<Float>(m[0]),
		SIMD3<Float>(m[1]),
		SIMD3<Float>(m[2]),
		SIMD3<Float>(m[3])
	)

	return theFloat4x3
}

func matrix4x4ExtendingMatrix3x3(
	_ m: simd_double3x3
) -> simd_double4x4 {

	let theMatrix4x4 = simd_double4x4(
		SIMD4<Double>(m[0][0], m[0][1], m[0][2], 0.0),
		SIMD4<Double>(m[1][0], m[1][1], m[1][2], 0.0),
		SIMD4<Double>(m[2][0], m[2][1], m[2][2], 0.0),
		SIMD4<Double>(  0.0,     0.0,     0.0,   1.0)
	)
	
	return theMatrix4x4
}


func PrintDocumentDirectoryPathToConsole() {
	
	let thePaths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
	let theDocumentDirectoryPath = thePaths[0]
	print("Document directory: " + theDocumentDirectoryPath.absoluteString)
}
