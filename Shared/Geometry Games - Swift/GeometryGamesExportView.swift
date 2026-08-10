//	GeometryGamesExportView.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import SwiftUI
import UniformTypeIdentifiers


struct GeometryGamesExportView<ModelDataType>: View {

	enum ExportedImageSize: Int, CaseIterable, Identifiable, Codable {

//#warning("Comment out these cases")
		//	The 64, 128 and 192 px image sizes are useful
		//	for creating KaleidoPaint's symmetry group button images,
		//	but aren't part of the publicly released KaleidoPaint.
		//case size64   =  64
		//case size128  =  128
		//case size192  =  192

//#warning("Comment out these cases")
		//	The 16 and 128 px image sizes are needed only
		//	for making app icons for the Geometry Games web site.
		//case size16 = 16
		//case size128 = 128

		case size256  =  256
		case size512  =  512
		case size1024 = 1024
		case size2048 = 2048
		case size4096 = 4096
		
		var id: Int { self.rawValue }

		var asString: String {
			return "\(self.rawValue) × \(self.rawValue)"
		}
	}

	let itsModelData: ModelDataType
	
	//	itsExportRenderer should be the same renderer that
	//	the main view uses. So it should be completely set up
	//	and ready to render the image. For example, in KaleidoPaint
	//	the renderer should already have its composed unit-cell
	//	texture prepared (the slow part), and be ready to render
	//	an image at our desired dimensions (the fast part).
	let itsExportRenderer: GeometryGamesRenderer<ModelDataType>

	//	ShareLink() uses itsCaption as the subject line of an e-mail,
	//	the caption of an iMessage, etc.  However, when the user
	//	chooses Save to Files (which is offered only on iOS,
	//	for reasons I don't understand), ShareLink() proposes
	//	the default filename "PNG Image", ignoring itsCaption
	//	(which is fair enough, given that itsCaption could be
	//	a whole sentence).
	let itsCaption: String

	let itsBackgroundColor: Color

	//	Only KaleidoPaint uses the following, for (Tileable) Rectangle.
	//	Most symmetry patterns support Tileable Rectangle, but
	//	a few support only a Rectangle that must get glued with a shear.
	let itsExportTileableRectangleTitle: LocalizedStringKey?
	let itsPrepareModelToRenderTileableRectangle: (Int, Int) -> (Int, Int)
	let itsRestoreModelAfterRenderingTileableRectangle: () -> Void

	@AppStorage("exported image size") var imageSizeInPixels: ExportedImageSize = .size1024
	@AppStorage("export with transparent background") var exportWithTransparentBackground: Bool = false
	@AppStorage("export tileable rectangle") var exportTileableRectangle: Bool = false
													//	used only in KaleidoPaint
	@State var renderedImage: Image? = nil
	@State var renderedWidthPx: Int = 0
	@State var renderedHeightPx: Int = 0
#if os(macOS)
	//	If the macOS ShareLink ever supports Copy and Save to Files,
	//	then we can eliminate pngImage, isShowingFileExporter,
	//	and all the code that use them.
	@State var pngImage: Data? = nil
	@State var isShowingFileExporter: Bool = false
#endif

	init(
	
		modelData: ModelDataType,
		exportRenderer: GeometryGamesRenderer<ModelDataType>,
		caption: String,
		
		//	Used only in 4D Maze and 4D Draw to provide
		//	a dark background color that's not pure black.
		modifiedBackgroundColor: Color? = nil,
		
		//	Used only in KaleidoPaint
		exportTileableRectangleTitle: LocalizedStringKey? = nil,
		prepareModelToRenderTileableRectangle: @escaping
			(Int, Int) -> (Int, Int) = { w,h in return(w,h) },
		restoreModelAfterRenderingTileableRectangle: @escaping
			() -> Void = {}
	) {
		self.itsModelData = modelData
		self.itsExportRenderer = exportRenderer
		self.itsCaption = caption

		if let theModifiedBackgroundColor = modifiedBackgroundColor {
			//	In 4D Maze and 4D Draw
			self.itsBackgroundColor = theModifiedBackgroundColor
		} else {
			//	In all other Geometry Games apps
#if os(iOS)
			self.itsBackgroundColor = Color(UIColor.systemBackground)
#endif
#if os(macOS)
			self.itsBackgroundColor = Color(NSColor.textBackgroundColor)
#endif
		}

		self.itsExportTileableRectangleTitle = exportTileableRectangleTitle
		self.itsPrepareModelToRenderTileableRectangle = prepareModelToRenderTileableRectangle
		self.itsRestoreModelAfterRenderingTileableRectangle = restoreModelAfterRenderingTileableRectangle
	}
	
