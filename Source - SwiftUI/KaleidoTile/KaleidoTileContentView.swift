//	KaleidoTileContentView.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import SwiftUI
import PhotosUI	//	for PhotosPicker
import UniformTypeIdentifiers	//	for UTType


// MARK: -
// MARK: Main View

enum PanelType {
	case noPanel
	case symmetryAndStylePanel
	case triplePointPanel
	case facesPanel
	case optionsPanel
	case exportPanel
	case helpMenuPanel
	case helpPanel
	case contactPanel
	case translatorsPanel
	
	var iconName: String {	//	name of built-in SF Symbol
	
		switch self {
		
		case .noPanel:
			return "n/a"
			
		case .symmetryAndStylePanel:
			return "cube"
			
		case .triplePointPanel:
			return "triangle"
			
		case .facesPanel:
			return "paintpalette"
			
		case .optionsPanel:
			return "switch.2"
			
		case .exportPanel:
			return "square.and.arrow.up"
			
		case .helpMenuPanel:
			return "questionmark.circle"
			
		case .helpPanel:
			return "questionmark.circle"
			
		case .contactPanel, .translatorsPanel:
			return "n/a"
		}
	}
}


struct KaleidoTileContentView: View {

	@State var itsModelData = KaleidoTileModel()

	//	Whenever itsArchimedeanSolidName gets set,
	//	an onChange(of:) block will set a timer to clear it
	//	after a few seconds.
	@State var itsArchimedeanSolidName: LocalizedStringKey? = nil
	@State var itsNameOpacity: Double = 0.0
	@State var itsNameFadingTimer: Timer? = nil
										
	@State var itsActivePanel: PanelType = .noPanel
	
	@AppStorage("Inertia") var itsInertia: Bool = true

	@State var itsRenderer = KaleidoTileRenderer()

	@GestureState var previousPoint: SIMD3<Double>? = nil
		//	on unit-radius sphere, Euclidean plane, or hyperboloid

	@GestureState var previousAngle: Double = 0.0	//	in radians

	//	To make App Store screenshots, set gMakeAppStoreScreenshots = true.
	@State var itsScreenshotIndex: Int = 0	//	used only when making screenshots


	var body: some View {

		let theTranslatorThanks = [
			GeometryGamesTranslatorThanks(pre: "diolch i", name: "Gareth Roberts", post: nil, lang: "cy"),
			GeometryGamesTranslatorThanks(pre: "mit Dank an", name: "Stas Drisner", post: nil, lang: "de"),
			GeometryGamesTranslatorThanks(pre: "merci à", name: "Jean-Michel Celibert", post: nil, lang: "fr"),
			GeometryGamesTranslatorThanks(pre: "grazie ad", name: "Angelo Contardi", post: nil, lang: "it"),
			GeometryGamesTranslatorThanks(pre: nil, name: "竹内建氏に", post: "感謝します", lang: "ja"),
			GeometryGamesTranslatorThanks(pre: nil, name: "박하은학생에게", post: "감사", lang: "ko"),
			GeometryGamesTranslatorThanks(pre: "obrigado ao", name: "Atractor", post: nil, lang: "pt"),
			GeometryGamesTranslatorThanks(pre: "感谢", name: "焦堂生", post: nil, lang: "zh-Hans"),
		]
		
		let theToolbarPadding = 4.0
		
#if os(iOS)
		let theEdgesToExpandFromSafeArea: Edge.Set = .all
#endif
#if os(macOS)
		let theEdgesToExpandFromSafeArea: Edge.Set = .bottom
#endif

		ZStack(alignment: .bottom) {
		
			//	Main animation view
			if let theRenderer = itsRenderer {
				
				GeometryReader() { geometryReaderProxy in
				
					GeometryGamesViewRep(
						modelData: itsModelData,
						renderer: theRenderer,
						extraRenderFlag: false,	//	render the whole tiling as usual
						isOpaque: true
					)
					//
					//	Gesture order matters:
					//		SwiftUI considers each Gesture only after
					//		all preceding gestures have failed.
					//
					.gesture(kaleidoTileDragGesture(
								modelData: itsModelData,
								viewSize: geometryReaderProxy.size,
								inertia: itsInertia,
								previousPoint: $previousPoint))
					.gesture(kaleidoTileRotateGesture(
								modelData: itsModelData,
								previousAngle: $previousAngle))
					.gesture(
						TapGesture()
						.onEnded() { _ in
							if itsActivePanel != .noPanel {
								itsActivePanel = .noPanel
							} else {
								itsModelData.itsIncrement = nil
							}
						}
					)
				}
				.ignoresSafeArea(edges: theEdgesToExpandFromSafeArea)
			}
			
			Group() {
				if let theArchimedeanSolidName = itsArchimedeanSolidName {
					Text(theArchimedeanSolidName)
					.font(.title)
					.opacity(itsNameOpacity)
					.padding(EdgeInsets(top: 16.0, leading: 0.0, bottom: 0.0, trailing: 0.0))
					.frame(maxHeight: .infinity, alignment: .top)
				}
			}
			.onChange(of: itsArchimedeanSolidName) {
				itsNameOpacity = 1.0
				itsNameFadingTimer?.invalidate()
				itsNameFadingTimer = itsArchimedeanSolidName != nil ?
					Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { timer in
						Task { @MainActor in
							withAnimation() {
								itsNameOpacity = 0.0
							}
							itsNameFadingTimer = nil
						}
					} :
					nil
				itsNameFadingTimer?.tolerance = 1.0
			}
			
			VStack() {
			
				Group() {
				
					//	Note:  Some of the panels get leading-aligned, others trailing-aligned.
					switch itsActivePanel {
					
					case .noPanel:
						Spacer()
						
					case .symmetryAndStylePanel:
						SymmetryAndStyleView(
							modelData: itsModelData,
							archimedeanSolidName: $itsArchimedeanSolidName)
						.frame(maxWidth: .infinity, alignment: .leading)
					
					case .triplePointPanel:
						TriplePointView(
							modelData: itsModelData,
							optionalRenderer: itsRenderer,
							inertia: itsInertia,
							archimedeanSolidName: $itsArchimedeanSolidName)
						.frame(maxWidth: .infinity, alignment: .leading)
						
					case .facesPanel:
						FacesView(
							modelData: itsModelData,
							optionalRenderer: itsRenderer)
						.frame(maxWidth: .infinity, alignment: .leading)
						
					case .optionsPanel:
						OptionsView(
							modelData: itsModelData,
							inertia: $itsInertia)
						.frame(maxWidth: .infinity, alignment: .leading)
						.onChange(of: itsInertia) {
							itsModelData.itsIncrement = nil
							itsModelData.itsTriplePointIncrement = nil
						}
						
					case .exportPanel:
						if let theRenderer = itsRenderer {
							GeometryGamesExportView(
								modelData: itsModelData,
								exportRenderer: theRenderer,
								caption: "KaleidoTile image")
							.frame(maxWidth: .infinity, alignment: .trailing)
						} else {
							Text("Renderer not available")
						}
						
					case .helpMenuPanel:
						HelpMenuView(activePanel: $itsActivePanel)
						.frame(maxWidth: .infinity, alignment: .trailing)
						
					case .helpPanel:
						KaleidoTileHelpView()
						.frame(maxWidth: .infinity, alignment: .trailing)
						
					case .contactPanel:
						GeometryGamesContactView()
						.frame(maxWidth: .infinity, alignment: .trailing)
						
					case .translatorsPanel:
						GeometryGamesTranslatorsView(theTranslatorThanks)
						.frame(maxWidth: .infinity, alignment: .trailing)
					}
				}

				HStack() {
				
					HStack() {
						PanelSelectorButton(requestedPanel: .symmetryAndStylePanel, activePanel: $itsActivePanel)
						PanelSelectorButton(requestedPanel: .triplePointPanel, activePanel: $itsActivePanel)
						PanelSelectorButton(requestedPanel: .facesPanel, activePanel: $itsActivePanel)
						PanelSelectorButton(requestedPanel: .optionsPanel, activePanel: $itsActivePanel)
					}
					.padding(theToolbarPadding)
					.background(gSystemBackgroundColor)
					.cornerRadius(geometryGamesCornerRadius)
					
					Spacer()

					HStack() {
						PanelSelectorButton(requestedPanel: .exportPanel, activePanel: $itsActivePanel)
						HelpMenuButton(activePanel: $itsActivePanel)
					}
					.padding(theToolbarPadding)
					.background(gSystemBackgroundColor)
					.cornerRadius(geometryGamesCornerRadius)
				}
				.modifier(applyForegroundAccentColorOnMacOS())
			}
			.modifier(buttonStyleOnMacOS())
			.padding(geometryGamesPanelMargin)	//	= geometryGamesControlInset
			.frame(maxHeight: .infinity, alignment: .bottom)

			if gMakeAppStoreScreenshots {
			
				//	The Rectangle will respond to taps
				//	only if it's at least a tiny bit opaque.
				Rectangle()
				.foregroundStyle(Color(.displayP3,
									red: 0.0,
									green: 0.0,
									blue: 0.0,
									opacity: 0.000000000001))
				.ignoresSafeArea()
				.onTapGesture {
					itsScreenshotIndex = (itsScreenshotIndex + 1) % gNumAppStoreScreenshots
				}
			}
		}
#if targetEnvironment(simulator)
		.statusBar(hidden: gMakeScreenshots)
#endif
		.onAppear() {
			if gGetScreenshotOrientations {
				preparetoGetScreenshotOrientations(
					modelData: itsModelData)
			}
			if gMakeIconScreenshot {
				prepareForIconScreenshots(
					modelData: itsModelData,
					activePanel: $itsActivePanel)
			}
			if gMakeAppStoreScreenshots {
				prepareForAppStoreScreenshot(
					itsScreenshotIndex,
					modelData: itsModelData,
					activePanel: $itsActivePanel,
					optionalRenderer: itsRenderer)
			}
			if gCIScreenshotMode {
				prepareForCIScreenshot(
					modelData: itsModelData,
					activePanel: $itsActivePanel,
					renderer: itsRenderer)
			}
			if gMakeWebSiteScreenshot {
				prepareForWebSiteScreenshot(
					modelData: itsModelData,
					activePanel: $itsActivePanel,
					optionalRenderer: itsRenderer)
			}
		}
		.onChange(of: itsScreenshotIndex) {
			prepareForAppStoreScreenshot(
				itsScreenshotIndex,
				modelData: itsModelData,
				activePanel: $itsActivePanel,
				optionalRenderer: itsRenderer)
		}
	}
}

