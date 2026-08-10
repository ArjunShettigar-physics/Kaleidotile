//  KaleidoTileCIScreenshot.swift
//
//	Support for taking screenshots from a headless CI pipeline
//	(see .github/workflows/build.yml), with no human present to
//	click through the UI, and no on-screen window required either.
//
//	Two deliberate design choices, both aimed at reusing existing,
//	already-working machinery instead of adding new fragile paths:
//
//	1)	The tiling is configured by setting the model's state directly
//		(reflection group, camera orientation) -- exactly the same
//		approach KaleidoTileScreenshots.swift's prepareForAppStoreScreenshot()
//		etc. already use -- rather than simulating taps or drags.
//		The "pan" is produced by calling the very same
//		translationAlongGeodesic() function the live drag gesture uses
//		(see KaleidoTileGestures.swift), so it's guaranteed to be a
//		mathematically valid isometry rather than a hand-rolled matrix.
//
//	2)	The image itself comes from GeometryGamesRenderer.createOffscreenImage(),
//		the same offscreen Metal render path the app's own Export panel
//		already uses (see GeometryGamesExportView.swift). This renders
//		directly to a CGImage in-process -- it does NOT depend on the
//		app's window being visible, focused, or even on-screen, and it
//		does NOT need the macOS "Screen Recording" permission that a
//		`screencapture`-based approach would require (and which fresh,
//		ephemeral GitHub Actions runners do not have pre-granted).
//
//	Everything here is controlled by environment variables so that
//	parameters (which p,q,r to render, how far to pan, which direction,
//	image size) can be changed from the GitHub Actions "Run workflow"
//	form, with no code or YAML editing required to try a different tiling.

import SwiftUI


let gCIScreenshotMode =
	ProcessInfo.processInfo.environment["KALEIDOTILE_CI_SCREENSHOT"] != nil


func prepareForCIScreenshot(
	modelData: KaleidoTileModel,
	activePanel: Binding<PanelType>,
	renderer: KaleidoTileRenderer
) {
	let theEnv = ProcessInfo.processInfo.environment

	let p = Int(theEnv["KALEIDOTILE_P"] ?? "") ?? 18
	let q = Int(theEnv["KALEIDOTILE_Q"] ?? "") ?? 2
	let r = Int(theEnv["KALEIDOTILE_R"] ?? "") ?? 4

	//	Hyperbolic distance to pan the camera away from the base
	//	triangle's incenter. 0.0 leaves the original (unpanned) view.
	let thePanDistance = Double(theEnv["KALEIDOTILE_PAN_DISTANCE"] ?? "") ?? 4.0

	//	Direction to pan in, as an angle in degrees within the
	//	tangent plane at the origin. 0 and multiples of 90 are
	//	reasonable first guesses; adjust and re-run to taste.
	let thePanAngleDegrees = Double(theEnv["KALEIDOTILE_PAN_ANGLE_DEGREES"] ?? "") ?? 0.0
	let thePanAngleRadians = thePanAngleDegrees * Double.pi / 180.0

	let theImageSizePx = Int(theEnv["KALEIDOTILE_IMAGE_SIZE_PX"] ?? "") ?? 2048
	let theOutputPath = theEnv["KALEIDOTILE_SCREENSHOT_PATH"] ?? "kaleidotile-screenshot.png"

	modelData.itsIncrement = nil
	modelData.itsTriplePointIncrement = nil

	modelData.itsBaseTriangle.reflectionGroup = ReflectionGroup(p, q, r)
	modelData.itsTilingStyle = .curved

	if thePanDistance != 0.0 {
		let theAxis = SIMD3<Double>(
			cos(thePanAngleRadians),
			sin(thePanAngleRadians),
			0.0)

		modelData.itsOrientation = translationAlongGeodesic(
			axis: theAxis,
			θ: thePanDistance,
			geometry: modelData.itsBaseTriangle.geometry)
	} else {
		modelData.itsOrientation = matrix_identity_double3x3
	}

	activePanel.wrappedValue = .noPanel

	modelData.changeCount += 1

#if os(macOS)
	attemptCIScreenshotCapture(
		modelData: modelData,
		renderer: renderer,
		widthPx: theImageSizePx,
		heightPx: theImageSizePx,
		outputPath: theOutputPath,
		attemptsRemaining: 6)
#endif
}


#if os(macOS)
//	Retries with a short delay because, at the moment onAppear() first
//	fires, the renderer's underlying MTKView may not have fully attached
//	its Metal device yet. createOffscreenImage() returning nil is the
//	signal to wait and try again rather than fail immediately.
func attemptCIScreenshotCapture(
	modelData: KaleidoTileModel,
	renderer: KaleidoTileRenderer,
	widthPx: Int,
	heightPx: Int,
	outputPath: String,
	attemptsRemaining: Int
) {
	DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {

		let theClampedWidthPx  = renderer.clampImageSize(requestedSizePx: widthPx)
		let theClampedHeightPx = renderer.clampImageSize(requestedSizePx: heightPx)

		let theOptionalCGImage = renderer.createOffscreenImage(
			modelData: modelData,
			widthPx: theClampedWidthPx,
			heightPx: theClampedHeightPx,
			transparentBackground: false,
			extraRenderFlag: nil)

		guard
			let theCGImage = theOptionalCGImage,
			let theColorSpace = CGColorSpace(name: CGColorSpace.displayP3)
		else {
			if attemptsRemaining > 1 {
				logToStderr("KaleidoTile CI screenshot: renderer not ready yet, " +
							"retrying (\(attemptsRemaining - 1) attempts left)...")
				attemptCIScreenshotCapture(
					modelData: modelData,
					renderer: renderer,
					widthPx: widthPx,
					heightPx: heightPx,
					outputPath: outputPath,
					attemptsRemaining: attemptsRemaining - 1)
			} else {
				logToStderr("KaleidoTile CI screenshot: FAILED to render an image " +
							"after all retries.")
				exit(1)
			}
			return
		}

		let theCIContext = CIContext()
		let theCIImage = CIImage(cgImage: theCGImage)
		guard let thePNGData = theCIContext.pngRepresentation(
			of: theCIImage,
			format: .RGBA8,
			colorSpace: theColorSpace)
		else {
			logToStderr("KaleidoTile CI screenshot: failed to encode PNG data.")
			exit(1)
		}

		do {
			try thePNGData.write(to: URL(fileURLWithPath: outputPath))
			print("KaleidoTile CI screenshot: wrote \(thePNGData.count) bytes to \(outputPath)")
			exit(0)
		} catch {
			logToStderr("KaleidoTile CI screenshot: failed to write file: \(error)")
			exit(1)
		}
	}
}

func logToStderr(_ message: String) {
	FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}
#endif