	var body: some View {
			
		let theImageSizeString = Bundle.main.localizedString(
			forKey: "Image size",
			value: nil,
			table: "GeometryGamesLocalizable")
		
		let theTransparentBackgroundString = Bundle.main.localizedString(
			forKey: "Transparent background",
			value: nil,
			table: "GeometryGamesLocalizable")

#if os(macOS)
		let theCopyString = Bundle.main.localizedString(
			forKey: "Copy",
			value: nil,
			table: "GeometryGamesLocalizable")

		let theSaveString = Bundle.main.localizedString(
			forKey: "Save",
			value: nil,
			table: "GeometryGamesLocalizable")
#endif

		return VStack(alignment: .center) {
			
			if let theRenderedImage = renderedImage {

				VStack(alignment: .center) {
#if os(macOS)
					//	The ShareLink panel's options on iOS include Copy
					//	and Save to Files. But on macOS, for reasons I don't
					//	understand at all, it includes neither of those.
					//	So let's provide our own versions on macOS.
					
					Button() {
						copyToClipboard()
					} label: {
						Label(theCopyString, systemImage: "doc.on.doc")
						.font(.title3)
						.modifier(applyForegroundAccentColorOnMacOS())
						.frame(maxWidth: .infinity, alignment: .leading) // to support equal-width buttons
					}
					
					Button() {
						isShowingFileExporter = true
					} label: {
						Label(theSaveString, systemImage: "folder")
						.font(.title3)
						.modifier(applyForegroundAccentColorOnMacOS())
						.frame(maxWidth: .infinity, alignment: .leading) // to support equal-width buttons
					}
					.fileExporter(
						isPresented: $isShowingFileExporter,
						document: PNGDocument(pngImage),
						contentType: .png
					//	, defaultFilename: "???"
					) { result in
//						switch result {
//						case .success(let url):   break
//						case .failure(let error): break
//						}
					}
#endif

					ShareLink(
						item: theRenderedImage,
						preview: SharePreview(itsCaption, image: theRenderedImage))
					.font(.title3)
					.modifier(applyForegroundAccentColorOnMacOS())
					.frame(maxWidth: .infinity, alignment: .leading) // to support equal-width buttons but...
												//   the ShareLink button stays a fixed size

#if os(macOS)
					Spacer()
					.frame(height: 24.0)
#endif
				}
				.fixedSize(horizontal: true, vertical: false) // to support equal-width buttons
			}
			
			HStack() {

#if os(iOS)
				//	By default, the Picker() itself shows
				//	theImageSizeString on macOS but not on iOS.
				//	So on iOS we must include it separately.
				Text(theImageSizeString)
				Spacer()
#endif
				Picker(
					theImageSizeString,
					selection: $imageSizeInPixels
				) {
					ForEach(ExportedImageSize.allCases, id: \.id) { theImageSize in
						Text(verbatim: theImageSize.asString)
					//	.modifier(applyForegroundAccentColorOnMacOS())	//	has no effect (?!)
						.foregroundStyle(Color.accentColor)				//	works fine
						.tag(theImageSize)	//	.tag must come after .foregroundStyle
					}
				}
				.pickerStyle(MenuPickerStyle())
				.fixedSize()
			}
			
			Toggle(
				theTransparentBackgroundString,
				isOn: $exportWithTransparentBackground
			)
			
			if let theExportTileableRectangleTitle = itsExportTileableRectangleTitle {
				Toggle(
					theExportTileableRectangleTitle,
					isOn: $exportTileableRectangle
				)
			}
						
			if let theRenderedImage = renderedImage {
			
				VStack(spacing: 4.0) {
				
					ZStack() {
					
						Rectangle()
						.foregroundStyle(Color(.displayP3, white: 0.9375))
			
						theRenderedImage
						.resizable()
					}
					.scaledToFit()
					.frame(width: 256.0, height: 256.0)

					Text("\(renderedWidthPx, format: .number.grouping(.never)) × \(renderedHeightPx, format: .number.grouping(.never))")
					.font(.footnote)
					.foregroundStyle(.gray)
				}
			}
		}
		.modifier(buttonStyleOnMacOS())
		.fixedSize()
		.onAppear() {
			makeImage()
		}
		.onChange(of: imageSizeInPixels) {
			makeImage()
		}
		.onChange(of: exportWithTransparentBackground) {
			makeImage()
		}
		.onChange(of: exportTileableRectangle) {
			makeImage()
		}
		.padding(geometryGamesPanelPadding)
		.background(itsBackgroundColor)
		.cornerRadius(geometryGamesCornerRadius)
	}
	
