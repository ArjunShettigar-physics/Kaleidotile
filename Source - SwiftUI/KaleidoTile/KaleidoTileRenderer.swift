//	KaleidoTileRenderer.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import MetalKit	//	or just plain Metal if not using MTKTextureLoader
import MetalPerformanceShaders	//	for MPSImageConversion
import SwiftUI


class KaleidoTileRenderer: GeometryGamesRenderer<KaleidoTileModel> {

	//	Before calling the superclass's (GeometryGamesRenderer's) init()
	//	to set up itsDevice, itsColorPixelFormat, itsCommandQueue, etc.,
	//	and indeed even before calling any of our own methods to set up
	//	the pipeline state, texture, etc., we must ensure that
	//	all our instances variables have values.  For that reason,
	//	we declare them to be optionals, which are automatically initialized
	//	to nil.  On the other hand constantly unwrapping such optionals
	//	would quickly become tedious, and make the code harder to read.
	//	So let's define them as implicitly unwrapped optionals.
	//	I'm slightly uncomfortable using implicitly unwrapped optionals
	//	-- I hadn't intended to use them at all, for run-time safety --
	//	but in this case all we need to do to avoid problems is make sure
	//	that our own init() function provides non-nil values for these
	//	instances variables before returning.
	//
	var itsSolidColorUnlitPipelineState: MTLRenderPipelineState!
	var itsSolidColorLitPipelineState: MTLRenderPipelineState!
	var itsSolidColorDimmedPipelineState: MTLRenderPipelineState!
	var itsTextureUnlitPipelineState: MTLRenderPipelineState!
	var itsTextureLitPipelineState: MTLRenderPipelineState!
	var itsTextureDimmedPipelineState: MTLRenderPipelineState!
	var itsSolidColorBackgroundPipelineState: MTLRenderPipelineState!
	var itsTextureBackgroundPipelineState: MTLRenderPipelineState!
	var itsTriplePointPipelineState: MTLRenderPipelineState!
	var itsTiling: KaleidoTileTiling!
	var itsMeshMaker: KaleidoTileMeshMaker!
	var itsFaceTextures: [MTLTexture] = []	//	textures 0, 1 and 2 are for the faces
											//	texture 3 is for the background
	var itsFaceThumbnails: [KTImage] = []	//	thumbnails for itsFaceTextures
	var itsIsotropicSamplerState: MTLSamplerState!
	var itsAnisotropicSamplerState: MTLSamplerState!
	var itsBackgroundSamplerState: MTLSamplerState!
	
	let thumbnailSizePt: Double = 40.0	//	thumbnail size in points


	init?() {

		//	Specify clear-color values in linear extended-range sRGB.

#if os(iOS)
		//	Use a transparent clearColor, so the triple-point View
		//	sits correctly over the View that contains it.
		let theClearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
#endif
#if os(macOS)
		//	The comment accompanying GeometryGamesView's isOpaque
		//	explains why we don't use a transparent clear color on macOS.
		let theClearColor = MTLClearColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
#endif

		super.init(
			wantsMultisampling: true,
			wantsDepthBuffer: false,	//	KaleidoTile needs no depth buffer
			clearColor: theClearColor)

		if !(
			setUpPipelineStates()
		 && setUpTiling()
		 && setUpMeshMaker()
		 && setUpTextures()
		 && setUpSamplerStates()
		) {
			assertionFailure("Unable to set up Metal resources")
			return nil
		}
	}
	