struct PanelSelectorButton: View {

	let requestedPanel: PanelType
	@Binding var activePanel: PanelType

	var body: some View {

		Button {
			activePanel = activePanel != requestedPanel ? requestedPanel : .noPanel
		} label: {
			Image(systemName: requestedPanel.iconName)
				.font(.title)
				.padding(geometryGamesControlPadding)
		}
	}
}

struct HelpMenuButton: View {

	@Binding var activePanel: PanelType

	var body: some View {

		Button {
			activePanel = activePanel == .helpMenuPanel ? .noPanel : .helpMenuPanel
		} label: {
			Image(systemName: PanelType.helpMenuPanel.iconName)
				.font(.title)
				.padding(geometryGamesControlPadding)
				.background(geometryGamesTappableClearColor)
		}
	}
}

struct HelpMenuView: View {

	@Binding var activePanel: PanelType

	var body: some View {

		VStack(alignment: .leading, spacing: 8.0) {

			Button() {
				activePanel = .helpPanel
			} label: {
				//	The Help panel title can stay in English,
				//	because the Help panel itself is always in English.
				Label("Tilings and Symmetry", systemImage: PanelType.helpPanel.iconName)
			}

			Button() {
				activePanel = .contactPanel
			} label: {
				GeometryGamesHelpMenuContactItemLabel()
			}

			Button() {
				activePanel = .translatorsPanel
			} label: {
				GeometryGamesHelpMenuTranslatorsItemLabel()
			}
		}
		.modifier(helpMenuStyle())
	}
}


// MARK: -
// MARK: Symmetry and Style

struct SymmetryAndStyleView: View {

	@Bindable var modelData: KaleidoTileModel
	@Binding var archimedeanSolidName: LocalizedStringKey?

	@State var showMoreSymmetryGroups: Bool = false


