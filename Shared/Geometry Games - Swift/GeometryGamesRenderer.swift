//	GeometryGamesRenderer.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt


import MetalKit


//	Notes on alpha blending
//
//	Alpha blending determines how the final fragment
//	blends in with the previous color buffer contents.
//	For opaque surfaces we can disable blending.
//	For partially transparent surfaces we may enable blending
//	but must take care to draw the scene in back-to-front order.
//
//	Whenever possible, avoid alpha-blending on iOS,
//	because the GPU's tile-based deferred rendering
//	works more efficiently with opaque surfaces.
//	If alpha-blending is needed, draw all opaque content first,
//	then draw transparent content.  (As well as drawing opaque
//	and transparent content, a third technique -- alpha-test
//	with possible "discard" -- is also possible, but this is
//	even less efficient than alpha-blending.  If alpha-test/discard
//	is unavoidable, then draw the content in the order (1) opaque,
//	(2) alpha-test/discard and (3) transparent, which makes sense.)
//
//	We represent colors as (αR, αG, αB, α) instead of
//	the traditional (R,G,B,α) to facilitate blending
//	and mipmap generation.
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

//	When the SwiftUI versions of all the Geometry Games apps
//	no longer use any C code, I can rename ModelDataType -> ModelData.
class GeometryGamesRenderer<ModelDataType> {

	let itsDevice: MTLDevice
	let itsCommandQueue: MTLCommandQueue
	let itsColorPixelFormat: MTLPixelFormat
	let itsDepthPixelFormat: MTLPixelFormat	//	= MTLPixelFormat.invalid if no depth buffer is needed
	let itsSampleCount: Int	//	typically 4 (for multisampling)
							//		   or 1 (for single-sampling)
	let itsClearColor: MTLClearColor