	func setUpPipelineStates() -> Bool {

		guard let theGPUFunctionLibrary = itsDevice.makeDefaultLibrary() else {
			assertionFailure("Failed to create default GPU function library")
			return false
		}
		
		enum LightingType {
			case unlit
			case lit
			case dimmed
		}
		
		itsSolidColorUnlitPipelineState		= makePipelineState(texture: false, lighting: .unlit)
		if itsSolidColorUnlitPipelineState == nil {
			return false
		}
		
		itsSolidColorLitPipelineState		= makePipelineState(texture: false, lighting: .lit)
		if itsSolidColorLitPipelineState == nil {
			return false
		}
		
		itsSolidColorDimmedPipelineState	= makePipelineState(texture: false, lighting: .dimmed)
		if itsSolidColorDimmedPipelineState == nil {
			return false
		}
		
		itsTextureUnlitPipelineState		= makePipelineState(texture: true,  lighting: .unlit)
		if itsTextureUnlitPipelineState == nil {
			return false
		}
		
		itsTextureLitPipelineState			= makePipelineState(texture: true,  lighting: .lit)
		if itsTextureLitPipelineState == nil {
			return false
		}
		
		itsTextureDimmedPipelineState		= makePipelineState(texture: true,  lighting: .dimmed)
		if itsTextureDimmedPipelineState == nil {
			return false
		}
		
		itsSolidColorBackgroundPipelineState	= makeBackgroundPipelineState(texture: false)
		if itsSolidColorBackgroundPipelineState == nil {
			return false
		}
		
		itsTextureBackgroundPipelineState		= makeBackgroundPipelineState(texture: true)
		if itsTextureBackgroundPipelineState == nil {
			return false
		}
		
		itsTriplePointPipelineState = makeTriplePointPipelineState()
		if itsTriplePointPipelineState == nil {
			return false
		}
		
		func makePipelineState(
			texture: Bool,
			lighting: LightingType
		) -> MTLRenderPipelineState? {

			//	GPU functions

			var theTextureValue = texture
			var theDirectionalLightingValue = (lighting != .unlit)
				//	Suppress specular reflection in screenshot for icon.
				//	Otherwise specular reflection looks good on a rotating polyhedron.
			var theSpecularReflectionValue = !gMakeScreenshots
			var theDimmingValue = (lighting == .dimmed)

			let theCompileTimeConstants = MTLFunctionConstantValues()
			theCompileTimeConstants.setConstantValue(	&theTextureValue,
														type: .bool,
														withName: "gTexture")
			theCompileTimeConstants.setConstantValue(	&theDirectionalLightingValue,
														type: .bool,
														withName: "gDirectionalLighting")
			theCompileTimeConstants.setConstantValue(	&theSpecularReflectionValue,
														type: .bool,
														withName: "gSpecularReflection")
			theCompileTimeConstants.setConstantValue(	&theDimmingValue,
														type: .bool,
														withName: "gDimming")
		
			let theGPUVertexFunction: MTLFunction
			do {
				theGPUVertexFunction
					= try theGPUFunctionLibrary.makeFunction(	//	returns non-nil
						name: "KaleidoTileVertexFunction",
						constantValues: theCompileTimeConstants)
			} catch {
				assertionFailure(error.localizedDescription)
				return nil
			}
		
			let theGPUFragmentFunction: MTLFunction
			do {
				theGPUFragmentFunction
					= try theGPUFunctionLibrary.makeFunction(	//	returns non-nil
						name: "KaleidoTileFragmentFunction",
						constantValues: theCompileTimeConstants)
			} catch {
				assertionFailure(error.localizedDescription)
				return nil
			}

			//	pipeline state

			//	Create a MTLVertexDescriptor describing the vertex attributes
			//	that the GPU sends along to each vertex.  Each vertex attribute
			//	may be a 1-, 2-, 3- or 4-component vector.

			let theVertexDescriptor = MTLVertexDescriptor()
			
				//	Say where to find each attribute.
			
			guard let thePosOffset = MemoryLayout.offset(of: \KaleidoTileVertexData.pos) else {
				assertionFailure("Failed to find offset of KaleidoTileVertexData.pos")
				return nil
			}
			theVertexDescriptor.attributes[VertexAttributePosition].format = MTLVertexFormat.float3
			theVertexDescriptor.attributes[VertexAttributePosition].bufferIndex = BufferIndexVFVertexAttributes
			theVertexDescriptor.attributes[VertexAttributePosition].offset = thePosOffset

			if lighting != .unlit {
			
				guard let theNorOffset = MemoryLayout.offset(of: \KaleidoTileVertexData.nor) else {
					assertionFailure("Failed to find offset of KaleidoTileVertexData.nor")
					return nil
				}
				theVertexDescriptor.attributes[VertexAttributeNormal].format = MTLVertexFormat.half3
				theVertexDescriptor.attributes[VertexAttributeNormal].bufferIndex = BufferIndexVFVertexAttributes
				theVertexDescriptor.attributes[VertexAttributeNormal].offset = theNorOffset
			}
			
			if texture {
			
				guard let theTexOffset = MemoryLayout.offset(of: \KaleidoTileVertexData.tex) else {
					assertionFailure("Failed to find offset of KaleidoTileVertexData.tex")
					return nil
				}
				theVertexDescriptor.attributes[VertexAttributeTexCoords].format = MTLVertexFormat.float2
				theVertexDescriptor.attributes[VertexAttributeTexCoords].bufferIndex = BufferIndexVFVertexAttributes
				theVertexDescriptor.attributes[VertexAttributeTexCoords].offset = theTexOffset
			}

				//	Say how to step through each buffer.

			theVertexDescriptor.layouts[BufferIndexVFVertexAttributes].stepFunction
				= MTLVertexStepFunction.perVertex
			theVertexDescriptor.layouts[BufferIndexVFVertexAttributes].stride
				= MemoryLayout<KaleidoTileVertexData>.stride

			//	Create a MTLRenderPipelineDescriptor.
			
			let thePipelineDescriptor = MTLRenderPipelineDescriptor()
			thePipelineDescriptor.label = "KaleidoTile render pipeline"
			thePipelineDescriptor.rasterSampleCount = itsSampleCount
			thePipelineDescriptor.vertexFunction = theGPUVertexFunction
			thePipelineDescriptor.fragmentFunction = theGPUFragmentFunction
			thePipelineDescriptor.vertexDescriptor = theVertexDescriptor
			thePipelineDescriptor.colorAttachments[0].pixelFormat = itsColorPixelFormat
			//	To allow for partially transparent colors and textures
			//	we must enable blending.  The comment on "Premultiplied alpha"
			//	in GeometryGamesColor.swift explains the (1, 1 - α) blend factors.
			thePipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
			thePipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
			thePipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
			thePipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
			thePipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
			thePipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
			thePipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
			thePipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormat.invalid	//	the default
			thePipelineDescriptor.stencilAttachmentPixelFormat = MTLPixelFormat.invalid	//	the default

			do {
				let thePipelineState = try itsDevice.makeRenderPipelineState(descriptor: thePipelineDescriptor)	//	returns non-nil
				return thePipelineState
			} catch {
				assertionFailure("Couldn't create thePipelineState: \(error)")
				return nil
			}
		}
		
		func makeBackgroundPipelineState(
			texture: Bool
		) -> MTLRenderPipelineState? {

			//	GPU functions

			let theCompileTimeConstants = MTLFunctionConstantValues()
			var theTextureValue = texture
			theCompileTimeConstants.setConstantValue(	&theTextureValue,
														type: .bool,
														withName: "gTexture")

			let theGPUVertexFunction: MTLFunction
			do {
				theGPUVertexFunction
					= try theGPUFunctionLibrary.makeFunction(	//	returns non-nil
						name: "KaleidoTileBackgroundVertexFunction",
						constantValues: theCompileTimeConstants)
			} catch {
				assertionFailure(error.localizedDescription)
				return nil
			}
		
			let theGPUFragmentFunction: MTLFunction
			do {
				theGPUFragmentFunction
					= try theGPUFunctionLibrary.makeFunction(	//	returns non-nil
						name: "KaleidoTileBackgroundFragmentFunction",
						constantValues: theCompileTimeConstants)
			} catch {
				assertionFailure(error.localizedDescription)
				return nil
			}

			//	pipeline state

			//	Create a MTLVertexDescriptor describing the vertex attributes
			//	that the GPU sends along to each vertex.  Each vertex attribute
			//	may be a 1-, 2-, 3- or 4-component vector.

			let theVertexDescriptor = MTLVertexDescriptor()
			
				//	Say where to find each attribute.
			
			guard let thePosOffset = MemoryLayout.offset(of: \KaleidoTile2DVertexData.pos) else {
				assertionFailure("Failed to find offset of KaleidoTile2DVertexData.pos")
				return nil
			}
			theVertexDescriptor.attributes[VertexAttributePosition].format = MTLVertexFormat.float2
			theVertexDescriptor.attributes[VertexAttributePosition].bufferIndex = BufferIndexVFVertexAttributes
			theVertexDescriptor.attributes[VertexAttributePosition].offset = thePosOffset
			
			if texture {
			
				guard let theTexOffset = MemoryLayout.offset(of: \KaleidoTile2DVertexData.tex) else {
					assertionFailure("Failed to find offset of KaleidoTile2DVertexData.tex")
					return nil
				}
				theVertexDescriptor.attributes[VertexAttributeTexCoords].format = MTLVertexFormat.float2
				theVertexDescriptor.attributes[VertexAttributeTexCoords].bufferIndex = BufferIndexVFVertexAttributes
				theVertexDescriptor.attributes[VertexAttributeTexCoords].offset = theTexOffset
			}

				//	Say how to step through each buffer.

			theVertexDescriptor.layouts[BufferIndexVFVertexAttributes].stepFunction
				= MTLVertexStepFunction.perVertex
			theVertexDescriptor.layouts[BufferIndexVFVertexAttributes].stride
				= MemoryLayout<KaleidoTile2DVertexData>.stride

			//	Create a MTLRenderPipelineDescriptor.
			
			let thePipelineDescriptor = MTLRenderPipelineDescriptor()
			thePipelineDescriptor.label = "KaleidoTile background render pipeline"
			thePipelineDescriptor.rasterSampleCount = itsSampleCount
			thePipelineDescriptor.vertexFunction = theGPUVertexFunction
			thePipelineDescriptor.fragmentFunction = theGPUFragmentFunction
			thePipelineDescriptor.vertexDescriptor = theVertexDescriptor
			thePipelineDescriptor.colorAttachments[0].pixelFormat = itsColorPixelFormat
			thePipelineDescriptor.colorAttachments[0].isBlendingEnabled = false
			thePipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormat.invalid	//	the default
			thePipelineDescriptor.stencilAttachmentPixelFormat = MTLPixelFormat.invalid	//	the default

			do {
				let thePipelineState = try itsDevice.makeRenderPipelineState(descriptor: thePipelineDescriptor)	//	returns non-nil
				return thePipelineState
			} catch {
				assertionFailure("Couldn't create thePipelineState for background: \(error)")
				return nil
			}
		}
		
		func makeTriplePointPipelineState(
		) -> MTLRenderPipelineState? {
		
			//	GPU functions

			guard let theGPUVertexFunction
				= theGPUFunctionLibrary.makeFunction(name: "KaleidoTileTriplePointVertexFunction")
			else {
				assertionFailure("Failed to load KaleidoTileTriplePointVertexFunction")
				return nil
			}
			
			guard let theGPUFragmentFunction
				= theGPUFunctionLibrary.makeFunction(name: "KaleidoTileTriplePointFragmentFunction")
			else {
				assertionFailure("Failed to load KaleidoTileTriplePointFragmentFunction")
				return nil
			}

			//	pipeline state

			let theVertexDescriptor = MTLVertexDescriptor()

				//	Say where to find each attribute.
			
			guard let thePosOffset = MemoryLayout.offset(of: \KaleidoTile2DVertexData.pos) else {
				assertionFailure("Failed to find offset of KaleidoTile2DVertexData.pos")
				return nil
			}
			theVertexDescriptor.attributes[VertexAttributePosition].format = MTLVertexFormat.float2
			theVertexDescriptor.attributes[VertexAttributePosition].bufferIndex = BufferIndexVFVertexAttributes
			theVertexDescriptor.attributes[VertexAttributePosition].offset = thePosOffset
			
			guard let theTexOffset = MemoryLayout.offset(of: \KaleidoTile2DVertexData.tex) else {
				assertionFailure("Failed to find offset of KaleidoTile2DVertexData.tex")
				return nil
			}
			theVertexDescriptor.attributes[VertexAttributeTexCoords].format = MTLVertexFormat.float2
			theVertexDescriptor.attributes[VertexAttributeTexCoords].bufferIndex = BufferIndexVFVertexAttributes
			theVertexDescriptor.attributes[VertexAttributeTexCoords].offset = theTexOffset

				//	Say how to step through each buffer.

			theVertexDescriptor.layouts[BufferIndexVFVertexAttributes].stepFunction
				= MTLVertexStepFunction.perVertex
			theVertexDescriptor.layouts[BufferIndexVFVertexAttributes].stride
				= MemoryLayout<KaleidoTile2DVertexData>.stride

			//	Create a MTLRenderPipelineDescriptor.
			
			let thePipelineDescriptor = MTLRenderPipelineDescriptor()
			thePipelineDescriptor.label = "KaleidoTile triple-point render pipeline"
			thePipelineDescriptor.rasterSampleCount = itsSampleCount
			thePipelineDescriptor.vertexFunction = theGPUVertexFunction
			thePipelineDescriptor.fragmentFunction = theGPUFragmentFunction
			thePipelineDescriptor.vertexDescriptor = theVertexDescriptor
			thePipelineDescriptor.colorAttachments[0].pixelFormat = itsColorPixelFormat
			//	The comment on "Premultiplied alpha" in GeometryGamesColor.swift
			//	explains the (1, 1 - α) blend factors.
			thePipelineDescriptor.colorAttachments[0].isBlendingEnabled = true
			thePipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
			thePipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
			thePipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .one
			thePipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
			thePipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
			thePipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
			thePipelineDescriptor.depthAttachmentPixelFormat = MTLPixelFormat.invalid	//	the default
			thePipelineDescriptor.stencilAttachmentPixelFormat = MTLPixelFormat.invalid	//	the default

			do {
				let thePipelineState
					= try itsDevice.makeRenderPipelineState(descriptor: thePipelineDescriptor)	//	returns non-nil
				return thePipelineState
			} catch {
				assertionFailure("Couldn't create thePipelineState for the triple point: \(error)")
				return nil
			}
		}
		
		return true
	}
		