	var body: some View {

		let group = modelData.itsBaseTriangle.reflectionGroup
		
		let tilingIs22n = (group.p == 2 ? 1 : 0) + (group.q == 2 ? 1 : 0) + (group.r == 2 ? 1 : 0) >= 2
		
		func updateArchimedeanName(	//	used only with "Other triangle group"
			buttonIsDown: Bool
		) {
			if buttonIsDown {
				archimedeanSolidName = nil	//	tiling may change several time while button is down
			} else {
				archimedeanSolidName = archimedeanName(modelData: modelData)
			}
		}

		return VStack(spacing: 8.0) {
		
			Text("Symmetry")

			ForEach(3 ..< 8) { i in

				Button(
					action: {
						withAnimation() {
							modelData.itsBaseTriangle.reflectionGroup = ReflectionGroup(2,3,i)
						}
						archimedeanSolidName = archimedeanName(modelData: modelData)
					},
					label: {
						HStack() {
										
							Image("Table Images/Symmetry/23\(i)")
							
							Text("Triangle group △(\(2), \(3), \(i))")
							.modifier(applyForegroundAccentColorOnMacOS())
						}
						Spacer()
						if group.p == 2 && group.q == 3 && group.r == i {
							Text("✓")
							.foregroundStyle(Color.primary)
						}
					}
				)
			}
			
			Button(
				action: {
					withAnimation() {
						showMoreSymmetryGroups.toggle()
					}
				},
				label: {
					HStack() {
						
						Image("Table Images/Symmetry/Other")
						
						Text("Other triangle group")
						.modifier(applyForegroundAccentColorOnMacOS())
					}
					Spacer()
					Image(systemName: showMoreSymmetryGroups ? "chevron.down" : "chevron.forward")
					.foregroundStyle(Color.primary)
				}
			)

			if showMoreSymmetryGroups {

				HStack() {
				
					Stepper(
						"\(group.p)",
						value: $modelData.itsBaseTriangle.reflectionGroup.p.animation(),
						in: 2...18,
						onEditingChanged: updateArchimedeanName)
						
					Stepper(
						"\(group.q)",
						value: $modelData.itsBaseTriangle.reflectionGroup.q.animation(),
						in: 2...18,
						onEditingChanged: updateArchimedeanName)
						
					Stepper(
						"\(group.r)",
						value: $modelData.itsBaseTriangle.reflectionGroup.r.animation(),
						in: 2...18,
						onEditingChanged: updateArchimedeanName)
				}
				.monospacedDigit()
			}
			
			Spacer()
			.frame(width: 1.0, height: 2.0)
			.frame(maxWidth: .infinity, alignment: .center)

			Text("Style")
			
			ForEach(TilingStyle.allCases) { style in

				Button(
					action: {
						withAnimation() {
							modelData.itsTilingStyle = style
						}
					},
					label: {
						HStack() {

							let theSystemImageName = (style == .flat ? "pentagon" : "circle")
							Image(systemName: theSystemImageName)
								.font(.title)
								.foregroundStyle(Color.secondary)
								.frame(width: 32.0, alignment: .center)	//	to align with Symmetry images

							let theLabelKey: LocalizedStringKey = (style == .flat ?
								"Polyhedron" :
								curvedStyleLabelKey(geometry: modelData.itsBaseTriangle.geometry) )
							Text(theLabelKey)
							.modifier(applyForegroundAccentColorOnMacOS())
							
							Spacer()

							if modelData.itsBaseTriangle.geometry != .euclidean
							&& !tilingIs22n
							&& style == modelData.itsTilingStyle {
								Text("✓")
								.foregroundStyle(Color.primary)
							}
						}
					}
				)
				.disabled(
					(
						modelData.itsBaseTriangle.geometry == .euclidean
					 ||
						tilingIs22n
					)
					&&
						!gMakeScreenshots
				)
			}
		}
		.fixedSize()
		.padding(geometryGamesPanelPadding)
		.background(gSystemBackgroundColor)
		.cornerRadius(geometryGamesCornerRadius)
	}
	
	func curvedStyleLabelKey(
		geometry: GeometryType
	) -> LocalizedStringKey {
	
		switch modelData.itsBaseTriangle.geometry {
		case .spherical:	return "Tiling of sphere"
		case .euclidean:	return "Tiling of Euclidean plane"
		case .hyperbolic:	return "Tiling of hyperbolic plane"
		}
	}
}


// MARK: -
// MARK: Triple point

struct TriplePointView: View {

	var modelData: KaleidoTileModel
	let optionalRenderer: KaleidoTileRenderer?
	let inertia: Bool
	@Binding var archimedeanSolidName: LocalizedStringKey?

	var body: some View {
	
		Group() {
		
			if let theRenderer = optionalRenderer {
			
				GeometryReader() { geometryReaderProxy in
				
					GeometryGamesViewRep(
						modelData: modelData,
						renderer: theRenderer,
						extraRenderFlag: true,	//	render the base triangle only
						isOpaque: false,
						isMainView: false	//	The main view updates the model,
							//	so if this TriplePointView updated it as well,
							//	the animation would run twice as fast.
					)
					.gesture(triplePointDragGesture(
						modelData: modelData,
						viewSize: geometryReaderProxy.size,
						inertia: inertia,
						archimedeanSolidName: $archimedeanSolidName))
				}

			} else {
				Text("Couldn't load Triple Point view")
			}
		}
		.frame(width: 320.0, height: 320.0)
		.cornerRadius(geometryGamesCornerRadius)
		.padding(8.0)
		.background(gSystemBackgroundColor.opacity(0.75))
		.cornerRadius(geometryGamesCornerRadius)
	}
}


// MARK: -
// MARK: Faces

enum FaceIndex: Int, CaseIterable, Identifiable {

	//	Raw values get used as array indices,
	//	so they must be 0...3
	case faceA		= 0
	case faceB		= 1
	case faceC		= 2
	case background	= 3

	var id: Int { self.rawValue }
	
	var name: LocalizedStringKey {
		switch self {
		case .faceA:		return "Face A"
		case .faceB:		return "Face B"
		case .faceC:		return "Face C"
		case .background:	return "Background"
		}
	}
}

enum BackgroundTextureIndex: Int, CaseIterable, Identifiable {

	case sky
	case wood
	case grass
	case sand
	case stone
	case tatami
	case moss
	case water
	case straw

	var id: Int { self.rawValue }
	
	var name: String {
		switch self {
			case .sky:		return "Sky"
			case .wood:		return "Wood"
			case .grass:	return "Grass"
			case .sand:		return "Sand"
			case .stone:	return "Stone"
			case .tatami:	return "Tatami"
			case .moss:		return "Moss"
			case .water:	return "Water"
			case .straw:	return "Straw"
		}
	}
	
	var textureName: String {
		"background - " + name.lowercased()
	}
	