	init?(
		wantsMultisampling: Bool,
		wantsDepthBuffer: Bool,

		//	Specify clear color values in linear extended-range sRGB.
		//
		//		Warning:  With a partially transparent clearColor,
		//		there'd be the question of pre-multiplied alpha here,
		//		and also the question of gamma-encoding or not.
		//		For now, all the Geometry Games apps use either
		//		a fully opaque fully clearColor, or fully transparent black.
		//
		clearColor: MTLClearColor,

		//	isDrawingThumbnail is useful when making Thumbnails in KaleidoPaint and 4D Draw,
		//	because QuickLookThumbnailing doesn't support wide color.
		//	If QLThumbnailProvider starts supporting wide-gamut thumbnails
		//	at some future time, we can eliminate isDrawingThumbnail.
		isDrawingThumbnail: Bool = false
	) {

		guard let theDevice = MTLCreateSystemDefaultDevice() else {
			return nil
		}
		itsDevice = theDevice

		//	Extended range pixel formats
		//
		//		Apple's "extended range" pixel formats
		//
		//			bgr10_xr
		//			bgr10_xr_srgb
		//
		//		use sRGB color-space coordinates, but allow the color components
		//		to extend beyond the usual [0.0, 1.0] range, giving us access
		//		to wider color spaces like Display P3.
		//
		//		Any iDevice in the MTLGPUFamilyApple3 GPU family
		//		or higher supports extended range pixel formats
		//		when paired with a wide-color display.
		//		All such devices support iOS 13, while no earlier devices do,
		//		so by requiring iOS 13 or later (which SwiftUI needs
		//		in any case) we ensure that extended range pixel formats
		//		are available when needed.  When running on a device
		//		with a non-wide-color display, we may use bgra8Unorm_srgb instead.
		//
		//		Conclusion:  Extended range pixel formats are a big win,
		//		and all newly revised Geometry Games apps use them
		//		whenever the display supports wide color.
		//
		//	sRGB gamma decoding
		//
		//		The two pixel formats
		//
		//			bgr10_xr
		//			bgr10_xr_srgb
		//
		//		can both be used with the full Display P3 gamut.
		//		Somewhat counter-intuitively, the "_srgb" suffix
		//		doesn't mean that we're restricting to the sRGB gamut.
		//		Instead, it means that we're asking Metal to take
		//		the (possibly extended) linear sRGB values that we give it
		//		and automatically gamma-encode them before writing them
		//		into the frame buffer and, conversely, automatically
		//		gamma-decoding those values when reading them
		//		from the frame buffer.  Both Display P3 and sRGB
		//		use the same encoding function -- known as the
		//		"sRGB gamma-encoding function" -- which is why
		//		the suffix "_sRGB" is used to denote a request
		//		for this automatic gamma-encoding and -decoding.
		//
		//		When using a pixel format without the "_sRGB" suffix,
		//		Metal assumes we'll take responsibility for doing
		//		the encoding ourselves, for example in our fragment function.
		//		If we fail to do so, the mid-tones in the image will
		//		look too dark.  For example, if we pass a color component
		//		of 0.5, intending it as a linear value, and Metal
		//		interprets it as a gamma-encoded value of 0.5,
		//		it will come out as dark as a linear value of ~0.22.
		//
		//		Given that gamma-encoding is needed no matter what,
		//		we might as well let Metal take care of it automatically.
		//		So all newly revised Geometry Games apps use an _srgb pixel format.
		//
		//			Boring technical comment:  When I try reading a texture
		//			from the Asset Catalog as a Texture Set, the colors
		//			come out too dark when the frame buffer has
		//			a plain (non _srgb) pixel format, but come out correct
		//			when the frame buffer has an _srgb pixel format.
		//			So that's another reason to prefer an _srgb pixel format.
		//
		//			Unfounded speculation:  I'm guessing that gamma-encoding
		//			is inexpensive (perhaps with hardware support) and of course
		//			the GPU can keep linearized framebuffer data in tile memory,
		//			and gamma-encoding it just before writing it to system memory
		//			(but I don't really know whether it does that or not).
		//			In any case, gamma-encoded data is ultimately what
		//			the display will want to show.
		//
		//	Transparency
		//
		//		Even in apps that make extensive use of partial transparency
		//		while rendering, it's fine for the underlying frame buffer
		//		to be opaque.  The only exception would be if we want to export
		//		an image with a transparent background, in which case we may
		//		use the 64-bit pixel format
		//
		//			bgra10_xr_srgb
		//
		//		or alternatively
		//
		//			rgba16Float
		//
		//		also gives access to extended range sRGB color coordinates.
		//		Somewhat surprisingly, rgba16Float handles the gamma-encoding
		//		correctly, even though it has no _srgb suffix.
		//		I'm guessing the reason that Apple recommends bgra10_xr_srgb
		//		instead of rgba16Float is that, according to Apple,
		//		the display can use the former's 10-bit encoded
		//		color components directly.
		//
		//		2022-07-26  I've modified the Geometry Games apps
		//		to always support exporting with a transparent background.
		//		The 64-bit pixel format, as well as requiring the extra memory,
		//		also requires a little extra bus traffic at render time.
		//		But with Tile-Based Deferred Rendering, that extra traffic
		//		would, I think, happen only at the end of each render pass.
		//		Even graphically intensive apps like 4D Draw and Crystal Flight
		//		make only a single render pass, so if my reasoning is correct,
		//		each pixel gets written to the frame buffer only once.
		//		(KaleidoPaint makes lots of render passes into its intermediate
		//		unit cell textures, but only one pass into the final color buffer.)
		//
#if targetEnvironment(simulator)
		//	Apple Silicon Macs let free-standing iOS apps
		//	use extended-range pixel format, but the Simulator does not.
		//	The page
		//		https://stackoverflow.com/questions/47721708/display-p3-screenshots-from-ios-simulator
		//	says
		//
		//		Unfortunately, the QuartzCore software renderer only supports sRGB.
		//		There is no way to get extended range sRGB or P3 out of that render pipeline
		//		in the simulator.
		//
		itsColorPixelFormat = MTLPixelFormat.rgba16Float
#else
		itsColorPixelFormat = (
			(	gMainScreenSupportsP3	//	wide color available?
			 && !isDrawingThumbnail		//	wide color desired?
			) ?
			MTLPixelFormat.bgra10_xr_srgb :
			MTLPixelFormat.bgra8Unorm_srgb
		)
#endif
		itsDepthPixelFormat = (wantsDepthBuffer ?
									MTLPixelFormat.depth32Float :
									MTLPixelFormat.invalid)
		itsSampleCount = wantsMultisampling ? 4 : 1

		itsClearColor = clearColor

		guard let theCommandQueue = itsDevice.makeCommandQueue() else {
			return nil
		}
		itsCommandQueue = theCommandQueue
	}


// MARK: -
// MARK: Draw onscreen