	func setUpTiling() -> Bool {

		//	Create an arbitrary KaleidoTileTiling as part of this
		//	KaleidoTileRenderer's init() sequence, so that
		//	itsTiling can be an implicitly unwrapped optional,
		//	which keeps subsequent code cleaner (compared to using
		//	a manually unwrapped optional).  At render time --
		//	when the ModelData will be available -- encodeCommands()
		//	will update this arbitrary tiling to match the desired
		//	reflectionGroup and tilingStyle.

		let theArbitraryReflectionGroup = ReflectionGroup(2, 3, 5)
		let theArbitraryBaseTriangle = BaseTriangle(reflectionGroup: theArbitraryReflectionGroup)
		
		itsTiling = KaleidoTileTiling(
						device: itsDevice,
						baseTriangle: theArbitraryBaseTriangle)

		return true
	}
	
	func setUpMeshMaker() -> Bool {

		itsMeshMaker = KaleidoTileMeshMaker(device: itsDevice)

		return true
	}
	
	func setUpTextures() -> Bool {
	
		let theTextureLoader = MTKTextureLoader(device: itsDevice)
		let theTextureLoaderOptions: [MTKTextureLoader.Option: Any] = [
			.textureUsage:		 NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
			.textureStorageMode: NSNumber(value: MTLStorageMode.`private`.rawValue)

			//	Note: MTKTextureLoader's newTexture() ignores the .origin option.
			//	Instead we can select the texture in our Asset Catalog in Xcode,
			//	show the Inspectors panel on the right, and set
			//
			//		Texture Set > Origin = Bottom Left or Top Left
			//
		]

		//	Wide-color PNG images are typically saved in the Display P3 color space,
		//	but all rendering on iOS takes place in Extended Range sRGB coordinates.
		//	To provide the necessary compatibility, whenever we add a P3 texture
		//	to an Asset Catalog Texture Set, Xcode automatically prepares
		//	an XR sRGB version, and then at run time the MTKTextureLoader's
		//	newTexture() method returns that XR sRGB version.
		//
		//	For this to work correctly, you should set the pixel format
		//	to bgr10_xr_srgb for opaque images, or rgba16Float for images
		//	with partial transparency.  Those pixel formats work well
		//	on both iOS and macOS ("Designed for iPad").
		//
		//		Note:  The Xcode Asset Catalog's Texture Set info panel
		//		doesn't immediately show the option to select a pixel format.
		//		You have to click on the image's thumbnail (which is
		//		typically labelled "universal" -- it's the only one)
		//		to get the pixel format picker for that image to appear.
		//		Otherwise you get the default astc_4x4_srgb format,
		//		with no support for wide color.
		//

		//	Users will typically select "Image from Camera" and/or "Image from Photo Library"
		//	to experiment with their own custom images.  But if we load some default images here,
		//	then the Previous Image command can be available at launch, to give users
		//	a super-quick way to put a texture onto a face, to see how KaleidoTile works.
		//	As an added bonus, this ensures that itsFaceTextures are never nil.

		let theDefaultTextureNames = [
			"default image A - dolphin",
			"default image B - Liguria",
			"default image C - dog",
			defaultBackground.textureName
		]

		do {
		
			itsFaceTextures = []	//	redundant but clear
			itsFaceThumbnails = []	//	redundant but clear
			
			for theTextureName in theDefaultTextureNames {
			
				try itsFaceTextures.append(
					theTextureLoader.newTexture(
						name: theTextureName,
						scaleFactor: 1.0,
						bundle: nil,
						options: theTextureLoaderOptions))
				
#if os(iOS)
				guard let theUIImage = UIImage(named: "Thumbnails/" + theTextureName) else {
					assertionFailure("Failed to load thumbnail in setUpTextures.")
					return false
				}
				guard let theThumbnail = KTImage(uiImage: theUIImage) else {
					assertionFailure("Failed to convert theUIImage to theThumbnail in setUpTextures.")
					return false
				}
#endif
#if os(macOS)
				guard let theNSImage = NSImage(named: "Thumbnails/" + theTextureName) else {
					assertionFailure("Failed to load thumbnail in setUpTextures.")
					return false
				}
				guard let theThumbnail = KTImage(nsImage: theNSImage) else {
					assertionFailure("Failed to convert theNSImage to theThumbnail in setUpTextures.")
					return false
				}
#endif

				itsFaceThumbnails.append(theThumbnail)
			}
			
		} catch {
			assertionFailure("Failed to load texture.  Error:  \(error)")
			return false
		}
		
		return true
	}
		
	func setUpSamplerStates() -> Bool {

		itsIsotropicSamplerState = makeSamplerState(mode: .clampToEdge, anisotropic: false)
		if itsIsotropicSamplerState == nil {
			assertionFailure("Couldn't create itsIsotropicSamplerState")
			return false
		}
		
		itsAnisotropicSamplerState = makeSamplerState(mode: .clampToEdge, anisotropic: true)
		if itsAnisotropicSamplerState == nil {
			assertionFailure("Couldn't create itsAnisotropicSamplerState")
			return false
		}
		
		itsBackgroundSamplerState = makeSamplerState(mode: .repeat, anisotropic: false)
		if itsBackgroundSamplerState == nil {
			assertionFailure("Couldn't create itsBackgroundSamplerState")
			return false
		}
		
		return true
	}


// MARK: -
// MARK: Rendering

	//	GeometryGamesRenderer (our superclass) provides the functions
	//
	//		render()
	//			for standard onscreen rendering
	//
	//		createOffscreenImage()
	//			for CopyImage and SaveImage
	//
	//	Those two functions handle the app-independent parts
	//	of rendering an image, but for the app-dependent parts
	//	they call encodeCommands(), which we override here
	//	to provide the app-specific content.