	//	Unlike the regular faces, the background uses a tileable texture.
	//	How many times (on average) should it repeat in each direction?
	var texReps: Double {
		switch self {
			case .sky:		return 1.0
			case .wood:		return 3.0
			case .grass:	return 8.0
			case .sand:		return 3.0
			case .stone:	return 3.0
			case .tatami:	return 6.0
			case .moss:		return 2.0
			case .water:	return 3.0
			case .straw:	return 3.0
		}
	}
}

//	Note:  Only .sky has a ready-to-use thumbnail in
//
//		KaleidoTileAssets.xcassets/Thumbnails
//
//	so if you change the defaultBackground you'll also
//	need to prepare a thumbnail image for the new default.
//
let defaultBackground: BackgroundTextureIndex = .sky	//	see Note immediately above

struct FacesView: View {

	var modelData: KaleidoTileModel
	let optionalRenderer: KaleidoTileRenderer?

	@ScaledMetric var viewWidth = 288.0
#if os(iOS)
	@ScaledMetric var viewHeight = 288.0
#endif
#if os(macOS)
	@ScaledMetric var viewHeight = 264.0
#endif

	var body: some View {
	
		//	The renderer should always be present.
		//	s = width = height, in points.
		//	Currently 40.0 pts.
		let s = optionalRenderer?.textureThumbnailSizePt() ?? 8.0

		return Group() {
		
			if gMakeAppStoreScreenshots {
			
				FaceDecorationView(
					modelData: modelData,
					faceIndex: FaceIndex.faceA,
					optionalRenderer: optionalRenderer)
				
			} else {
			
				NavigationStack() {

					Text("Decoration")
					.font(.title3)

					VStack(spacing: 16.0) {
					
						ForEach(FaceIndex.allCases) { faceIndex in
						
							NavigationLink(
								destination:
								
									FaceDecorationView(
										modelData: modelData,
										faceIndex: faceIndex,
										optionalRenderer: optionalRenderer
									)
									.padding(EdgeInsets(top: 0.0, leading: 8.0, bottom: 0.0, trailing: 8.0)),
								
								label: {
								
									HStack() {
									
										switch modelData.itsFacePaintings[faceIndex.rawValue].style {
										
										case .solidColor:
											Rectangle()
											.foregroundStyle(makeSwiftUIColor(from: modelData.itsFacePaintings[faceIndex.rawValue].color))
											.frame(width: s, height: s)
											.cornerRadius(4.0)
											
										case .texture:
										
											switch modelData.itsFacePaintings[faceIndex.rawValue].textureSource {
										
											case .fromCamera, .fromPhotoLibrary, .fromFiles, .fromPasteboard, .previous:
											
												if let theRenderer = optionalRenderer {
													let theThumbnail = theRenderer.textureThumbnail(
																		faceIndex: faceIndex)
													Image(
														decorative: theThumbnail.cgImage,
														scale: theThumbnail.scale,
														orientation: theThumbnail.orientation)
													.cornerRadius(4.0)
												} else {
													Rectangle()	//	should never be needed
													.foregroundStyle(Color.gray)
													.frame(width: s, height: s)
													.cornerRadius(4.0)
												}
											
											case .builtInBackground(let backgroundTextureIndex):
											
												Image("Table Images/Background/"
														+ backgroundTextureIndex.name)
												.cornerRadius(4.0)
											}
											
										case .invisible:
											Rectangle()
											.foregroundStyle(Color.clear)
											.frame(width: s, height: s)
										}
										
										Text(faceIndex.name)
										.modifier(applyForegroundAccentColorOnMacOS())
										
										Spacer()	//	makes whole row tappable
									}
								}
							)
						}
					}
					.padding(EdgeInsets(top: 0.0, leading: 8.0, bottom: 0.0, trailing: 8.0))
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
				}
			}
		}
		.frame(width: viewWidth, height: viewHeight)
			//	There's no way to size a NavigationStack() to its content.
		.padding(12.0)
		.background(gSystemBackgroundColor)
		.cornerRadius(geometryGamesCornerRadius)
	}
}
	
let buttonImageFrameWidth = 64.0
let buttonImageFrameHeight = 40.0

struct FaceDecorationView: View {

	var modelData: KaleidoTileModel
	let faceIndex: FaceIndex
	let optionalRenderer: KaleidoTileRenderer?
	
	@Environment(\.dismiss) private var dismiss

	@ScaledMetric var gridCellWidth = 80.0
	@ScaledMetric var gridCellHeight = 80.0