	func makeImage() {

		let theAvailableImageSizePx = itsExportRenderer.clampImageSize(
										requestedSizePx: imageSizeInPixels.rawValue)
		
		let theWidthPx: Int
		let theHeightPx: Int
		if exportTileableRectangle {

			//	Only KaleidoPaint provides a non-trivial closure
			//	for prepareModelToRenderTileableRectangle().
			(theWidthPx, theHeightPx) = itsPrepareModelToRenderTileableRectangle(
								theAvailableImageSizePx, theAvailableImageSizePx)
					
		} else {
			(theWidthPx, theHeightPx) = (theAvailableImageSizePx, theAvailableImageSizePx)
		}

		let theOptionalCGImage = itsExportRenderer.createOffscreenImage(
			modelData: itsModelData,
			widthPx: theWidthPx,
			heightPx: theHeightPx,
			transparentBackground: exportWithTransparentBackground,
			extraRenderFlag: nil	//	could provide subclass-specific value if desired
		)
		
		if exportTileableRectangle {

			//	Only KaleidoPaint provides a non-empty closure
			//	for restoreModelAfterRenderingTileableRectangle.
			itsRestoreModelAfterRenderingTileableRectangle()
		}

		if let theCGImage = theOptionalCGImage {
			renderedImage = Image(decorative: theCGImage, scale: 1.0)
			renderedWidthPx = theCGImage.width
			renderedHeightPx = theCGImage.height
		} else {
			renderedImage = nil
			renderedWidthPx = 0
			renderedHeightPx = 0
		}

#if os(macOS)
		if let theCGImage = theOptionalCGImage,
		   let theColorSpace = CGColorSpace(name: CGColorSpace.displayP3) {
		   
			let theCIContext = CIContext()
			let theCIImage = CIImage(cgImage: theCGImage)
			pngImage = theCIContext.pngRepresentation(
										of: theCIImage,
										format: .RGBA8,
										colorSpace: theColorSpace)
		} else {
			pngImage = nil
		}
#endif
	}
	
#if os(macOS)

	func copyToClipboard() {
	
		if let thePngImage = pngImage {
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setData(thePngImage, forType: .png)
		}
	}

	struct PNGDocument: FileDocument {

		static var readableContentTypes: [UTType] { [.png] }
		
		var pngImage: Data

		init?(
			_ pngImage: Data?
		) {
			guard let thePngImage = pngImage
			else { return nil }
			
			self.pngImage = thePngImage
		}

		init(configuration: ReadConfiguration) throws {

			assertionFailure("The FileDocument protocol requires this init(), but we never use it.")
			pngImage = Data(capacity: 1)
		}

		func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {

			return FileWrapper(regularFileWithContents: pngImage )
		}
	}

#endif // os(macOS)
}