	override func encodeCommands(
		modelData: KaleidoTileModel,
		commandBuffer: MTLCommandBuffer,
		renderPassDescriptor: MTLRenderPassDescriptor,
		frameWidth: Int,
		frameHeight: Int,
		transparentBackground: Bool,
		extraRenderFlag: Bool?,
		quality: GeometryGamesImageQuality
	) {
	
		guard frameWidth > 0 && frameHeight > 0 else {
			assertionFailure("encodeCommands() received a frame of zero width or height")
			return
		}
		
		let baseTriangleOnly = extraRenderFlag ?? false

		itsTiling.preparedBaseTriangle = modelData.itsBaseTriangle

		var theUniformData = prepareUniformData(
				modelData: modelData,
				frameWidth: Double(frameWidth),
				frameHeight: Double(frameHeight),
				baseTriangleOnly: baseTriangleOnly)

		let (thePlainInstanceCount, thePlainInstances, theReflectedInstanceCount, theReflectedInstances)
			= baseTriangleOnly ?
				itsTiling.getIdentityInstance() :
				itsTiling.getTiling()

		//	No matter what TilingStyle the main view is using,
		//	the Triple Point view always using .curved,
		//	to maintain a constant "parameter space" for the triple point.
		//
		let theTilingStyle = baseTriangleOnly ? .curved : modelData.itsTilingStyle

		let (theVertexCount, theVertexBuffers, theFaceIndexCount, theFaceBuffer)
			= itsMeshMaker.makeMeshes(
				baseTriangle: modelData.itsBaseTriangle,
				tilingStyle: theTilingStyle,
				triplePoint: modelData.itsTriplePoint,
				cutAlongMirrorLines: modelData.itsCutAlongMirrorLines,
				forUseWith: commandBuffer)
		for i in 0...2 {
			precondition(
				theVertexBuffers[i].length >= theVertexCount * MemoryLayout<KaleidoTileVertexData>.stride,
				"Invalid vertex buffer length")
		}
		precondition(
			theFaceBuffer.length >= theFaceIndexCount * MemoryLayout<UInt16>.stride,
			"Invalid face buffer length")
		
		guard let theCommandEncoder = commandBuffer.makeRenderCommandEncoder(
						descriptor: renderPassDescriptor) else {
			assertionFailure("Couldn't create theCommandEncoder in encodeCommands()")
			return
		}
		theCommandEncoder.label = "KaleidoTile render encoder"


		//	Draw the background as a single rectangle
		//	with the appropriate color or texture.
		let bg = FaceIndex.background.rawValue
		if   modelData.itsFacePaintings[bg].style != .invisible
		  && !baseTriangleOnly
		  && !transparentBackground {
		
			theCommandEncoder.pushDebugGroup("Draw background")

			theCommandEncoder.setCullMode(.none)
			
			//	Use a do{} block to limit the scope of the UnsafeMutablePointer.
			do {
				let theBackgroundVertices = UnsafeMutablePointer<KaleidoTile2DVertexData>.allocate(capacity: 4)

				//	theTexReps is needed only when .style == .texture
				//	and .textureSource == .builtInBackground.
				//
				//		Please forgive Swift's bizarre if-case-let syntax.
				//
				let theTexReps: Double?
				if case .builtInBackground(let backgroundTextureIndex)
										= modelData.itsFacePaintings[bg].textureSource {
					theTexReps = backgroundTextureIndex.texReps
				} else {	//	.style == .solidColor, so texture coordinates get ignored
					theTexReps = nil
				}
					
				setBackgroundVertices(
					theBackgroundVertices,
					frameWidth: Double(frameWidth),
					frameHeight: Double(frameHeight),
					avgTexReps: theTexReps)

				theCommandEncoder.setVertexBytes(
					theBackgroundVertices,
					length: 4 * MemoryLayout<KaleidoTile2DVertexData>.stride,
					index: BufferIndexVFVertexAttributes)

				theBackgroundVertices.deallocate()
			}

			switch modelData.itsFacePaintings[bg].style {

			case .solidColor:

				theCommandEncoder.setRenderPipelineState(itsSolidColorBackgroundPipelineState)
				
				var theFaceColor = modelData.itsFacePaintings[bg].color
				theCommandEncoder.setFragmentBytes(
									&theFaceColor,
									length: MemoryLayout.size(ofValue: theFaceColor),
									index: BufferIndexFFColor)

			case .texture:

				theCommandEncoder.setRenderPipelineState(itsTextureBackgroundPipelineState)

				theCommandEncoder.setFragmentTexture(
									itsFaceTextures[bg],
									index: TextureIndexPrimary)
				
				theCommandEncoder.setFragmentSamplerState(
									itsBackgroundSamplerState,
									index: SamplerIndexPrimary)

			case .invisible:
				preconditionFailure("The .invisible case should have already been excluded by the enclosing if{}.")
			}
			
			theCommandEncoder.drawPrimitives(
				type: .triangleStrip,
				vertexStart: 0,
				vertexCount: 4)

			theCommandEncoder.popDebugGroup()
		}


		theCommandEncoder.pushDebugGroup("Draw tiling")

		theCommandEncoder.setVertexBytes(
			&theUniformData,
			length: MemoryLayout.size(ofValue: theUniformData),
			index: BufferIndexVFUniforms)

		//	When the orientation is flipped (det < 0),
		//	the plain instances all become reflected instances, and
		//	the reflected instances all become plain instances.
		let theOrientationIsFlipped = baseTriangleOnly ?
										false :
										modelData.itsOrientation.determinant < 0
		let theEffectivePlainInstanceCount: Int
		let theEffectivePlainInstances: MTLBuffer?
		let theEffectiveReflectedInstanceCount: Int
		let theEffectiveReflectedInstances: MTLBuffer?
		if theOrientationIsFlipped {	//	reflected chirality

			theEffectivePlainInstanceCount = theReflectedInstanceCount
			theEffectivePlainInstances = theReflectedInstances
			theEffectiveReflectedInstanceCount = thePlainInstanceCount
			theEffectiveReflectedInstances = thePlainInstances

		} else {						//	normal chirality
		
			theEffectivePlainInstanceCount = thePlainInstanceCount
			theEffectivePlainInstances = thePlainInstances
			theEffectiveReflectedInstanceCount = theReflectedInstanceCount
			theEffectiveReflectedInstances = theReflectedInstances
		}

		let directionalLighting = (
				modelData.itsBaseTriangle.geometry == .spherical
			 && !baseTriangleOnly)

		func encodeInstances(
			isRenderingInnerFaces: Bool
		) {

			for i in 0...2 {	//	which quad

				theCommandEncoder.setVertexBuffer(
									theVertexBuffers[i],
									offset: 0,
									index: BufferIndexVFVertexAttributes)

				switch modelData.itsFacePaintings[i].style {

				case .solidColor:
				
					theCommandEncoder.setRenderPipelineState(directionalLighting ?
						(isRenderingInnerFaces ?
							itsSolidColorDimmedPipelineState :
							itsSolidColorLitPipelineState
						) :
						itsSolidColorUnlitPipelineState)
					
					var theFaceColor = modelData.itsFacePaintings[i].color
					theCommandEncoder.setFragmentBytes(
										&theFaceColor,
										length: MemoryLayout.size(ofValue: theFaceColor),
										index: BufferIndexFFColor)
					
				case .texture:
				
					theCommandEncoder.setRenderPipelineState(directionalLighting ?
						(isRenderingInnerFaces ?
							itsTextureDimmedPipelineState :
							itsTextureLitPipelineState
						):
						itsTextureUnlitPipelineState)

					theCommandEncoder.setFragmentTexture(
										itsFaceTextures[i],
										index: TextureIndexPrimary)
					
					theCommandEncoder.setFragmentSamplerState(
						modelData.itsBaseTriangle.geometry == .spherical ?
							itsAnisotropicSamplerState : itsIsotropicSamplerState,
						index: SamplerIndexPrimary)

				case .invisible:
				
					//	Don't render this face at all.
					continue
				}

				if (modelData.itsShowPlainImages || baseTriangleOnly)
				&& theEffectivePlainInstanceCount > 0 {
				
					theCommandEncoder.setFrontFacing(.counterClockwise) //	in left-handed coordinate system
					theCommandEncoder.setVertexBuffer(
										theEffectivePlainInstances,
										offset: 0,
										index: BufferIndexVFInstanceData)
					theCommandEncoder.drawIndexedPrimitives(
						type: .triangle,
						indexCount: theFaceIndexCount,
						indexType: .uint16,
						indexBuffer: theFaceBuffer,
						indexBufferOffset: 0,
						instanceCount: theEffectivePlainInstanceCount)
				}
				
				if (modelData.itsShowReflectedImages || baseTriangleOnly)
				&& theEffectiveReflectedInstanceCount > 0 {
				
					theCommandEncoder.setFrontFacing(.clockwise) //	in left-handed coordinate system
					theCommandEncoder.setVertexBuffer(
										theEffectiveReflectedInstances,
										offset: 0,
										index: BufferIndexVFInstanceData)
					theCommandEncoder.drawIndexedPrimitives(
						type: .triangle,
						indexCount: theFaceIndexCount,
						indexType: .uint16,
						indexBuffer: theFaceBuffer,
						indexBufferOffset: 0,
						instanceCount: theEffectiveReflectedInstanceCount)
				}
			}
		}

		//	Render front faces in all three geometries.
		//
		//		Note:  As the comment in KaleidoTileMeshMaker.makeMeshes() explains,
		//		the user sees all tilings from the negative z side.
		//		That is, the user sees Euclidean and hyperbolic tilings "from underneath",
		//		and a spherical tiling's front faces lie on the inside of the sphere.
		//
		let theFrontFaceCullMode = (modelData.itsBaseTriangle.geometry == .spherical ?
			MTLCullMode.back :	//	spherical tilings need culling
			MTLCullMode.none)	//	euclidean and hyperbolic tilings do not
		theCommandEncoder.setCullMode(theFrontFaceCullMode)
		encodeInstances(isRenderingInnerFaces:
				modelData.itsBaseTriangle.geometry == .spherical
			 && !baseTriangleOnly)
		
		//	Render back faces only in spherical geometry,
		//	where they lie on the polyhedron's outer (not inner) surface.
		//
		//		Note:  KaleidoTile uses no depth buffer,
		//		so it's essential that we render back faces
		//		after front faces.
		//
		if modelData.itsBaseTriangle.geometry == .spherical {
			theCommandEncoder.setCullMode(MTLCullMode.front)
			encodeInstances(isRenderingInnerFaces: false)
		}

		theCommandEncoder.popDebugGroup()

		//	If this is the triple-point view, render the triple-point handle.
		if baseTriangleOnly {

			theCommandEncoder.pushDebugGroup("Draw triple-point handle")

			theCommandEncoder.setRenderPipelineState(itsTriplePointPipelineState)
			theCommandEncoder.setCullMode(.none)
			do {
				let theTriplePointVertices = UnsafeMutablePointer<KaleidoTile2DVertexData>.allocate(capacity: 4)

				setTriplePointVertices(
					theTriplePointVertices,
					triplePoint: modelData.itsTriplePoint,
					baseTriangle: modelData.itsBaseTriangle)

				theCommandEncoder.setVertexBytes(
					theTriplePointVertices,
					length: 4 * MemoryLayout<KaleidoTile2DVertexData>.stride,
					index: BufferIndexVFVertexAttributes)

				theTriplePointVertices.deallocate()
			}
			theCommandEncoder.drawPrimitives(
				type: .triangleStrip,
				vertexStart: 0,
				vertexCount: 4)

			theCommandEncoder.popDebugGroup()
		}

		theCommandEncoder.endEncoding()
	}
	