	var body: some View {
	
		let theFaceColorButton
			= FaceColorButton(
				modelData: modelData,
				faceIndex: faceIndex,
				gridCellWidth: gridCellWidth,
				gridCellHeight: gridCellHeight)

#if os(iOS)
		let theFaceCameraButton
			= FaceCameraButton(
				modelData: modelData,
				faceIndex: faceIndex,
				optionalRenderer: optionalRenderer,
				gridCellWidth: gridCellWidth,
				gridCellHeight: gridCellHeight)
#endif
#if os(macOS)
		//	The camera is less useful on macOS: users could
		//	have fun taking selfies of themselves and their friends,
		//	but the Mac's built-in camera isn't good for much else.
		//	Moreover, the API for using a Mac's camera is a lot
		//	more complicted than the API for using an iPhone
		//	or iPad's camera -- the Mac's API is really more
		//	orientated for capturing video. So let's just omit
		//	KaleidoTile's image-from-camera feature when
		//	running on macOS.
#endif
		
		let theFacePhotoPickerButton
			= FacePhotoPickerButton(
				modelData: modelData,
				faceIndex: faceIndex,
				optionalRenderer: optionalRenderer,
				gridCellWidth: gridCellWidth,
				gridCellHeight: gridCellHeight)

		let theFaceFilesButton
			= FaceFilesButton(
				modelData: modelData,
				faceIndex: faceIndex,
				optionalRenderer: optionalRenderer,
				gridCellWidth: gridCellWidth,
				gridCellHeight: gridCellHeight)
		
		let theFacePasteButton
			= FacePasteButton(
				modelData: modelData,
				faceIndex: faceIndex,
				optionalRenderer: optionalRenderer,
				gridCellWidth: gridCellWidth,
				gridCellHeight: gridCellHeight)
		
		let theFacePreviousButton
			= FacePreviousButton(
				modelData: modelData,
				faceIndex: faceIndex,
				gridCellWidth: gridCellWidth,
				gridCellHeight: gridCellHeight)
		
		let theFaceInvisibleButton
			= FaceInvisibleButton(
				modelData: modelData,
				faceIndex: faceIndex,
				gridCellWidth: gridCellWidth,
				gridCellHeight: gridCellHeight)

		VStack(alignment: .center, spacing: 16.0) {

			ZStack(alignment: .center) {
			
				Text(faceIndex.name)
				.font(.title3)
				
				Button() {
					dismiss()
				} label: {
					Image(systemName: "chevron.backward")
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}

			if faceIndex != .background {
			
#if os(iOS)
				Grid() {
					GridRow() {
						theFaceColorButton
						theFaceCameraButton
						theFacePhotoPickerButton
					}
					GridRow() {
						theFaceFilesButton
						theFacePasteButton
						theFacePreviousButton
					}
					GridRow() {
						Rectangle()	//	skips first grid cell
							.hidden()
							.frame(
								width: gridCellWidth,
								height: gridCellHeight,
								alignment: .top)
						theFaceInvisibleButton
					}
				}
#endif
#if os(macOS)
				Grid() {
					GridRow() {
						theFaceColorButton
						theFacePhotoPickerButton
						theFaceFilesButton
					}
					GridRow() {
						theFacePasteButton
						theFacePreviousButton
						theFaceInvisibleButton
					}
				}
				.modifier(applyForegroundAccentColorOnMacOS())
#endif
				
			} else {	//	faceIndex == .background
			
				VStack(spacing: 0.0) {
				
					Grid(
						//	Each button is enclosed in a fixed-size frame,
						//	so there's no need for any extra spacing.
						horizontalSpacing: 0.0,
						verticalSpacing: 0.0
					) {
					
						GridRow() {
						
							BackgroundTextureButton(
								modelData: modelData,
								backgroundTextureIndex: .sky,
								optionalRenderer: optionalRenderer)
								
							BackgroundTextureButton(
								modelData: modelData,
								backgroundTextureIndex: .wood,
								optionalRenderer: optionalRenderer)
								
							BackgroundTextureButton(
								modelData: modelData,
								backgroundTextureIndex: .grass,
								optionalRenderer: optionalRenderer)
								
							BackgroundTextureButton(
								modelData: modelData,
								backgroundTextureIndex: .sand,
								optionalRenderer: optionalRenderer)
								
							BackgroundTextureButton(
								modelData: modelData,
								backgroundTextureIndex: .stone,
								optionalRenderer: optionalRenderer)
						}
						
						GridRow() {
						
							BackgroundTextureButton(
								modelData: modelData,
								backgroundTextureIndex: .tatami,
								optionalRenderer: optionalRenderer)
								
							BackgroundTextureButton(
								modelData: modelData,
								backgroundTextureIndex: .moss,
								optionalRenderer: optionalRenderer)
								
							BackgroundTextureButton(
								modelData: modelData,
								backgroundTextureIndex: .water,
								optionalRenderer: optionalRenderer)
								
							BackgroundTextureButton(
								modelData: modelData,
								backgroundTextureIndex: .straw,
								optionalRenderer: optionalRenderer)
						}
					}
					.fixedSize()	//	Avoids truncating captions.
					
					FaceColorButton(
						modelData: modelData,
						faceIndex: .background,
						gridCellWidth: gridCellWidth,
						gridCellHeight: gridCellHeight)
				}
				.modifier(applyForegroundAccentColorOnMacOS())
			}
		}
		.navigationBarBackButtonHidden()
		.frame(maxHeight: .infinity, alignment: .top)
	}
}

struct FaceColorButton: View {

	var modelData: KaleidoTileModel
	let faceIndex: FaceIndex
	let gridCellWidth: Double
	let gridCellHeight: Double

	//	On the one hand, KaleidoTile works with
	//	premultiplied linear extended-range sRGB colors,
	//	because they're what the GPU expects.
	//	On the other hand, the SwiftUI ColorPicker
	//	insists on a binding to a SwiftUI Color.
	@State var colorPickerColorAsSwiftUIColor: Color = .black	//	overwritten in onAppear()

	var body: some View {
	
		ZStack(alignment: .top) {

			//	Tapping the Button label selects the pre-existing color.
			Button(
				action: {
					modelData.itsFacePaintings[faceIndex.rawValue].style = .solidColor
					modelData.changeCount += 1
				},
				label: {
					VStack(spacing: 4.0) {
						
						Group() {
							if modelData.itsFacePaintings[faceIndex.rawValue].style == .solidColor
							{
								//	Include a Spacer that will sit underneath
								//	the ColorPicker in the ZStack.
								Spacer()
								
							} else {	//	style ≠ .solidColor
								Image("Table Images/Face Decoration/Color Wheel")
							}
						}
						.frame(
							width: buttonImageFrameWidth,
							height: buttonImageFrameHeight,
							alignment: .center)
					
						Text(faceIndex == .background ? "Solid Color 1" : "Solid Color 2")
						.font(.caption)
						.multilineTextAlignment(.center)
						.fixedSize()	//	prevents text truncation
					}
				}
			)

			//	Tapping the ColorPicker() lets the user select a new color.
			//
			//		Note: I would have liked to have left the ColorPicker's
			//		own button visible at all times, but it wasn't behaving
			//		as desired. If the face were, say, Invisible and the user
			//		tapped the ColorPicker's own button without first tapping
			//		our own text-labelled button (see immediately above),
			//		the ColorPicker would appear as expected, but SwiftUI
			//		would rebuild our View and leave the ColorPicker bound
			//		to an old copy of our @State variable. @State variables
			//		should persist across View rebuilds, but somehow that
			//		seemed not to be happening when the user switched
			//		from Invisible to Solid Color by tapping directly
			//		on the ColorPicker's own button.
			//
			if modelData.itsFacePaintings[faceIndex.rawValue].style == .solidColor {

				ColorPicker(
					faceIndex.name,
					selection: $colorPickerColorAsSwiftUIColor,
					supportsOpacity: true)
				.labelsHidden()
				.frame(
					width: buttonImageFrameWidth,
					height: buttonImageFrameHeight,
					alignment: .center)
				.onAppear() {
					colorPickerColorAsSwiftUIColor = makeSwiftUIColor(
						from: unPremultiplyAlpha(
							modelData.itsFacePaintings[faceIndex.rawValue].color))
				}
				.onChange(of: colorPickerColorAsSwiftUIColor) {
					modelData.itsFacePaintings[faceIndex.rawValue].color
						= premultiplyAlpha(
							makeLinearXRsRGBColor(from: colorPickerColorAsSwiftUIColor)
										?? SIMD4<Float16>(1.0, 0.0, 1.0, 1.0)
						)
					modelData.changeCount += 1
				}
			}
		}
		.modifier(SelectionMarker(
			modelData.itsFacePaintings[faceIndex.rawValue].style == .solidColor))
		.frame(width: gridCellWidth, height: gridCellHeight, alignment: .top)
	}
}

#if os(iOS)
struct FaceCameraButton: View {

