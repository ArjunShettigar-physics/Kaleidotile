//  KaleidoTileScreenshots.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import SwiftUI


//	Set gGetScreenshotOrientations to true while looking
//	for an aesthetically pleasing matrix for itsOrientation
//	for each type of screenshot, copy your preferred matrix
//	into prepareForAppStoreScreenshot(), and then set
//	gGetScreenshotOrientations back to false before
//	making the screenshots.
//#warning("disable gGetScreenshotOrientations")
let gGetScreenshotOrientations = false

//#warning("disable screenshots")
let gMakeIconScreenshot = false			//	always false in release version
let gMakeAppStoreScreenshots = false	//	always false in release version
let gMakeWebSiteScreenshot = false		//	always false in release version

let gMakeScreenshots = (   gGetScreenshotOrientations
						|| gMakeIconScreenshot
						|| gMakeAppStoreScreenshots
						|| gMakeWebSiteScreenshot)



let gNumAppStoreScreenshots = 6


func preparetoGetScreenshotOrientations(
	modelData: KaleidoTileModel
) {
	modelData.itsOrientation = matrix_identity_double3x3
	modelData.itsIncrement = nil

	modelData.itsTriplePoint = TriplePoint(1.0/3.0, 1.0/3.0, 1.0/3.0)
	modelData.itsTriplePointIncrement = nil
}

func prepareForIconScreenshots(
	modelData: KaleidoTileModel,
	activePanel: Binding<PanelType>
) {
	modelData.itsIncrement = nil
	modelData.itsTriplePointIncrement = nil

	modelData.itsBaseTriangle.reflectionGroup = ReflectionGroup(2,3,5)
	modelData.itsTilingStyle = .flat
	modelData.itsOrientation = simd_double3x3([
		[ 0.9755804787826860, -0.1185630775054341,  0.1848932829244631],
		[-0.1044244127754750, -0.9909406874867690, -0.0844517371031936],
		[-0.1932311347444877, -0.0630820936216463,  0.9791232700889443]])
	modelData.itsTriplePoint = TriplePoint(0.00, 0.88, 0.12)

	modelData.itsFacePaintings[0].style = .solidColor
	modelData.itsFacePaintings[0].color = SIMD4<Float16>(0.50, 0.00, 1.00, 1.00)	//	= default purple

	modelData.itsFacePaintings[1].style = .solidColor
	modelData.itsFacePaintings[1].color = SIMD4<Float16>(1.00, 0.75, 0.00, 1.00)	//	= default yellow

	modelData.itsFacePaintings[2].style = .solidColor
	modelData.itsFacePaintings[2].color = SIMD4<Float16>(0.00, 0.75, 0.25, 1.00)	//	= default green

	modelData.itsFacePaintings[3].style = .solidColor
	modelData.itsFacePaintings[3].color = SIMD4<Float16>(0.75, 0.95, 1.00, 1.00)

	modelData.changeCount += 1
	
	activePanel.wrappedValue = .noPanel
}