	func prepareUniformData(
		modelData: KaleidoTileModel,
		frameWidth: Double,
		frameHeight: Double,
		baseTriangleOnly: Bool
	) -> KaleidoTileUniformData {

		let theViewMatrix = baseTriangleOnly ?
								matrix_identity_double3x3 :
								modelData.itsOrientation
		let theViewMatrixExt = matrix4x4ExtendingMatrix3x3(theViewMatrix)
		let theProjectionMatrix = baseTriangleOnly ?
									makeProjectionMatrixForBaseTriangle(
										ndcPlacement: modelData.itsBaseTriangle.ndcPlacement) :
									makeProjectionMatrixForTiling(
										frameWidth: frameWidth,
										frameHeight: frameHeight)
		let theViewProjectionMatrix
			= theProjectionMatrix * theViewMatrixExt //	right-to-left matrix composition
		
		let theLightDirection = SIMD3<Double>(-0.27, +0.27, -0.92)
								//	points towards the light source
		
		let theViewerDirection = SIMD3<Double>(0.00,  0.00, -1.00)
								//	points towards the observer
		
		let theSpecularDirection = normalize(theLightDirection + theViewerDirection)
								//	direction of maximal specular reflection
								
		//	The light direction L is an honest vector,
		//	which we write as a column vector for consistency
		//	with SIMD's right-to-left matrix actions.
		//	By contrast a surface normal is, strictly speaking, a 1-form,
		//	which we write as a row vector for consistency
		//	with the right-to-left matrix actions.
		//	To compute the intensity of a light, we take the matrix product
		//	of the light direction with the surface normal:
		//
		//			          (Lx)
		//			(Nx Ny Nz)(Ly)
		//			          (Lz)
		//
		//	(Note:  If we were instead using left-to-right matrix actions,
		//	we'd take the transpose of everything in sight and
		//	write vectors as rows and 1-forms as columns.)
		//
		//	If we rotate the surface and the light source simultaneously
		//	using a matrix M, the light direction vector transforms
		//	as L → ML while the normal transforms as N → NM⁻¹,
		//	leaving their product
		//
		//			          (     )(     )(Lx)
		//			(Nx Ny Nz)( M⁻¹ )(  M  )(Ly)
		//			          (     )(     )(Lz)
		//
		//	invariant, as it must be.
		//
		//	In the present case, however, we want to leave
		//	the light source fixed while we rotate the polyhedron
		//	and its normals.  The product thus becomes
		//
		//			          (     )(Lx)
		//			(Nx Ny Nz)( M⁻¹ )(Ly)
		//			          (     )(Lz)
		//
		//	Conceptually we group the factors as (NM⁻¹)L,
		//	but to minimize the computational load on the GPU,
		//	it's convenient to regroup the factors as N(M⁻¹L)
		//	and pre-compute the product M⁻¹L, which we call
		//	a "normal evaluator".
		//
		//	In general we'd need to invert the matrix M to compute M⁻¹L.
		//	In O(3), however, the inverse is just the transpose.
		//	So instead of computing M⁻¹L we compute its transpose
		//
		//		transpose(M⁻¹L) = transpose(transpose(M) L)
		//						= transpose(L) M
		//
		let theDiffuseEvaluator = theLightDirection * theViewMatrix

		//	The same logic applies to compute theSpecularEvaluator.
		let theSpecularEvaluator = theSpecularDirection * theViewMatrix
		
		let theUniformData = KaleidoTileUniformData(
			itsViewProjectionMatrix: convertDouble4x4toFloat4x4(theViewProjectionMatrix),
			itsDiffuseEvaluator: SIMD3<Float16>(theDiffuseEvaluator),
			itsSpecularEvaluator: SIMD3<Float16>(theSpecularEvaluator) )
			
		return theUniformData
	}
	
	func makeProjectionMatrixForTiling(
		frameWidth: Double,	//	typically in pixels or points
		frameHeight: Double	//	typically in pixels or points
	) -> simd_double4x4 {	//	returns the projection matrix
	
		if frameWidth <= 0.0 || frameHeight <= 0.0 {
			assertionFailure("nonpositive-size frame received")
			return matrix_identity_double4x4
		}
		
		let theGeometry = itsTiling.preparedBaseTriangle.geometry

		let theIntrinsicUnitsPerPixelOrPoint = intrinsicUnitsPerPixelOrPoint(
													viewWidth: frameWidth,
													viewHeight: frameHeight,
													geometry: theGeometry)
		
		//	Compute the frame's half-width and half-height in intrinsic units.
		let w = 0.5 * frameWidth  * theIntrinsicUnitsPerPixelOrPoint	//	half width
		let h = 0.5 * frameHeight * theIntrinsicUnitsPerPixelOrPoint	//	half height

		//	Select an appropriate viewing distance, according to the geometry.
		let d: Double
		switch theGeometry {
		
		case .spherical:
		
			//	Assume the observer's eye is d intrinsic units
			//	from the center of the display.  We can't possibly
			//	know the true distance, so just make a plausible guess
			//	and hope for the best.
			d = 6.0
			
		case .euclidean:
		
			//	The viewing distance d is irrelevant in the Euclidean case
			//	because we'll use an orthogonal projection.
			d = 0.0
			
		case .hyperbolic:
			
			//	View the hyperboloid from z = -1,
			//	so the user sees the Poincaré disk model.
			d = 1.0
		}

		//	KaleidoTile uses no depth buffer, so we may safely
		//	set the near clip to 0 and the far clip to infinity.
		//
//		n → 0
//		f → ∞

		//	The eight points
		//
		//			(±n*(w/d), ±n*(h/d), n, 1) and
		//			(±f*(w/d), ±f*(h/d), f, 1)
		//
		//	define the view frustum.  More precisely,
		//	because the GPU works in 4D homogeneous coordinates,
		//	it's really a set of eight rays, from the origin (0,0,0,0)
		//	through each of those eight points, that defines
		//	the view frustum as a "hyper-wedge" in 4D space.
		//
		//	Because the GPU works in homogenous coordinates,
		//	we may multiply each point by any scalar constant we like,
		//	without changing the ray that it represents.
		//	So let divide each of those eight points through
		//	by its own z coordinate, giving
		//
		//			(±w/d, ±h/d, 1, 1/n) and
		//			(±w/d, ±h/d, 1, 1/f)
		//
		//	Geometrically, these points define the intersection
		//	of the 4D wedge with the hyperplane z = 1.
		//	Conveniently enough, this intersection is a rectangular box!
		//
		//	Our goal is to find a 4×4 matrix that takes this rectangular box
		//	to the standard clipping box with corners at
		//
		//			(±1, ±1, 0, 1) and
		//			(±1, ±1, 1, 1)
		//
		//	To find such a matrix, let's "follow our nose"
		//	and construct it as the product of several factors.
		//
		//		Note:  Unlike in older versions of the Geometry Games
		//		source code, matrices now act using
		//		the right-to-left (matrix)(column vector) convention,
		//		not the left-to-right (row vector)(matrix) convention.]
		//
		//	Factor #1
		//
		//		The quarter turn matrix
		//
		//			1  0  0  0
		//			0  1  0  0
		//			0  0  0 -1
		//			0  0  1  0
		//
		//		takes the eight points
		//			(±w/d, ±h/d, 1, 1/n) and
		//			(±w/d, ±h/d, 1, 1/f)
		//		to
		//			(±w/d, ±h/d, -1/n, 1) and
		//			(±w/d, ±h/d, -1/f, 1)
		//
		//	Factor #2
		//
		//		The xy dilation
		//
		//			d/w  0   0   0
		//			 0  d/h  0   0
		//			 0   0   1   0
		//			 0   0   0   1
		//
		//		takes
		//			(±w/d, ±h/d, -1/n, 1) and
		//			(±w/d, ±h/d, -1/f, 1)
		//		to
		//			(±1, ±1, -1/n, 1) and
		//			(±1, ±1, -1/f, 1)
		//
		//	Factor #3
		//
		//		The z dilation
		//
		//			1  0  0  0
		//			0  1  0  0
		//			0  0  a  0
		//			0  0  0  1
		//
		//		where a = n*f/(f - n), stretches or shrinks
		//		the box to have unit length in the z direction,
		//		taking
		//			(±1, ±1, -1/n, 1) and
		//			(±1, ±1, -1/f, 1)
		//		to
		//			(±1, ±1, -f/(f - n), 1) and
		//			(±1, ±1, -n/(f - n), 1)
		//
		//	Factor #4
		//
		//		The shear
		//
		//			1  0  0  0
		//			0  1  0  0
		//			0  0  1  b
		//			0  0  0  1
		//
		//		where b = f/(f - n), translates the hyperplane w = 1
		//		just the right amount to take
		//
		//			(±1, ±1, -f/(f - n), 1) and
		//			(±1, ±1, -n/(f - n), 1)
		//		to
		//			(±1, ±1, 0, 1) and
		//			(±1, ±1, 1, 1)
		//
		//		which are the vertices of the standard clipping box,
		//		which is exactly where we wanted to end up.
		//
		//	The projection matrix is the product (taken right-to-left!)
		//	of those four factors:
		//
		//			( 1  0  0  0 )( 1  0  0  0 )( d/w  0   0   0 )( 1  0  0  0 )
		//			( 0  1  0  0 )( 0  1  0  0 )(  0  d/h  0   0 )( 0  1  0  0 )
		//			( 0  0  1  b )( 0  0  a  0 )(  0   0   1   0 )( 0  0  0 -1 )
		//			( 0  0  0  1 )( 0  0  0  1 )(  0   0   0   1 )( 0  0  1  0 )
		//		=
		//			( d/w  0   0   0 )
		//			(  0  d/h  0   0 )
		//			(  0   0   b  -a )
		//			(  0   0   1   0 )
		//
		//
		//	If we let
		//
		//		n → 0
		//		f → ∞,
		//
		//	then
		//
		//		a → 0
		//		b → 1
		//
		//	and the projection matrix becomes
		//
		//			( d/w  0   0   0 )
		//			(  0  d/h  0   0 )
		//			(  0   0   1   0 )		//	always maps to z = 1
		//			(  0   0   1   0 )
		//
		//	Note:  We'll use this matrix in the spherical and hyperbolic cases,
		//	but not the Euclidean case.

		let theRawProjectionMatrix: simd_double4x4
		switch theGeometry {

		case .euclidean:

			//	To keep things simple, use an orthogonal projection.
			//	This ensures that the user will see exactly the view's
			//	intended diagonal size ( = characteristicViewSizeIU(.euclidean) = 2√2 ).
			//	With a perspective projection (and the tiling at z = +1)
			//	the user would see a slightly larger area, and in particular
			//	might see occasional gaps corresponding to images
			//	of the base triangle that shouldn't be visible.

			theRawProjectionMatrix = simd_double4x4(
				SIMD4<Double>(1.0/w, 0.0,  0.0, 0.0),
				SIMD4<Double>( 0.0, 1.0/h, 0.0, 0.0),
				SIMD4<Double>( 0.0,  0.0,  0.0, 0.0),
				SIMD4<Double>( 0.0,  0.0,  0.5, 1.0))

		case .spherical, .hyperbolic:
		
			//	Use a standard perspective projection.

			//	Technical Note:  In theory we can set aProjectionMatrix[2][2]
			//	to the values you get with n = 0 and f = ∞, and in practice
			//	this works fine on my computer.  But I'm a little nervous about having
			//	all vertices end up on the far face of the viewing volume (at z = w),
			//	just in case someday some system maps (x,y,z,1) → (…,…,z,z) and then
			//	divides to get z/z = 1.0000000000000001 or, even less likely,
			//	some non-compliant Metal implementation clips against 0 < z < +w
			//	instead of the prescribed 0 ≤ z ≤ +w.  Therefore, for added safety,
			//	I've artificially set aProjectionMatrix[2][2] = 0.5
			//	to force all vertices to the middle plane of the viewing volume.

			theRawProjectionMatrix = simd_double4x4(
				SIMD4<Double>(d/w, 0.0, 0.0, 0.0),
				SIMD4<Double>(0.0, d/h, 0.0, 0.0),
				SIMD4<Double>(0.0, 0.0, 0.5, 1.0),	//	for clipping to 0 ≤ z ≤ +w;
													//	f/(f-n) → 1 as n → 0 and f → ∞,
													//	but see Technical Note above
													
				SIMD4<Double>(0.0, 0.0, 0.0, 0.0))	//	for clipping to 0 ≤ z ≤ +w;
													//	-n*f/(f-n) → 0 as n → 0 and f → ∞
			
		}

		//	Let theTranslation be the first factor in the projection matrix
		//	rather than the last factor in the view matrix.
		var theTranslation = matrix_identity_double4x4
		theTranslation[3][2] = d
		let theProjectionMatrix
			= theRawProjectionMatrix	//	right-to-left matrix composition
			* theTranslation

		return theProjectionMatrix
	}
	