	func render(
		modelData: ModelDataType,
		drawable: CAMetalDrawable,
		extraRenderFlag: Bool?
	) {
			
		//	Locate the drawable's MTLTexture.
		let theColorBuffer = drawable.texture

		//	Create a command buffer for the onscreen render pass.
		//	Be sure to do this before waiting on the semaphore,
		//	because if we return prematurely the semaphore won't get signaled.
		guard let theCommandBuffer = itsCommandQueue.makeCommandBuffer() else {
			assertionFailure("Failed to make theCommandBuffer")
			return
		}

		//	Create a render target using theColorBuffer.
		let theRenderPassDescriptor = CreateRenderTarget(
			device: itsDevice,
			colorBuffer: theColorBuffer,
			sampleCount: itsSampleCount,
			clearColor: itsClearColor,
			depthPixelFormat: itsDepthPixelFormat)

		//	Let the subclass encode an onscreen render pass.
		encodeCommands(
			modelData: modelData,
			commandBuffer: theCommandBuffer,
			renderPassDescriptor: theRenderPassDescriptor,
			frameWidth:  theColorBuffer.width,
			frameHeight: theColorBuffer.height,
			transparentBackground: false,
			extraRenderFlag: extraRenderFlag,
			quality: .animation)

		//	Ask Metal to present our results for display.
		theCommandBuffer.present(drawable)

		//	Commit theCommandBuffer to the GPU.
		theCommandBuffer.commit()

		//	KaleidoPaint may need to copy RLE-encoded flood-fill masks
		//	from its scratch buffer to invididual buffers,
		//	which it can allocate only *after* theCommandBuffer has
		//	completed and the required buffer sizes are known.
		didCommitCommandBuffer(theCommandBuffer, modelData: modelData)
	}


// MARK: -
// MARK: Draw offscreen

	func clampImageSize(requestedSizePx: Int) -> Int {

		let theMaxFramebufferSize = GetMaxFramebufferSizeOnDevice(itsDevice)

		if requestedSizePx == 0 {
			return 1
		}

		if requestedSizePx > theMaxFramebufferSize {
			return theMaxFramebufferSize
		}

		return requestedSizePx
	}

	func createOffscreenImage(
		modelData: ModelDataType,
		widthPx: Int,
		heightPx: Int,
		transparentBackground: Bool,
		extraRenderFlag: Bool?
	) -> CGImage? {
	
		//	Create the command buffer.
		guard let theCommandBuffer = itsCommandQueue.makeCommandBuffer() else {
			return nil
		}

		//	Create an offscreen color buffer.
		guard let theColorBuffer = CreateOffscreenColorBuffer(
			device: itsDevice,
			colorPixelFormat: itsColorPixelFormat,
			widthPx: widthPx,
			heightPx: heightPx
		) else {
			return nil
		}

		//	Create a render target using theColorBuffer.
		let theRenderPassDescriptor = CreateRenderTarget(
			device: itsDevice,
			colorBuffer: theColorBuffer,
			sampleCount: itsSampleCount,
			clearColor: transparentBackground ?
							MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0) :
							itsClearColor,
			depthPixelFormat: itsDepthPixelFormat)
		
		//	Encode the offscreen render pass.
		encodeCommands(
			modelData: modelData,
			commandBuffer: theCommandBuffer,
			renderPassDescriptor: theRenderPassDescriptor,
			frameWidth:  theColorBuffer.width,
			frameHeight: theColorBuffer.height,
			transparentBackground: transparentBackground,
			extraRenderFlag: extraRenderFlag,
			quality: .export)

		//	Draw the scene.
		theCommandBuffer.commit()
		theCommandBuffer.waitUntilCompleted()	//	This blocks!