	var modelData: KaleidoTileModel
	let faceIndex: FaceIndex
	let optionalRenderer: KaleidoTileRenderer?
	let gridCellWidth: Double
	let gridCellHeight: Double

	@State private var showCamera = false
	@State private var photoFromCamera: KTImage? = nil

	var body: some View {
	
		Button(
			action: {
				showCamera = true
			},
			label: {
				VStack(spacing: 4.0) {
				
					Image("Table Images/Face Decoration/Camera")
					.frame(
						width: buttonImageFrameWidth,
						height: buttonImageFrameHeight)
							
					Text("Image from Camera")
					.font(.caption)
					.multilineTextAlignment(.center)
					.fixedSize()	//	prevents text truncation
				}
				.modifier(SelectionMarker(
					   modelData.itsFacePaintings[faceIndex.rawValue].style == .texture
					&& modelData.itsFacePaintings[faceIndex.rawValue].textureSource == .fromCamera))
			}
		)
		.frame(width: gridCellWidth, height: gridCellHeight, alignment: .top)
		.sheet(
			isPresented: $showCamera,
			onDismiss: {
			
				if let thePhoto = photoFromCamera,
				   let theRenderer = optionalRenderer {
					
					let i = faceIndex.rawValue
					modelData.itsFacePaintings[i].style = .texture
					modelData.itsFacePaintings[i].textureSource = .fromCamera

					theRenderer.setTexture(
									fromImage: thePhoto,
									onFace: faceIndex)
					
					modelData.changeCount += 1
				}
				
				photoFromCamera = nil
			},
			content: {
				CameraViewControllerRep(photoFromCamera: $photoFromCamera)
			}
		)
	}
}
#endif

struct FacePhotoPickerButton: View {

	var modelData: KaleidoTileModel
	let faceIndex: FaceIndex
	let optionalRenderer: KaleidoTileRenderer?
	let gridCellWidth: Double
	let gridCellHeight: Double

	@State private var photosPickerItem: PhotosPickerItem?

	var body: some View {
	
		let theSelectionMarker = SelectionMarker(
				   modelData.itsFacePaintings[faceIndex.rawValue].style == .texture
				&& modelData.itsFacePaintings[faceIndex.rawValue].textureSource == .fromPhotoLibrary)
		
		//	PhotosPicker's init() is '@preconcurrency nonisolated',
		//	so let's prefetch whatever information we need.
		let theButtonImageFrameWidth  = buttonImageFrameWidth
		let theButtonImageFrameHeight = buttonImageFrameHeight
	
		PhotosPicker(
			selection: $photosPickerItem,
			matching: .images
		) {
			VStack(spacing: 4.0) {
			
				Image("Table Images/Face Decoration/Photo Library")
				.frame(
					width: theButtonImageFrameWidth,
					height: theButtonImageFrameHeight)
						
				Text("Image from Photo Library")
				.font(.caption)
				.multilineTextAlignment(.center)
				.fixedSize()	//	prevents text truncation
			}
			.modifier(theSelectionMarker)
		}
		.frame(width: gridCellWidth, height: gridCellHeight, alignment: .top)
		.onChange(of: photosPickerItem) {
		
			guard let theItem = photosPickerItem else {
				return
			}
			
			//	loadTransferable() returns immediately on the main thread,
			//	then does it's real work on a background thread.
			//	The completion handler gets called on the background thread.
			//
			theItem.loadTransferable(type: Data.self) { result in
			
				switch result {
				
				case .success(let theData?):

					Task { @MainActor in
						if let theKTImage = KTImage(data: theData),
						   let theRenderer = optionalRenderer {
						
								let i = faceIndex.rawValue
								modelData.itsFacePaintings[i].style = .texture
								modelData.itsFacePaintings[i].textureSource = .fromPhotoLibrary

								theRenderer.setTexture(
												fromImage: theKTImage,
												onFace: faceIndex)
								
								modelData.changeCount += 1
						}
					}

				case .success(nil):	//	success with no Image (WTF???)
					break

				case .failure(_):
					break
				}
			}
		}
	}
}

struct FaceFilesButton: View {

	var modelData: KaleidoTileModel
	let faceIndex: FaceIndex
	let optionalRenderer: KaleidoTileRenderer?
	let gridCellWidth: Double
	let gridCellHeight: Double

	@State private var showFileImporter = false

	var body: some View {
	
		Button(
			action: {
				showFileImporter = true
			},
			label: {
				VStack(spacing: 4.0) {
				
					Image("Table Images/Face Decoration/Files")
					.frame(
						width: buttonImageFrameWidth,
						height: buttonImageFrameHeight)
							
					Text("Image from Files")
					.font(.caption)
					.multilineTextAlignment(.center)
					.fixedSize()	//	prevents text truncation
				}
				.modifier(SelectionMarker(
					   modelData.itsFacePaintings[faceIndex.rawValue].style == .texture
					&& modelData.itsFacePaintings[faceIndex.rawValue].textureSource == .fromFiles))
			}
		)
		.frame(width: gridCellWidth, height: gridCellHeight, alignment: .top)
		.fileImporter(
			isPresented: $showFileImporter,
			allowedContentTypes: [UTType.png, UTType.jpeg],
			allowsMultipleSelection: false
		) { result in
			
			do {
			
				guard let theFile = try result.get().first else {
					return
				}
				guard theFile.startAccessingSecurityScopedResource() else {
					return
				}
				defer { theFile.stopAccessingSecurityScopedResource() }

				let theData = try Data(contentsOf: theFile)
#if os(iOS)
				guard let theUIImage = UIImage(data: theData),
					  let theImage = KTImage(uiImage: theUIImage) else {
					return
				}
#endif
#if os(macOS)
				guard let theNSImage = NSImage(data: theData),
					  let theImage = KTImage(nsImage: theNSImage) else {
					return
				}
#endif

				guard let theRenderer = optionalRenderer else {
					return
				}
					
				let i = faceIndex.rawValue
				modelData.itsFacePaintings[i].style = .texture
				modelData.itsFacePaintings[i].textureSource = .fromFiles

				theRenderer.setTexture(
								fromImage: theImage,
								onFace: faceIndex)
				
				modelData.changeCount += 1

			} catch {
				assertionFailure("Couldn't import image file.  Error = \(error)")
			}
		}
	}
}

struct FacePasteButton: View {