	func makeProjectionMatrixForBaseTriangle(
		ndcPlacement: NDCPlacement
	) -> simd_double4x4 {	//	returns the projection matrix

		//	We assume the frame is square.

		//	The ndcPlacement scales and offsets the base triangle so that
		//	it fills about 90% of the available "normalized device coordinates",
		//	which run from -1.0...+1.0 in each direction.
		let  s = ndcPlacement.scale
		let Δx = ndcPlacement.Δx
		let Δy = ndcPlacement.Δy
		
		//	Use an orthogonal projection.
		//	The z coordinate is largely irrelevant
		//	(KaleidoTile uses no depth buffer),
		//	so we may set it to 0.5 to ensure
		//	we have no depth clipping problems.
		let theProjectionMatrix = simd_double4x4(
			SIMD4<Double>(  s,  0.0, 0.0, 0.0),
			SIMD4<Double>( 0.0,  s,  0.0, 0.0),
			SIMD4<Double>( 0.0, 0.0, 0.0, 0.0),
			SIMD4<Double>( Δx,  Δy,  0.5, 1.0))
		
		return theProjectionMatrix
	}

	struct KaleidoTile2DVertexData {

		let pos: SIMD2<Float32>	//	position (x,y) in normalized device coordinates
								//		(with corners at (±1, ±1))

		let tex: SIMD2<Float32>	//	texture coordinates (u,v)
	}

	func setBackgroundVertices(
		_ vertices: UnsafeMutablePointer<KaleidoTile2DVertexData>,
		frameWidth: Double,		//	known to be > 0.0
		frameHeight: Double,	//	known to be > 0.0
		avgTexReps: Double?
	) {
	
		precondition(
			frameWidth > 0.0 && frameHeight > 0.0,
			"setBackgroundVertices() received a frame of zero width or height")

		//	The shader accepts vertex positions in normalized device coordinates,
		//	so we may place the rectangle's corners directly at (±1, ±1).
		//	But, if drawing a repeating background texture, we must adjust
		//	the texture coordinates to account for the view's aspect ratio,
		//	while ensuring that the view contains exactly (avgTexReps)² repetitions
		//	of the 2-dimensional texture.  In algebraic terms, we want
		//
		//		theTexRepsV / theTexRepsH = frameHeight / frameWidth
		//		theTexRepsV * theTexRepsH = avgTexReps * avgTexReps
		//
		//	It's easy to solve those equations to get
		//
		//		theTexRepsH = avgTexReps * sqrt(frameWidth / frameHeight)
		//		theTexRepsV = avgTexReps * sqrt(frameHeight / frameWidth)
		//
		let theTexRepsH: Float32
		let theTexRepsV: Float32
		if let theAvgTexReps = avgTexReps {
		
			theTexRepsH = Float32( theAvgTexReps * sqrt(frameWidth / frameHeight) )
			theTexRepsV = Float32( theAvgTexReps * sqrt(frameHeight / frameWidth) )
		
		} else {
			theTexRepsH = 1.0	//	ultimately irrelevant
			theTexRepsV = 1.0	//	ultimately irrelevant
		}

		vertices[0] = KaleidoTile2DVertexData(
			pos: SIMD2<Float32>(-1.0, -1.0),
			tex: SIMD2<Float32>( 0.0,  0.0))

		vertices[1] = KaleidoTile2DVertexData(
			pos: SIMD2<Float32>(-1.0, +1.0),
			tex: SIMD2<Float32>( 0.0, theTexRepsV))

		vertices[2] = KaleidoTile2DVertexData(
			pos: SIMD2<Float32>(+1.0, -1.0),
			tex: SIMD2<Float32>(theTexRepsH, 0.0))

		vertices[3] = KaleidoTile2DVertexData(
			pos: SIMD2<Float32>(+1.0, +1.0),
			tex: SIMD2<Float32>(theTexRepsH, theTexRepsV))
	}
	