		//	KaleidoPaint may need to copy RLE-encoded flood-fill masks
		//	from its scratch buffer to invididual buffers,
		//	which it can allocate only *after* theCommandBuffer has
		//	completed and the required buffer sizes are known.
		//
		//		Note:  KaleidoPaint's override of didCommitCommandBuffer()
		//		will also call waitUntilCompleted().  In practice there's
		//		no problem calling waitUntilCompleted() twice.
		//		Once the command buffer has in fact completed,
		//		then all such calls should return immediately.
		//
		didCommitCommandBuffer(theCommandBuffer, modelData: modelData)

		//	theColorBuffer is a MTLTexture created with a pixel format
		//
		//		MTLPixelFormat.bgr10_xr_srgb	(iDevice, opaque background)
		//			2022-07-26 Geometry Games apps no longer use bgr10_xr_srgb.
		//		MTLPixelFormat.bgra10_xr_srgb	(iDevice, transparent background)
		//		MTLPixelFormat.rgba16Float		(simulator or catalyst)
		//	or  MTLPixelFormat.bgra8Unorm_srgb
		//
		//	Even though a color buffer of format bgr10_xr_srgb or bgra10_xr_srgb
		//	stores gamma-encoded color components, the _srgb suffix
		//	asks that the values be automatically gamma-decoded when read.
		//	So when we call
		//
		//		CIImage(mtlTexture: theColorBuffer, options: nil)
		//
		//	theColorBuffer automatically decodes its gamma-encoded values
		//	and reports linearized values to the CIImage.
		//	For consistency, we must mark theCIContext's workingColorSpace
		//	as extendedLinearSRGB, because linearized values are what it will contain.
		//	(Caution:  I have no proof that that's how Core Image works,
		//	but it seems plausible.)
		//
		//	Even when using rgba16Float in Catalyst, the exported colors
		//	come out correct -- in the Display P3 color space
		//	with no gamma-encoding problems -- for reasons I don't fully understand.
		//	In any case, I don't plan to release SwiftUI versions
		//	of the Geometry Games apps for legacy Macs, so
		//	the publicly released version will never use rgba16Float.
		//
		guard let theWorkingColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else {
			return nil
		}
		guard let theOutputColorSpace = CGColorSpace(name: CGColorSpace.displayP3) else {
			return nil
		}

		//	Use a half-precision (16-bit) floating-point pixel format,
		//	to accommodate values below 0.0 and above 1.0,
		//	as extended sRGB coordinates require.
		//
		let thePixelFormat = CIFormat.RGBAh
		let theOptions: [CIContextOption : Any] = [
						CIContextOption.workingColorSpace: theWorkingColorSpace,
						CIContextOption.workingFormat:     thePixelFormat
		]
		let theCIContext = CIContext(options: theOptions)
		guard let theCIImage = CIImage(mtlTexture: theColorBuffer, options: nil) else {
			return nil
		}
		let theFlippedCIImage = theCIImage.oriented(CGImagePropertyOrientation.downMirrored)
		let theRect = CGRect(x: 0, y: 0, width: widthPx, height: heightPx)
		guard let theCGImage = theCIContext.createCGImage(
										theFlippedCIImage,
										from: theRect,
										format: thePixelFormat,
										colorSpace: theOutputColorSpace
		) else {
			return nil
		}

		return theCGImage
	}

	