func prepareForAppStoreScreenshot(
	_ screenshotIndex: Int,
	modelData: KaleidoTileModel,
	activePanel: Binding<PanelType>,
	optionalRenderer: KaleidoTileRenderer?
) {

	modelData.itsIncrement = nil
	modelData.itsTriplePointIncrement = nil
	
	//	legacy:  TriplePoint(0.0000, 0.9375, 0.0625)
	//	chunky:  TriplePoint(0.00, 0.83, 0.17)
	//
	let theDogTriplePoint = TriplePoint(0.00, 0.88, 0.12)

	switch screenshotIndex {
	
	//	Remember that the iOS Simulator doesn't support wide color,
	//	so avoid extended-range values.
	
	case 0:	//	default colors
	
		modelData.itsBaseTriangle.reflectionGroup = ReflectionGroup(2,3,5)
		modelData.itsTilingStyle = .flat
		modelData.itsOrientation = matrix_identity_double3x3
		modelData.itsTriplePoint = TriplePoint(1.0/3.0, 1.0/3.0, 1.0/3.0)

		modelData.itsFacePaintings[0].style = .solidColor
		modelData.itsFacePaintings[0].color = SIMD4<Float16>(0.50, 0.00, 1.00, 1.00)

		modelData.itsFacePaintings[1].style = .solidColor
		modelData.itsFacePaintings[1].color = SIMD4<Float16>(1.00, 0.75, 0.00, 1.00)

		modelData.itsFacePaintings[2].style = .solidColor
		modelData.itsFacePaintings[2].color = SIMD4<Float16>(0.00, 0.75, 0.25, 1.00)

		modelData.itsFacePaintings[3].style = .solidColor
		modelData.itsFacePaintings[3].color = SIMD4<Float16>(0.75, 0.95, 1.00, 1.00)
		
		activePanel.wrappedValue = .triplePointPanel
	
	case 1:	//	dog spherical

		modelData.itsBaseTriangle.reflectionGroup = ReflectionGroup(2,3,5)
		modelData.itsTilingStyle = .flat
		modelData.itsOrientation = simd_double3x3([
			[ 0.880593955022068,  0.3935280271568014,  0.263988594868544],
			[-0.387550260274607,  0.9186541755237458, -0.076676603692859],
			[-0.272688617546969, -0.0347878949472777,  0.961473203071963]])
		modelData.itsTriplePoint = theDogTriplePoint

		modelData.itsFacePaintings[0].style = .solidColor
		modelData.itsFacePaintings[0].color = SIMD4<Float16>(1.0, 0.9, 0.0, 1.0)
	//	Or keep default purple color.

		modelData.itsFacePaintings[1].style = .solidColor
		modelData.itsFacePaintings[1].color = SIMD4<Float16>(0.0, 1.0, 0.0, 1.0)
	//	Or keep default yellow color.

		modelData.itsFacePaintings[2].style = .texture
		modelData.itsFacePaintings[2].textureSource = .previous

		modelData.itsFacePaintings[3].style = .texture
		modelData.itsFacePaintings[3].textureSource = .builtInBackground(.sky)
		if let theRenderer = optionalRenderer {
			theRenderer.setBackgroundTexture(backgroundTextureIndex: .sky)
		}
		
		activePanel.wrappedValue = .noPanel

	case 2:	//	dog Euclidean

		modelData.itsBaseTriangle.reflectionGroup = ReflectionGroup(2,3,6)
		modelData.itsTilingStyle = .flat
		modelData.itsOrientation = matrix_identity_double3x3
		modelData.itsTriplePoint = theDogTriplePoint

		modelData.itsFacePaintings[0].style = .solidColor
		modelData.itsFacePaintings[0].color = SIMD4<Float16>(1.0, 0.9, 0.0, 1.0)
	//	Or keep default purple color.

		modelData.itsFacePaintings[1].style = .solidColor
		modelData.itsFacePaintings[1].color = SIMD4<Float16>(0.0, 1.0, 0.0, 1.0)
	//	Or keep default yellow color.

		modelData.itsFacePaintings[2].style = .texture
		modelData.itsFacePaintings[2].textureSource = .previous

		modelData.itsFacePaintings[3].style = .invisible
		
		activePanel.wrappedValue = .symmetryAndStylePanel
		
	case 3:	//	dog hyperbolic

		modelData.itsBaseTriangle.reflectionGroup = ReflectionGroup(2,3,7)
		modelData.itsTilingStyle = .curved
		modelData.itsOrientation = matrix_identity_double3x3
		modelData.itsTriplePoint = theDogTriplePoint

		modelData.itsFacePaintings[0].style = .solidColor
		modelData.itsFacePaintings[0].color = SIMD4<Float16>(1.0, 0.9, 0.0, 1.0)
	//	Or keep default purple color.

		modelData.itsFacePaintings[1].style = .solidColor
		modelData.itsFacePaintings[1].color = SIMD4<Float16>(0.0, 1.0, 0.0, 1.0)
	//	Or keep default yellow color.

		modelData.itsFacePaintings[2].style = .texture
		modelData.itsFacePaintings[2].textureSource = .previous

		modelData.itsFacePaintings[3].style = .solidColor
		modelData.itsFacePaintings[3].color = SIMD4<Float16>(0.33, 1.00, 0.33, 1.0)
		
		activePanel.wrappedValue = .noPanel
	
	case 4:	//	Liguria

		modelData.itsBaseTriangle.reflectionGroup = ReflectionGroup(2,3,4)
		modelData.itsTilingStyle = .flat
		modelData.itsOrientation = simd_double3x3([
			[ 0.6514993340836985, 0.7564225469019438, -0.0580822539754969],
			[-0.7518874910737793, 0.6335985491238647, -0.1822582763961936],
			[-0.1010634377768485, 0.1624124659209092,  0.9815336838123360]])
		modelData.itsTriplePoint = TriplePoint(0.2, 0.2, 0.6)

		modelData.itsFacePaintings[0].style = .solidColor
		modelData.itsFacePaintings[0].color = SIMD4<Float16>(1.00, 0.23, 0.22, 1.0)

		modelData.itsFacePaintings[1].style = .texture
		modelData.itsFacePaintings[1].textureSource = .previous

		modelData.itsFacePaintings[2].style = .solidColor
		modelData.itsFacePaintings[2].color = SIMD4<Float16>(1.00, 0.67, 0.00, 1.0)

		modelData.itsFacePaintings[3].style = .texture
		modelData.itsFacePaintings[3].textureSource = .builtInBackground(.water)
		if let theRenderer = optionalRenderer {
			theRenderer.setBackgroundTexture(backgroundTextureIndex: .water)
		}
		
		activePanel.wrappedValue = .facesPanel
	
	case 5:	//	dolphin

		modelData.itsBaseTriangle.reflectionGroup = ReflectionGroup(2,3,3)
		modelData.itsTilingStyle = .curved
		modelData.itsOrientation = matrix_identity_double3x3
		modelData.itsTriplePoint = TriplePoint(0.0, 0.5, 0.5)

		modelData.itsFacePaintings[0].style = .texture
		modelData.itsFacePaintings[0].textureSource = .previous

		modelData.itsFacePaintings[1].style = .solidColor
		modelData.itsFacePaintings[1].color = SIMD4<Float16>(0.00, 0.17, 0.77, 1.0)

		modelData.itsFacePaintings[2].style = .solidColor
		modelData.itsFacePaintings[2].color = SIMD4<Float16>(0.00, 0.75, 1.00, 1.0)

		modelData.itsFacePaintings[3].style = .texture
		modelData.itsFacePaintings[3].textureSource = .builtInBackground(.sand)
		if let theRenderer = optionalRenderer {
			theRenderer.setBackgroundTexture(backgroundTextureIndex: .sand)
		}
		
		activePanel.wrappedValue = .exportPanel

	default:
		preconditionFailure("unexpected screenshotIndex")
	}

	modelData.changeCount += 1
}