	func setTriplePointVertices(
		_ vertices: UnsafeMutablePointer<KaleidoTile2DVertexData>,
		triplePoint: TriplePoint,
		baseTriangle: BaseTriangle
	) {
	
		let theRawTriplePoint = baseTriangle.barycentricBasis * triplePoint	//	right-to-left matrix action
		let theNormalizedTriplePoint = baseTriangle.geometry.metricForVertical.normalize(theRawTriplePoint)
		var theTriplePoint = SIMD2<Double>(
								theNormalizedTriplePoint[0],
								theNormalizedTriplePoint[1])
		theTriplePoint *= baseTriangle.ndcPlacement.scale
		theTriplePoint += SIMD2<Double>(
							baseTriangle.ndcPlacement.Δx,
							baseTriangle.ndcPlacement.Δy)
		
		let r = 0.0625	//	triple-point marker's radius in normalized device coordinates (NDC),
						//		which run from -1.0...+1.0 in each direction
		
		let x₀ = Float(theTriplePoint[0] - r)
		let x₁ = Float(theTriplePoint[0] + r)
		let y₀ = Float(theTriplePoint[1] - r)
		let y₁ = Float(theTriplePoint[1] + r)
	
		vertices[0] = KaleidoTile2DVertexData(
			pos: SIMD2<Float32>( x₀,   y₀ ),
			tex: SIMD2<Float32>(-1.0, -1.0))

		vertices[1] = KaleidoTile2DVertexData(
			pos: SIMD2<Float32>( x₀,   y₁ ),
			tex: SIMD2<Float32>(-1.0, +1.0))

		vertices[2] = KaleidoTile2DVertexData(
			pos: SIMD2<Float32>( x₁,   y₀ ),
			tex: SIMD2<Float32>(+1.0, -1.0))

		vertices[3] = KaleidoTile2DVertexData(
			pos: SIMD2<Float32>( x₁,   y₁ ),
			tex: SIMD2<Float32>(+1.0, +1.0))
	}

// MARK: -
// MARK: Texture import/export

	func setTexture(
		fromImage uncroppedImage: KTImage,
		onFace faceIndex: FaceIndex
	) {

		let theUncroppedCGImage = uncroppedImage.cgImage
		
		//	Crop the image to the largest enclosed square.
		let theWidthPx  = theUncroppedCGImage.width
		let theHeightPx = theUncroppedCGImage.height
		let theSizePx = min(theWidthPx, theHeightPx)
		let theCropRect = CGRect(
			origin: CGPoint(
				x: (theWidthPx  - theSizePx) / 2,	//	integer division discards remainder
				y: (theHeightPx - theSizePx) / 2),	//	integer division discards remainder
			size: CGSize(
				width:  theSizePx,
				height: theSizePx)
		)
		guard let theSquareCGImage = theUncroppedCGImage.cropping(to: theCropRect) else {
			assertionFailure("Couldn't crop theUncroppedImage in setTexture()")
			return
		}

		let theSquareImage = KTImage(
								cgImage: theSquareCGImage,
								scale: uncroppedImage.scale,
								orientation: uncroppedImage.orientation)

		//	Create the thumbail.
		guard let theThumbnailImage = makeThumbnail(squareImage: theSquareImage)
		else {
			assertionFailure("Couldn't make thumbnail in setTexture()")
			return
		}


		//	Make some modifications to the image
		//	in preparation for creating the MTLTexture.

		//	First package theSquareImage as a CIImage,
		//	so we can request modifications.
		let theRawCIImage = CIImage(cgImage: theSquareCGImage)

		//	Make sure the image is using premultiplied alpha.
		//	The documentation for premultiplyingAlpha() says
		//
		//		Premultiplied alpha speeds up the rendering of images,
		//		so Core Image filters require that input image data
		//		be premultiplied. If you have an image without
		//		premultiplied alpha that you want to feed into a filter,
		//		use this method [premultiplyingAlpha()] before
		//		applying the filter.
		//
		//	We'll want to be sending premultiplied alpha
		//	to the GPU fragment function in any case.
		//
		let thePremultipliedCIImage: CIImage
		switch theSquareCGImage.alphaInfo {
		
		case .first, .last:	//	.first and .last are non-premultiplied formats
			thePremultipliedCIImage = theRawCIImage.premultiplyingAlpha()
			
		case .none, .premultipliedLast, .premultipliedFirst, .noneSkipLast, .noneSkipFirst, .alphaOnly:
			fallthrough
		@unknown default:
			thePremultipliedCIImage = theRawCIImage
			
		}

		//	Rotate the image to the orientation that, in the case of a photo,
		//	is the orientation the user saw while taking the photo.
		//	theUncroppedCGImage will have arrived in the orientation
		//	of the device's physical camera sensor
		//	(which I think might always be landscape orientation,
		//	regardless of how the user was holding the device).

		//	Select an appropriate rotation to make the image "right side up".
		//
		//	CGAffineTransforms use the row-vector-times-matrix convention
		//
		//		       ( a  b  0 )
		//		(x y 1)( c  d  0 )
		//		       ( tx ty 1 )
		//
		//	The third column is always (0 0 1), so we don't need to write it.
		//
		//		Confession:  The resulting image will later get flipped
		//		top-to-bottom to agree with Metal's coordinate conventions.
		//		Here I just chose the rotation angle empirically,
		//		to find the one that works.
		//
		let theSize = CGFloat(theSizePx)
		let theRotation: CGAffineTransform
		switch uncroppedImage.orientation {
		
		case .up:
			//	The photo was taken with the device's home button
			//	on the right, meaning that the image pixels
			//	are already right side up (well, except for the
			//	top-to-bottom flip noted above).
			theRotation = CGAffineTransformMake(
							   1.0,     0.0,
							   0.0,     1.0,
							   0.0,     0.0)
			
		case .down:
			//	The photo was taken with the device's home button
			//	on the left, so the image needs a 180° rotation.
			theRotation = CGAffineTransformMake(
							  -1.0,     0.0,
							   0.0,    -1.0,
							 theSize, theSize)
			
		case .left:
			//	The photo was taken with the device's home button
			//	at the top, so the image needs a 90° counterclockwise rotation.
			theRotation = CGAffineTransformMake(
							   0.0,     1.0,
							  -1.0,     0.0,
							 theSize,   0.0)
			
		case .right:
			//	The photo was taken with the device's home button
			//	at the bottom, so the image needs a 90° clockwise rotation.
			theRotation = CGAffineTransformMake(
							   0.0,    -1.0,
							   1.0,     0.0,
							   0.0,   theSize)
			
		case .upMirrored, .downMirrored, .leftMirrored, .rightMirrored:
			//	The mirrored cases should never occur.
			fallthrough
		@unknown default:
			theRotation = CGAffineTransformMake(
							   1.0,     0.0,
							   0.0,     1.0,
							   0.0,     0.0)
		}
		let theRotatedCIImage = thePremultipliedCIImage.transformed(by: theRotation)
		let theCIContext = CIContext()
		let theRotatedCGImage = theCIContext.createCGImage(
											theRotatedCIImage,
											from: theRotatedCIImage.extent)
								?? theSquareCGImage
		
		//	Create the MTLTexture.
		let theTextureLoader = MTKTextureLoader(device: itsDevice)
		let theTextureLoaderOptions: [MTKTextureLoader.Option : Any] = [
		
			.SRGB :	//	meaning gamma-encoded or not
				NSNumber(value: false),
				
			.textureUsage :
				NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
				
			.textureStorageMode :
				NSNumber(value: MTLStorageMode.private.rawValue),
				
			.origin :
				MTKTextureLoader.Origin.bottomLeft,
				
			.allocateMipmaps :
				NSNumber(value: false),	//	theSrcTexture doesn't need mipmaps
				
			.generateMipmaps :
				NSNumber(value: false)	//	theSrcTexture doesn't need mipmaps
		]
		let theSrcTexture: MTLTexture
		do {
		
			theSrcTexture = try theTextureLoader.newTexture(
				cgImage: theRotatedCGImage,
				options: theTextureLoaderOptions)
				
		} catch {
			assertionFailure("Failed to convert imported UIImage to MTLTexture.  Error:  \(error)")
			return
		}
		
		//	At this point we've got a usable texture,
		//	except that we've ignored its color space.
		//	theUncroppedCGImage is probably a Display P3 image,
		//	so if we used theSrcTexture directly,
		//	the GPU fragment function would misinterpret
		//	theSrcTexture as an sRGB-gamut image,
		//	because the GPU does all its rendering
		//	in extended-range linear sRGB.
		//	To get correct colors, we must convert
		//	from the source color space (probably Display P3)
		//	to the GPU fragment function's native color space
		//	(always extended-range linear sRGB).
		
		guard let theSrcColorSpace = theUncroppedCGImage.colorSpace else {
			assertionFailure("Failed to get theSrcColorSpace")
			return
		}

		//	Prepare an empty destination texture
		//	appropriate for the host's display's color gamut.
		//
		let theDstPixelFormat: MTLPixelFormat
		let theDstColorSpace: CGColorSpace
		if gMainScreenSupportsP3 {

			//	theDstPixelFormat needs to support negative values
			//	for extended-range coordinates, and also needs
			//	to be writable from the MPSImageConversion GPU function.
			//
			//	Note that in theTextureLoaderOptions above,
			//	we must set .SRGB to
			//
			//		true  for a gamma-encoded pixel format, or
			//		false for a linear pixel format,
			//
			//	to get the colors to come out right.
			//
			theDstPixelFormat = .bgra10_xr	//	or .rgba16Float if we needed to export to CGImage
			guard let theExtendedLinearSRGBColorSpace
				= CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
			else {
				assertionFailure("Failed to get theExtendedLinearSRGBColorSpace")
				return
			}
			theDstColorSpace = theExtendedLinearSRGBColorSpace
			
		} else {
		
			//	There's no need to support negative values
			//	when rendering to a Narrow Color (linear sRGB) display.
			//
			theDstPixelFormat = .rgba8Unorm	//	non-extended linear coordinates
			guard let theLinearSRGBColorSpace
				= CGColorSpace(name: CGColorSpace.linearSRGB)
			else {
				assertionFailure("Failed to get theLinearSRGBColorSpace")
				return
			}
			theDstColorSpace = theLinearSRGBColorSpace
		}
		let theDstTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
										pixelFormat: theDstPixelFormat,
										width: theSizePx,
										height: theSizePx,
										mipmapped: true)
		theDstTextureDescriptor.usage = [.shaderWrite, .shaderRead]
		theDstTextureDescriptor.storageMode = .private
		guard let theDstTexture
			= itsDevice.makeTexture(descriptor: theDstTextureDescriptor)
		else {
			assertionFailure("Couldn't create theDstTexture in KaleidoTileRenderer.setTexture()")
			return
		}