// MARK: -
// MARK: For subclass override

	func encodeCommands(
		modelData: ModelDataType,
		commandBuffer: MTLCommandBuffer,
		renderPassDescriptor: MTLRenderPassDescriptor,
		frameWidth: Int,	//	in pixels
		frameHeight: Int,	//	in pixels
		transparentBackground: Bool,	//	Only KaleidoPaint and KaleidoTile need to know
										//	  transparentBackground while encoding commands.
		extraRenderFlag: Bool?,	//	Only KaleidoTile uses the extraRenderFlag,
								//	  which tells it whether it's rendering the full tiling
								//	  or the only the base triagle.
		quality: GeometryGamesImageQuality)
	{
		//	The GeometryGamesRenderer subclass should override encodeCommands()
		//	to do the actual drawing.
		
		//	If we want the GPU to clear the frame buffer to the background color,
		//	we must submit a command encoder.  An empty one is fine.
		if let theCommandEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
			theCommandEncoder.label = "Geometry Games dummy encoder"
			theCommandEncoder.endEncoding()
		}
	}

	func didCommitCommandBuffer(
		_ commandBuffer: MTLCommandBuffer,
		modelData: ModelDataType
	) {
		//	Each app-specific subclass may override this method if desired.
		//	In practice, only KaleidoPaint does so.
	}

	
	// MARK: -
 	// MARK: Utility methods

	func makeSamplerState(
		mode: MTLSamplerAddressMode,
		anisotropic: Bool
	) -> MTLSamplerState? {
		
		let theDescriptor = MTLSamplerDescriptor()

		theDescriptor.normalizedCoordinates = true

		theDescriptor.sAddressMode = mode
		theDescriptor.tAddressMode = mode

		theDescriptor.minFilter = MTLSamplerMinMagFilter.linear
		theDescriptor.magFilter = MTLSamplerMinMagFilter.linear
		theDescriptor.mipFilter = MTLSamplerMipFilter.linear
		
		theDescriptor.maxAnisotropy = (anisotropic ? 16 : 1)

		let theSamplerState = itsDevice.makeSamplerState(descriptor: theDescriptor)

		return theSamplerState
	}
}


enum GeometryGamesImageQuality {

	//	During animations, the renderer may want
	//	to strike a balance between image quality
	//	and rendering speed.  For example,
	//	Curved Spaces and Crystal Flight render
	//	progressively more distant objects
	//	using progressively coarser meshes.
	case animation
	
	//	When exporting a still image, the renderer
	//	may want to increase image quality
	//	at the expense of a longer render time.
	//	For example, Curved Spaces and Crystal Flight
	//	draw the whole scene using their best
	//	mesh refinements.
	case export
}


func CreateRenderTarget(
	device: MTLDevice,
	colorBuffer: MTLTexture,
	sampleCount: Int,	//	typically 4 (for multisampling)
						//		   or 1 (for single-sampling)
	clearColor: MTLClearColor,
	depthPixelFormat: MTLPixelFormat	//	= MTLPixelFormat.invalid if no depth buffer is needed
) -> MTLRenderPassDescriptor {

	//	Create a complete render target using the given colorBuffer.
	//	Note that theMultisampleBuffer, theDepthBuffer and theStencilBuffer,
	//	if present, will all be memoryless, so the present function creates
	//	a MTLRenderPassDescriptor without actually creating any new buffers.

	//	Render pass descriptor
	let theRenderPassDescriptor = MTLRenderPassDescriptor()

	//	Color buffer
	//
	//		Note:  colorAttachments[0] returns an implicitly unwrapped optional.
	//		The maximum value of n in colorAttachments[n] is a hardware-dependent constant,
	//		whose value is given in the Metal Feature Set Tables
	//
	//			https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf
	//
	//		in the Render Targets section, in the row labelled
	//		"Maximum number of color render targets per render pass descriptor".
	//		This maximum value is n = 4 for devices in the MTLGPUFamilyApple1
	//		(meaning A7 GPUs) and n = 8 for all later iOS devices (A8 and later,
	//		and all Macs).
	//
	let theColorAttachmentDescriptor: MTLRenderPassColorAttachmentDescriptor = theRenderPassDescriptor.colorAttachments[0]

	theColorAttachmentDescriptor.clearColor = clearColor
	theColorAttachmentDescriptor.loadAction = MTLLoadAction.clear	//	always MTLLoadAction.clear for robustness
	if sampleCount > 1 {
		let theMultisampleTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
												pixelFormat: colorBuffer.pixelFormat,
												width: colorBuffer.width,
												height: colorBuffer.height,
												mipmapped: false)
		theMultisampleTextureDescriptor.textureType = MTLTextureType.type2DMultisample
		theMultisampleTextureDescriptor.sampleCount = sampleCount
									//	must match value in pipeline state
		theMultisampleTextureDescriptor.usage = MTLTextureUsage.renderTarget
		theMultisampleTextureDescriptor.storageMode = MTLStorageMode.memoryless
		
		let theMultisampleBuffer = device.makeTexture(descriptor: theMultisampleTextureDescriptor)

		theColorAttachmentDescriptor.texture = theMultisampleBuffer
		theColorAttachmentDescriptor.resolveTexture = colorBuffer
		theColorAttachmentDescriptor.storeAction = MTLStoreAction.multisampleResolve
	}
	else {	//	sampleCount == 1
		theColorAttachmentDescriptor.texture = colorBuffer
		theColorAttachmentDescriptor.storeAction = MTLStoreAction.store
	}
	
	//	Depth buffer
	if depthPixelFormat != MTLPixelFormat.invalid {	//	Caller wants depth buffer?
		let theDepthTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
											pixelFormat: depthPixelFormat,
											width: colorBuffer.width,
											height: colorBuffer.height,
											mipmapped: false)
		if sampleCount > 1 {
			theDepthTextureDescriptor.textureType = MTLTextureType.type2DMultisample
			theDepthTextureDescriptor.sampleCount = sampleCount
		}
		else {	//	sampleCount == 1
			theDepthTextureDescriptor.textureType = MTLTextureType.type2D
			theDepthTextureDescriptor.sampleCount = 1
		}
		theDepthTextureDescriptor.usage = MTLTextureUsage.renderTarget
		theDepthTextureDescriptor.storageMode = MTLStorageMode.memoryless
		let theDepthBuffer = device.makeTexture(descriptor: theDepthTextureDescriptor)
		
		//	depthAttachment is an implicitly unwrapped optional.
		let theDepthAttachmentDescriptor: MTLRenderPassDepthAttachmentDescriptor = theRenderPassDescriptor.depthAttachment
		
		theDepthAttachmentDescriptor.texture = theDepthBuffer
		theDepthAttachmentDescriptor.clearDepth = 1.0
		theDepthAttachmentDescriptor.loadAction = MTLLoadAction.clear
		theDepthAttachmentDescriptor.storeAction = MTLStoreAction.dontCare
	}
	
	//	Stencil buffer (currently unused)