	var modelData: KaleidoTileModel
	let faceIndex: FaceIndex
	let optionalRenderer: KaleidoTileRenderer?
	let gridCellWidth: Double
	let gridCellHeight: Double

#if os(iOS)
	@State private var pasteboardHasImage = UIPasteboard.general.hasImages
#endif

	var body: some View {
	
		let pasteImage: (KTImage) -> Void = { ktImage in
		
			if let theRenderer = optionalRenderer {

				let i = faceIndex.rawValue
				modelData.itsFacePaintings[i].style = .texture
				modelData.itsFacePaintings[i].textureSource = .fromPasteboard

				theRenderer.setTexture(
								fromImage: ktImage,
								onFace: faceIndex)
				
				modelData.changeCount += 1
			}
		}
		
		let theLabel
			= VStack(spacing: 4.0) {
			
				Image("Table Images/Face Decoration/Paste")
				.frame(
					width: buttonImageFrameWidth,
					height: buttonImageFrameHeight)
						
				Text("Paste Image")
				.font(.caption)
				.multilineTextAlignment(.center)
				.fixedSize()	//	prevents text truncation
			}
			.modifier(SelectionMarker(
				   modelData.itsFacePaintings[faceIndex.rawValue].style == .texture
				&& modelData.itsFacePaintings[faceIndex.rawValue].textureSource == .fromPasteboard))
	
#if os(iOS)

		//	On the one hand, using UIPasteboard directly forces the user
		//	to explicitly approve every paste operation.  Ugh.
		//
		//	On the other hand, UIPasteboard gives us a UIImage,
		//	which we can pass directly to the renderer,
		//	unlike the SwiftUI PasteButton which is willing
		//	to give us a SwiftUI Image (which is really a View
		//	and not an image per se) but apparently unwilling
		//	to give us a UIImage because a UIImage doesn't
		//	conform to the Transferrable protocol.
		//
		//	An additional problem with the SwiftUI PasteButton
		//	is that it forces us to use the Button that it provides,
		//	with only very limited stylistic options, so there'd
		//	be no way to integrate it into the design of the current
		//	FaceDecorationView.
		//
		//	So let's go ahead and use UIPasteboard directly,
		//	in spite of it forcing the user to approve each
		//	and every paste operation.
		
		Button(
			action: {
				if let theUIImage = UIPasteboard.general.image,
				   let theKTImage = KTImage(uiImage: theUIImage) {

					pasteImage(theKTImage)
				}
			},
			label: {
				theLabel
			}
		)
		.disabled( !(pasteboardHasImage || gMakeScreenshots) )
		.frame(width: gridCellWidth, height: gridCellHeight, alignment: .top)
		.onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
			//	This catches changes to the UIPasteboard made within KaleidoTile,
			//	but doesn't catch changes to the UIPasteboard made within other apps
			//	while KaleidoTile is in the background.
			pasteboardHasImage = UIPasteboard.general.hasImages
		}
		.onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
			//	This catches changes to the UIPasteboard made within other apps
			//	while KaleidoTile is in the background.
			pasteboardHasImage = UIPasteboard.general.hasImages
		}

#endif // os(iOS)
#if os(macOS)

		//	The page
		//
		// 		https://levelup.gitconnected.com/swiftui-macos-working-with-nspasteboard-b5811f98d5d1
		//
		//	says
		//
		//		Super unfortunately, the NSPasteboard version of
		//		UIPasteboard.changedNotification does NOT exist!
		//		Which means we have to poll! Using a Timer!
		//
		//	The page
		//
		//		https://stackoverflow.com/questions/5033266/can-i-receive-a-callback-whenever-an-nspasteboard-is-written-to
		//
		//	includes some discussion of why Apple chose not to provide
		//	a changedNotification, and whether it's a good idea to keep
		//	polling or not.
		//
		//	One further thought (of my own): maybe NSPasteboard's conventions
		//	were decided back in an era when the only way to see whether
		//	the Copy and Paste commands were enabled was to pull down
		//	the Edit menu from the Mac's menu bar. At the moment the user
		//	pulls down the menu bar, the app could check whether the NSPasteboard
		//	contains any pastable content. At all other times, the app
		//	really doesn't need to know.
		//
		//	This is consistent with the fact Apple's documentation at
		//
		//		https://developer.apple.com/documentation/swiftui/pastebutton
		//
		//	warns that even SwiftUI's own built-in PasteButton
		//	(which KaleidoTile doesn't use for the reasons explained above)
		//	makes no effort to work around that lack of a notification.
		//	Specifically, it says
		//
		//		A paste button automatically validates and invalidates
		//		based on changes to the pasteboard on iOS, but not on macOS.
		//
		//	So I'll go ahead and follow SwiftUI's lead and be lazy and
		//	leave the Paste button always enabled on macOS. It doesn't
		//	see to be worth the trouble of implementing a timer and
		//	worrying about invalidating it when the panel disappears.

		Button(
			action: {
				//	NSPasteboard seems to store all images in PNG format,
				//	no matter what format the source image was in.
				//	So we don't need
				//
				//		let theAvailableType
				//			= NSPasteboard.general.availableType(from: [.png, .tiff])
				//
				if let thePNGData = NSPasteboard.general.data(forType: .png),
				   let theNSImage = NSImage(data: thePNGData),
				   let theKTImage = KTImage(nsImage: theNSImage) {

					pasteImage(theKTImage)
				}
			},
			label: {
				theLabel
			}
		)
		.frame(width: gridCellWidth, height: gridCellHeight, alignment: .top)
		
#endif // os(macOS)
	}
}

struct FacePreviousButton: View {

	var modelData: KaleidoTileModel
	let faceIndex: FaceIndex
	let gridCellWidth: Double
	let gridCellHeight: Double