func prepareForWebSiteScreenshot(
	modelData: KaleidoTileModel,
	activePanel: Binding<PanelType>,
	optionalRenderer: KaleidoTileRenderer?
) {
	modelData.itsIncrement = nil
	modelData.itsTriplePointIncrement = nil

	modelData.itsBaseTriangle.reflectionGroup = ReflectionGroup(2,3,5)
	modelData.itsTilingStyle = .flat
	modelData.itsOrientation = simd_double3x3([
		[ 0.880593955022068,  0.3935280271568014,  0.263988594868544],
		[-0.387550260274607,  0.9186541755237458, -0.076676603692859],
		[-0.272688617546969, -0.0347878949472777,  0.961473203071963]])
	modelData.itsTriplePoint = TriplePoint(0.00, 0.88, 0.12)

	modelData.itsFacePaintings[0].style = .solidColor
	modelData.itsFacePaintings[0].color = SIMD4<Float16>(  0.56, -0.02,  1.09,  1.00 )
											//	= Linear P3(0.46, 0.0, 1.0, 1.0)

	modelData.itsFacePaintings[1].style = .solidColor
//	modelData.itsFacePaintings[1].color = SIMD4<Float16>( -0.22,  1.04, -0.08,  1.00 )
//											//	= Linear P3(0.0, 1.0, 0.0, 1.0)
	modelData.itsFacePaintings[1].color = SIMD4<Float16>( -0.11,  0.52,  1.06,  1.00 )
											//	= Linear P3(0.0, 0.5, 1.0, 1.0)

	modelData.itsFacePaintings[2].style = .texture
	modelData.itsFacePaintings[2].textureSource = .previous

	modelData.itsFacePaintings[3].style = .texture
	modelData.itsFacePaintings[3].textureSource = .builtInBackground(.sand)
	if let theRenderer = optionalRenderer {
		theRenderer.setBackgroundTexture(backgroundTextureIndex: .sand)
	}
		
	activePanel.wrappedValue = .facesPanel

	modelData.changeCount += 1
}