//	if false {	//	No current Geometry Games app needs a stencil buffer.
//				//	(If one does someday need a stencil buffer,
//				//	consider the possibility of a combined depth-stencil buffer,
//				//	implemented via an MTLDepthStencilDescriptor.)
//
//		let theStencilTextureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
//											pixelFormat: MTLPixelFormat.stencil8,
//											width: colorBuffer.width,
//											height: colorBuffer.height,
//											mipmapped: false)
//		if sampleCount > 1 {
//			theStencilTextureDescriptor.textureType = MTLTextureType.type2DMultisample
//			theStencilTextureDescriptor.sampleCount = sampleCount
//		}
//		else {	//	sampleCount == 1
//			theStencilTextureDescriptor.textureType = MTLTextureType.type2D
//			theStencilTextureDescriptor.sampleCount = 1
//		}
//		theStencilTextureDescriptor.usage = MTLTextureUsage.renderTarget
//		theStencilTextureDescriptor.storageMode = MTLStorageMode.memoryless
//		let theStencilBuffer = device.makeTexture(descriptor: theStencilTextureDescriptor)
//
		//	stencilAttachment is an implicitly unwrapped optional.
//		let theStencilAttachmentDescriptor: MTLRenderPassStencilAttachmentDescriptor = theRenderPassDescriptor.stencilAttachment
//
//		theStencilAttachmentDescriptor.texture = theStencilBuffer
//		theStencilAttachmentDescriptor.clearStencil = 0
//		theStencilAttachmentDescriptor.loadAction = MTLLoadAction.clear
//		theStencilAttachmentDescriptor.storeAction = MTLStoreAction.dontCare
//	}
	
	//	All done!
	return theRenderPassDescriptor
}


//	Create a color buffer for offscreen rendering,
//	typically in response to a Copy Image or Save Image command.
//
func CreateOffscreenColorBuffer(
	device: MTLDevice,
	colorPixelFormat: MTLPixelFormat,
	widthPx: Int,	//	in pixels, not points
	heightPx: Int	//	in pixels, not points
) -> MTLTexture? {

	let theColorBufferDescriptor = MTLTextureDescriptor.texture2DDescriptor(
									pixelFormat: colorPixelFormat,
									width: widthPx,
									height: heightPx,
									mipmapped: false)
	theColorBufferDescriptor.textureType = MTLTextureType.type2D
		//	Be sure to include MTLTextureUsage.shaderRead
		//	so Core Image can read the pixels afterwards.
	theColorBufferDescriptor.usage = [MTLTextureUsage.renderTarget, MTLTextureUsage.shaderRead]
	theColorBufferDescriptor.storageMode = MTLStorageMode.private
	let theColorBuffer = device.makeTexture(descriptor: theColorBufferDescriptor)
	
	return theColorBuffer
}