	var body: some View {
	
		Button(
			action: {
		
				modelData.itsFacePaintings[faceIndex.rawValue].style = .texture
				modelData.itsFacePaintings[faceIndex.rawValue].textureSource = .previous

				modelData.changeCount += 1
			},
			label: {
				VStack(spacing: 4.0) {
				
					Image("Table Images/Face Decoration/Previous Image")
					.frame(
						width: buttonImageFrameWidth,
						height: buttonImageFrameHeight)
							
					Text("Previous Image")
					.font(.caption)
					.multilineTextAlignment(.center)
					.fixedSize()	//	prevents text truncation
				}
				.modifier(SelectionMarker(
					   modelData.itsFacePaintings[faceIndex.rawValue].style == .texture
					&& modelData.itsFacePaintings[faceIndex.rawValue].textureSource == .previous))
			}
		)
		.frame(width: gridCellWidth, height: gridCellHeight, alignment: .top)
		.disabled(modelData.itsFacePaintings[faceIndex.rawValue].style == .texture)
	}
}

struct FaceInvisibleButton: View {

	var modelData: KaleidoTileModel
	let faceIndex: FaceIndex
	let gridCellWidth: Double
	let gridCellHeight: Double

	var body: some View {
	
		Button(
			action: {

				modelData.itsFacePaintings[faceIndex.rawValue].style = .invisible

				modelData.changeCount += 1
			},
			label: {
				VStack(spacing: 4.0) {
				
					Image("Table Images/Face Decoration/None")
					.frame(
						width: buttonImageFrameWidth,
						height: buttonImageFrameHeight)
							
					Text("Invisible")
					.font(.caption)
					.multilineTextAlignment(.center) // moot for 1-word title
					.fixedSize()	//	prevents text truncation
				}
				.modifier(SelectionMarker(
					modelData.itsFacePaintings[faceIndex.rawValue].style == .invisible))
			}
		)
		.frame(width: gridCellWidth, height: gridCellHeight, alignment: .top)
	}
}


struct BackgroundTextureButton: View {

	var modelData: KaleidoTileModel
	let backgroundTextureIndex: BackgroundTextureIndex
	let optionalRenderer: KaleidoTileRenderer?

	var body: some View {
	
		Button(
			action: {
			
				let bg = FaceIndex.background.rawValue
				modelData.itsFacePaintings[bg].style = .texture
				modelData.itsFacePaintings[bg].textureSource = .builtInBackground(backgroundTextureIndex)

				if let theRenderer = optionalRenderer {
					theRenderer.setBackgroundTexture(backgroundTextureIndex: backgroundTextureIndex)
				}
				
				modelData.changeCount += 1
			},
			label: {

				VStack(spacing: 4.0) {
				
					Image("Table Images/Background/" + backgroundTextureIndex.name)
					.cornerRadius(4.0)
					
					Text(LocalizedStringKey(backgroundTextureIndex.name))
					.font(.caption)
				}
				.modifier(SelectionMarker(
					modelData.itsFacePaintings[FaceIndex.background.rawValue].style == .texture
				 && modelData.itsFacePaintings[FaceIndex.background.rawValue].textureSource
												== .builtInBackground(backgroundTextureIndex)))
			}
		)
	}
}

#if os(iOS)
struct CameraViewControllerRep: UIViewControllerRepresentable {

	@Environment(\.presentationMode) var presentationMode
	@Binding var photoFromCamera: KTImage?
	
	func makeUIViewController(
		context: UIViewControllerRepresentableContext<CameraViewControllerRep>
	) -> UIImagePickerController {

		let theImagePicker = UIImagePickerController()
		theImagePicker.allowsEditing = true
		theImagePicker.sourceType = .camera
		theImagePicker.delegate = context.coordinator
		
		return theImagePicker
	}
	
	func updateUIViewController(
		_ uiViewController: UIImagePickerController,
		context: UIViewControllerRepresentableContext<CameraViewControllerRep>
	) {
		
	}
	
	func makeCoordinator(
	) -> CameraViewCoordinator {
	
		return CameraViewControllerRep.CameraViewCoordinator(self)
	}
	
	final class CameraViewCoordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {

		var parent: CameraViewControllerRep
		
		init(_ parent: CameraViewControllerRep) {
			self.parent = parent
		}
		
		func imagePickerController(
			_ picker: UIImagePickerController,
			didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]
		) {
			
			if let theUIImage = info[UIImagePickerController.InfoKey.editedImage] as? UIImage {

				//	The editedImage will have the same resolution
				//	as the image displayed in the UIImagePicker's
				//	on-screen cropping interface, which is typically
				//	a lot less than the resolution of the originalImage.
				//	For a camera app this would be a very bad thing,
				//	but for KaleidoTile that's OK.
				//
				//	UIImagePicker seems locked to a square crop rectangle.
				//	Again, a problem for a general camera app but fine
				//	for KaleidoTile.
				
				let theKTImage = KTImage(uiImage: theUIImage)
				parent.photoFromCamera = theKTImage
			}
			
			parent.presentationMode.wrappedValue.dismiss()
		}
	}
}
#endif // os(iOS)

struct SelectionMarker: ViewModifier {

	var isSelected: Bool

	init(
		_ isSelected: Bool
	) {
		self.isSelected = isSelected
	}

	func body(content: Content) -> some View {

		if isSelected {
		
			content
			.padding(8.0)
			.overlay(
				RoundedRectangle(cornerRadius: 8.0)
				.stroke(
					Color(.displayP3, red: 0.0, green: 1.0, blue: 0.5, opacity: 1.0),
					lineWidth: 3.0)
			)
			
		} else {
		
			content
			.padding(8.0)	//	add padding to keep content's position consistent
		}
	}
}


// MARK: -
// MARK: Options

struct OptionsView: View {

	@Bindable var modelData: KaleidoTileModel
	
	@Binding var inertia: Bool
	
	private var playSounds: Binding<Bool> { Binding(
		get: { gPlaySounds },
		set: { newValue in gPlaySounds = newValue }
	)}

	var body: some View {

		VStack(alignment: .leading, spacing: 8.0) {
			// Toggles will align on both sides on iOS
		
			Toggle("Show Plain Images", isOn: $modelData.itsShowPlainImages)
			Toggle("Show Reflected Images", isOn: $modelData.itsShowReflectedImages)
			Toggle("Cut Along Mirror Lines", isOn: $modelData.itsCutAlongMirrorLines)
			Divider()
			Toggle("Snap to Archimedean Solids", isOn: $modelData.itsSnapToArchimedeanSolids)
			Divider()
			Toggle("Sound Effects", isOn: playSounds)
			Toggle("Inertia", isOn: $inertia)
		}
		.fixedSize()
		.padding(geometryGamesPanelPadding)
		.background(gSystemBackgroundColor)
		.cornerRadius(geometryGamesCornerRadius)
	}
}