		//	Prepare an MPSImageConversion object that will let us
		//	ask the GPU to convert from aSrcImage's original color space
		//	to the (typically Extended-Range) Linear sRGB color space.
		let theColorConversionInfo = CGColorConversionInfo(
										src: theSrcColorSpace,
										dst: theDstColorSpace)
		let theConversion = MPSImageConversion(
								device: itsDevice,
								srcAlpha: .premultiplied,
								destAlpha: .premultiplied,
								backgroundColor: nil,
								conversionInfo: theColorConversionInfo)

		//	Ask the GPU...
		guard let theCommandBuffer = itsCommandQueue.makeCommandBuffer() else {
			assertionFailure("Couldn't create theCommandBuffer in KaleidoTileRenderer.setTexture()")
			return
		}
		
		//		... to convert the texture to the pixel format
		//		and color space described above, and then...
		theConversion.encode(
			commandBuffer: theCommandBuffer,
			sourceTexture: theSrcTexture,
			destinationTexture: theDstTexture)

		//		... generate the mipmaps.
		GenerateMipmaps(for: theDstTexture, commandBuffer: theCommandBuffer)
		
		theCommandBuffer.commit()

		//	Done!
		itsFaceTextures[faceIndex.rawValue] = theDstTexture
		itsFaceThumbnails[faceIndex.rawValue] = theThumbnailImage
	}
			
	func makeThumbnail(
		squareImage: KTImage
	) -> KTImage? {

		let theWidthPx  = Double(squareImage.cgImage.width)
		let theHeightPx = Double(squareImage.cgImage.height)

		if theWidthPx != theHeightPx {
			assertionFailure("makeThumbnail() received an unexpectedly non-square squareImage")
			return nil
		}
		let theSizePx = theWidthPx

		let thumbnailSizePx = thumbnailSizePt * squareImage.scale
		
		//	Crop the image.
		//
		//	For aesthetic reasons, let's use only the middle quarter
		//	of the image (half the width and half the height) whenever possible.
		//
		let theHalfSize = floor(0.5 * theSizePx)
		let theCropSize = theHalfSize >= thumbnailSizePx ? theHalfSize : theSizePx
		let theCropOrigin = floor(0.5 * (theSizePx - theCropSize))
		let theCropRect = CGRect(
			origin: CGPoint(x: theCropOrigin, y: theCropOrigin),
			size:   CGSize(width: theCropSize, height: theCropSize)
		)
		guard let theCroppedImage = squareImage.cgImage.cropping(to: theCropRect) else {
			assertionFailure("Couldn't crop the squareImage in makeThumbnail()")
			return nil
		}
		
		//	Rescale the image.
		//
		//		To rescale an image, Core Graphics requires us
		//		to draw the image into a graphics context
		//		of the desired size.
		//
		let theThumbnailRect = CGRect(
								origin: .zero,
								size: CGSize(width: thumbnailSizePx, height: thumbnailSizePx))
		guard let theColorSpace = theCroppedImage.colorSpace else {
			assertionFailure("theCroppedImage has no color space in makeThumbnail()")
			return nil
		}
		guard let theContext = CGContext(
							data: nil,
							width: Int(thumbnailSizePx),
							height: Int(thumbnailSizePx),
							bitsPerComponent: theCroppedImage.bitsPerComponent,
							bytesPerRow: 0,
							space: theColorSpace,
							bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
			assertionFailure("Couldn't create the CGContext in makeThumbnail()")
			return nil
		}
		theContext.interpolationQuality = .high
		theContext.draw(theCroppedImage, in: theThumbnailRect)
		guard let theThumbnailImage = theContext.makeImage() else {
			assertionFailure("Couldn't create theThumbnailImage in makeThumbnail()")
			return nil
		}

		let theKTImage = KTImage(
							cgImage: theThumbnailImage,
							scale: squareImage.scale,
							orientation: squareImage.orientation)
		
		return theKTImage
	}

	func textureThumbnail(
		faceIndex: FaceIndex
	) -> KTImage {

		return itsFaceThumbnails[faceIndex.rawValue]
	}
	
	func textureThumbnailSizePt(
	) -> Double {
	
		return thumbnailSizePt
	}
	
	func setBackgroundTexture(
		backgroundTextureIndex: BackgroundTextureIndex
	) {

		let theTextureLoader = MTKTextureLoader(device: itsDevice)
		let theTextureLoaderOptions = [
			MTKTextureLoader.Option.textureUsage:       NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
			MTKTextureLoader.Option.textureStorageMode:	NSNumber(value: MTLStorageMode.`private`.rawValue)
		]

		do {

			let theTexture = try theTextureLoader.newTexture(
									name: backgroundTextureIndex.textureName,
									scaleFactor: 1.0,
									bundle: nil,
									options: theTextureLoaderOptions)

			itsFaceTextures[FaceIndex.background.rawValue] = theTexture
			
			//	Note:  We don't need to compute thumbnails
			//	for the background textures, because they've already
			//	been precomputed and stored in KaleidoTileAssets.xcassets
			//	as TableImages/Background/… .
			
		} catch {
			assertionFailure("Failed to load background texture.  Error:  \(error)")
		}
	}
}


// MARK: -
// MARK: Characteristic size

//	At render time the characteristic size will be used to deduce
//	the tiling view's width and height in intrinsic units.

func characteristicViewSize(
	width: Double,	//	typically in pixels or points
	height: Double,	//	typically in pixels or points
	geometry: GeometryType
) -> Double {		//	characteristic view size in pixels or points

	//	This is the *only* place that specifies the dependence
	//	of the characteristic size on the view dimensions.
	//	If you want to change the definition, for example
	//	from min(width,height) to sqrt(width*height),
	//	this is the only place you need to do it.
	
	switch geometry {
	
	case .spherical, .hyperbolic:

		//	Let the characteristic size be min(width, height),
		//	so the whole tiling fits within the view.
		//
		return min(width, height)
		
	case .euclidean:

		//	Let the characteristic size be √(width² + height²),
		//	so no part of the view gets left uncovered.
		//
		return sqrt( width * width  +  height * height )
	}
}

//	The characteristic size will always correspond
//	to the number of intrinsic units (IU) given below,
//	even as the user resizes the view and thus changes
//	the number of pixels lying within it.
//
func characteristicViewSizeIU(
	geometry: GeometryType
) -> Double {	//	characteristic view size in intrinsic units

	switch geometry {

	case .spherical:
		return 2.2				//	view's inradius is 1.1
		
	case .euclidean:
		return 2.0 * sqrt(2.0)	//	view's outradius is √2
		
	case .hyperbolic:
		return 2.125			//	view's inradius is 17/16, to allow
								//	a small margin around the Poincaré disk
	}
}

func intrinsicUnitsPerPixelOrPoint(
	viewWidth: Double,	//	typically in pixels or points
	viewHeight: Double,	//	typically in pixels or points
	geometry: GeometryType
) -> Double {	//	number of intrinsic units per pixel or point

	let theCharacteristicSizePp = characteristicViewSize(
									width: viewWidth,
									height: viewHeight,
									geometry: geometry)

	let theCharacteristicSizeIU = characteristicViewSizeIU(
									geometry: geometry)

	let theIntrinsicUnitsPerPixelOrPoint = theCharacteristicSizeIU / theCharacteristicSizePp
	
	return theIntrinsicUnitsPerPixelOrPoint
}