func GetMaxFramebufferSizeOnDevice(_ device: MTLDevice) -> Int {

	let theMaxTextureSize: Int

	//	A color buffer gets created in Metal as a texture, via the call
	//
	//		device.makeTexture(descriptor: theColorBufferDescriptor)
	//
	//	so the maximum texture size also tells the maximum framebuffer size.

	if
		device.supportsFamily(MTLGPUFamily.apple9)	//	Apple A17, M3, M4
	 || device.supportsFamily(MTLGPUFamily.apple8)	//	Apple A15, A16, M2
	 || device.supportsFamily(MTLGPUFamily.apple7)	//	Apple A14, M1
	 || device.supportsFamily(MTLGPUFamily.apple6)	//	Apple A13
	 || device.supportsFamily(MTLGPUFamily.apple5)	//	Apple A12
	 || device.supportsFamily(MTLGPUFamily.apple4)	//	Apple A11
	 || device.supportsFamily(MTLGPUFamily.apple3)	//	Apple A9, A10
	{
		theMaxTextureSize = 16384
	}
	else
	if  device.supportsFamily(MTLGPUFamily.apple2)	//	Apple A8
	 || device.supportsFamily(MTLGPUFamily.apple1)	//	Apple A7
	{
		theMaxTextureSize =  8192
	}
	else
	if  device.supportsFamily(MTLGPUFamily.mac2)	//	unspecified Mac GPUs
	{
		theMaxTextureSize = 16384
	}
	else
	if  device.supportsFamily(MTLGPUFamily.common3)
	 || device.supportsFamily(MTLGPUFamily.common2)
	 || device.supportsFamily(MTLGPUFamily.common1)
	{
		//	If we're running on something other than an Apple Silicon GPU
		//	or an Intel Mac GPU, then we'll end up here.
		//	Alas as of 3 November 2019, the documentation
		//	for the three "Common" GPU families gives
		//	feature availability but no implementation limits.
		//	So let's just try to make a safe-ish guess,
		//	and hope for the best.
		theMaxTextureSize =  8192	//	UNDOCUMENTED GUESS
	}
	else
	{
		//	The only way we could get to this point
		//	would be if MTLDevice denied supporting
		//	MTLGPUFamily.apple8 and all earlier feature sets.
		assertionFailure("MTLDevice denies support for all known MTLGPUFamilies (as of April 2023).")
		theMaxTextureSize = 16384
	}
	
	return theMaxTextureSize
}


func GenerateMipmaps(
	for texture: MTLTexture,
	commandBuffer: MTLCommandBuffer) {

	if texture.mipmapLevelCount > 1 {
		
		//	Apple's page
		//
		//		https://developer.apple.com/documentation/metal/mtlblitcommandencoder/1400748-generatemipmapsfortexture
		//
		//	doesn't say whether generateMipmapsForTexture: expects
		//	pre-multiplied alpha or not.  But Eric Haines' page
		//
		//		https://www.realtimerendering.com/blog/gpus-prefer-premultiplication/
		//
		//	strongly implies that pre-multiplied alpha is standard
		//	on current GPUs and their drivers.  This is good news,
		//	because the GeometryGames apps all use pre-multiplied alpha
		//	throughout.  (Indeed my original reason for using pre-multiplied alpha
		//	was to make blending and mipmapping easier, back in the old days
		//	when the Geometry Games own code was doing the mipmapping.)
		//
		if let theBlitEncoder = commandBuffer.makeBlitCommandEncoder() {
			theBlitEncoder.label = "make mipmap levels"
			theBlitEncoder.generateMipmaps(for: texture)
			theBlitEncoder.endEncoding()
		}
	}
}
