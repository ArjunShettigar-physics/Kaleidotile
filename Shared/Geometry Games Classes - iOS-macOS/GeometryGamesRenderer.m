//	GeometryGamesRenderer.m
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt


#import "GeometryGamesRenderer.h"
#import "GeometryGamesGPUDefinitions.h"
#import "GeometryGamesUtilities-Common.h"
#import "GeometryGamesUtilities-Mac-iOS.h"
#import <QuartzCore/QuartzCore.h>	//	for CAMetalLayer
#import <MetalKit/MetalKit.h>		//	for MTKTextureLoader
#if TARGET_OS_IOS
#import "GeometryGamesUtilities-iOS.h"
#endif
#import "GeometryGamesColorSpaces.h"


static MTLRenderPassDescriptor *CreateRenderTarget(id<MTLDevice> aDevice,
	MTLPixelFormat aColorPixelFormat, MTLPixelFormat aDepthPixelFormat, MTLPixelFormat aStencilPixelFormat,
	NSUInteger aWidthPx, NSUInteger aHeightPx, bool aMultisamplingFlag,
	MTLClearColor aClearColor);


//	Privately-declared methods
@interface GeometryGamesRenderer()
- (MTLRenderPassDescriptor *)renderPassDescriptorUsingDrawable:(id<CAMetalDrawable>)aDrawable modelData:(ModelData *)md;
- (MTLClearColor)adjustedClearColorWithModelData:(ModelData *)md;
@end


@implementation GeometryGamesRenderer
{
	CAMetalLayer			* __weak itsMetalLayer;
	
	id<MTLTexture>			itsMultisampleBuffer,
							itsDepthBuffer,
							itsStencilBuffer;

	//	Keep several instances of each "inflight" data buffer,
	//	so that while the GPU renders a frame using one buffer,
	//	the CPU can already be filling another buffer in preparation
	//	for the next frame.  To synchronize buffer access,
	//	the CPU will wait on itsInflightBufferSemaphore
	//	before writing to the next buffer, and then
	//	the command buffer's completion handler will
	//	signal itsInflightBufferSemaphore when the GPU's
	//	done with that buffer.
	unsigned int			itsInflightBufferIndex;	//	= 0, 1, … , (NUM_INFLIGHT_BUFFERS - 1)
	dispatch_semaphore_t	itsInflightBufferSemaphore;

	//	Pipeline states for utility functions.
	id<MTLComputePipelineState>	itsSolidColorPipelineState,
								itsTextureRoughingPipelineState;
}


- (id)initWithLayer:(CAMetalLayer *)aLayer device:(id<MTLDevice>)aDevice
	multisampling:(bool)aMultisamplingFlag depthBuffer:(bool)aDepthBufferFlag stencilBuffer:(bool)aStencilBufferFlag
	mayExportWithTransparentBackground:(bool)aMayExportWithTransparentBackgroundFlag
{
	self = [super init];
	if (self != nil)
	{

#if TARGET_OS_IOS

#if TARGET_CPU_ARM64

		//	Metal expects a gamma-encoded framebuffer no matter what.
		//	The simplest way to supply one is to select of the pixel formats
		//	with an _sRGB suffix.  These pixel formats ask Metal to take
		//	the linear values that our GPU function returns, and automatically
		//	gamma-encode them before writing them into the frame buffer.
		//
		//		Note #1:  The _sRGB pixel format can also be used
		//		to ask Metal to automatically decode values that
		//		it passes from a MTLTexture into our shader
		//		(so the shader always works with linear color components),
		//		but no such decoding happens when Metal passes
		//		the frame buffer to the compositor -- and thence
		//		to the display -- which wants gamma-encoded values
		//		in any case.
		//
		//		Note #2:  With a non _sRGB pixel format, our own code
		//		would need to do the gamma-encoding manually.
		//
		if (MainScreenSupportsP3())
		{
			if (aMayExportWithTransparentBackgroundFlag)
				itsColorPixelFormat = MTLPixelFormatBGRA10_XR_sRGB;	//	64-bit format
			else
				itsColorPixelFormat = MTLPixelFormatBGR10_XR_sRGB;	//	32-bit format
		}
		else	//	fall back to sRGB color space
		{
			itsColorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;	//	32-bit format
		}

#elif TARGET_CPU_X86_64	//	iOS simulator or MacCatalyst on Intel Mac

		//	Intel Macs don't support bgr10_xr_srgb or bgra10_xr_srgb,
		//	but luckily rgba16Float also gives access to extended range sRGB color coordinates.
		//	I'm guessing the reason that iOS uses bgra10_xr_srgb
		//	instead of rgba16Float is that, according to Apple,
		//	the display can use the former's 10-bit encoded
		//	color components directly.
		//
		//	RGBA16Float accepts linear P3 values and somehow ends up
		//	displaying gamma-encoded P3 values.  To be honest
		//	I'm not sure whether
		//
		//		- the linear values we pass in get gamma-encoded
		//			as we write them into the frame buffer
		//			(seems less likely), or
		//
		//		- the compositor gamma-encodes the linear values
		//			as it reads them from the frame buffer
		//			(seems more likely).
		//
		//	Whatever the mechanism might be, the final color
		//	comes out as gamma-encoded, with no explicit conversion
		//	on our part.
		//
		itsColorPixelFormat = MTLPixelFormatRGBA16Float;

#else
#error Compiling for unexpected CPU
#endif	//	TARGET_CPU_

#endif	//	TARGET_OS_IOS

#if TARGET_OS_OSX

		//	On macOS, GeometryGamesGraphicsViewMac has
		//	set the color space to Display P3.
		//	We don't need coordinates outside the range [0.0, 1.0],
		//	but we do need gamma-encoding.
		itsColorPixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;

#endif	//	TARGET_OS_OSX

		itsMultisamplingFlag	= aMultisamplingFlag;
		itsDepthBufferFlag		= aDepthBufferFlag;
		itsStencilBufferFlag	= aStencilBufferFlag;
//	The renderer shouldn't be storing itsOnscreenNativeSizePx either.  See comment re CAMetalLayer below.
		itsOnscreenNativeSizePx	= CGSizeZero;	//	-viewSizeOrScaleFactorDidChange: will set itsOnscreenNativeSizePx.

//	The renderer shouldn't be storing all this information about the CAMetalLayer.
//	Instead, a renderer should be prepared to render into whatever target it's given,
//	without needing to know anything about that target in advance except for the pixel format,
//	which the renderer's pipeline states need to know about.
//	With this approach, the view (not the renderer) would take responsibility
//	for providing a drawable, and the renderer would simply render the scene
//	into whatever target the renderpass descriptor provides.
//	(This approach is already be present in the SwiftUI version, which uses MetalKit.)
		itsMetalLayer	= aLayer;

		itsDevice		= aDevice;
		itsCommandQueue = [itsDevice newCommandQueue];
		
		//	If the caller requested multisampling but the hardware
		//	doesn't support the expected number of samples per pixel,
		//	then disable multisampling.
		if (itsMultisamplingFlag && ! [itsDevice supportsTextureSampleCount:METAL_MULTISAMPLING_NUM_SAMPLES])
			itsMultisamplingFlag = false;

		[itsMetalLayer setDevice:itsDevice];
		[itsMetalLayer setPixelFormat:itsColorPixelFormat];
		[itsMetalLayer setFramebufferOnly:YES];
		//	itsMetalLayer.colorspace has already been set,
		//	either by default on iOS, or explicitly on macOS.

		//	The first time we draw the scene,
		//	-renderPassDescriptorUsingDrawable:modelData:
		//	will create the required auxiliary buffers.
		itsMultisampleBuffer	= nil;
		itsDepthBuffer			= nil;
		itsStencilBuffer		= nil;

		itsInflightBufferIndex		= 0;
		itsInflightBufferSemaphore	= dispatch_semaphore_create(NUM_INFLIGHT_BUFFERS);
		

		//	Does the host support non-uniform threadgroup sizes?
#if TARGET_OS_IOS
		if (@available(iOS 13.0, *))	//	-supportsFamily: requires iOS 13 or higher
		{
			//	Non-uniform threadgroup sizes are available
			//	in MTLGPUFamilyApple4 and higher, meaning an A11 GPU or newer.
			itsNonuniformThreadGroupSizesAreAvailable = [itsDevice supportsFamily:MTLGPUFamilyApple4];
		}
		else
		{
			itsNonuniformThreadGroupSizesAreAvailable = false;
		}
#else	//	macOS

		//	Non-uniform threadgroup sizes are available
		//	in MTLGPUFamilyMac1 and higher.
		//	I've been unable to find any documentation
		//	saying which Macs support MTLGPUFamilyMac1.
		//	All I know is that my
		//
		//		MacBook Pro (13-inch, Late 2016, Two Thunderbolt 3 ports)
		//
		//	supports both MTLGPUFamilyMac1 and MTLGPUFamilyMac2.
		itsNonuniformThreadGroupSizesAreAvailable = [itsDevice supportsFamily:MTLGPUFamilyMac1];
#endif
	}
	return self;
}

- (MTLPixelFormat)colorPixelFormat
{
	return itsColorPixelFormat;
}

- (CGColorSpaceRef)colorSpaceRef
{
	return [itsMetalLayer colorspace];
}

- (void)setUpGraphicsWithModelData:(ModelData *)md
{
	//	The app-specific subclass will override this method,
	//	and must call this superclass implementation.

	id<MTLLibrary>	theGPUFunctionLibrary;
	id<MTLFunction>	theGPUComputeFunctionSolidColor,
					theGPUComputeFunctionTextureRoughening;

	//	Set up the pipeline states needs for some handy utility functions.
	//
	//		Note:  Not all the Geometry Games apps use these
	//		utility functions.  So to avoid creating unnecessary
	//		pipeline states, we could leave these references
	//		set to nil here, and then set up any required states
	//		later on, if and when they're needed.  However...
	//		these pipeline states and their respective GPU functions
	//		shouldn't be particularly memory intensive,
	//		so for simplicity let's go ahead and set them up now,
	//		whether or not they'll ultimately be needed.
	//
	theGPUFunctionLibrary = [itsDevice newDefaultLibrary];

	theGPUComputeFunctionSolidColor	= [theGPUFunctionLibrary newFunctionWithName:@"GeometryGamesComputeFunctionSolidColor"];
	itsSolidColorPipelineState		= [itsDevice newComputePipelineStateWithFunction:theGPUComputeFunctionSolidColor error:NULL];

	theGPUComputeFunctionTextureRoughening	= [theGPUFunctionLibrary newFunctionWithName:@"GeometryGamesComputeFunctionRoughenTexture"];
	itsTextureRoughingPipelineState			= [itsDevice newComputePipelineStateWithFunction:theGPUComputeFunctionTextureRoughening error:NULL];
}

- (void)shutDownGraphicsWithModelData:(ModelData *)md
{
	//	The app-specific subclass will override this method,
	//	and must call this superclass implementation.

	//	Clear our references to the multisample, depth and stencil buffers
	//	(if present), so that they may be deallocated.
	//	Our renderPassDescriptorUsingDrawable:modelData: method
	//	will re-create them when needed.
	itsMultisampleBuffer	= nil;
	itsDepthBuffer			= nil;
	itsStencilBuffer		= nil;
	
	//	Clear our references to our utility functions' pipeline states.
	itsSolidColorPipelineState		= nil;
	itsTextureRoughingPipelineState	= nil;
	
	//	Keep our references to the other Metal objects (itsMetalLayer,
	//	itsDevice, itsCommandQueue and also itsInflightBufferSemaphore).
	//	While it might be possible to delete and later re-create, say,
	//	itsCommandQueue, I'd rather not go looking for trouble at this point.
}


#pragma mark -
#pragma mark resize

- (void)viewSizeOrScaleFactorDidChange:(CGSize)aNativeSizePx modelData:(ModelData *)md
{
	//	We don't need the ModelData's contents,
	//	but do rely on it as a lock for thread safety in the macOS version,
	//	whose CVDisplayLink runs the animation in a separate thread.
	//
	UNUSED_PARAMETER(md);	//	md is needed only for thread safety
	
	itsOnscreenNativeSizePx = aNativeSizePx;

	[itsMetalLayer setDrawableSize:aNativeSizePx];
}


#pragma mark -
#pragma mark render

- (void)drawViewWithModelData:(ModelData *)md
{
	//	I'm not sure whether we'll ever get called with a zero-size view or not,
	//	but just to be safe...
	if (itsOnscreenNativeSizePx.width <= 0.0 || itsOnscreenNativeSizePx.height <= 0.0)
		return;

	//	Apple's pages
	//		https://developer.apple.com/reference/quartzcore/cametallayer/1478172-nextdrawable
	//		https://developer.apple.com/library/content/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/Drawables.html
	//	both strongly suggest enclosing any code that uses a CAMetalDrawable
	//	in a tight autorelease pool block.  theCurrentDrawable will be
	//	a transient CAMetalDrawable, but it will contain a reference to one
	//	of a finite number (maybe 3?) of persistent frame buffers.
	//	So if we kept references to three CAMetalDrawables at the same time,
	//	we'd exhaust the pool, and the next call to [itsMetalLayer nextDrawable]
	//	would block, effectively deadlocking the app.  That said, I'm not entirely
	//	sure why the run loop's default autorelease pool isn't good enough.
	//	Indeed in practice it seems to work fine.  At the risk of indulging
	//	in "cargo cult programming", I've gone ahead and put an autorelease pool
	//	here, partly to guard against surprises in the iOS versions of these apps
	//	(maybe Curved Spaces for iOS, with possible slower frame rates,
	//	will encounter bottlenecks that the faster apps like Torus Games do not?),
	//	and partly to be prepared for possible framework differences
	//	when I use this code in the upcoming macOS versions of the apps.
	//
	@autoreleasepool
	{
		//	theInflightDataBuffers will contain an app-specific collection of objects.
		//	Typically the contents will all be of type id<MTLBuffer>,
		//	but there are some exceptions, for example Curved Spaces
		//	inserts a TilingBufferSet along with an id<MTLBuffer>.
		NSDictionary<NSString *, id>	*theInflightDataBuffers;
		id<CAMetalDrawable>				theCurrentDrawable;
		MTLRenderPassDescriptor			*theRenderPassDescriptor;
		id<MTLCommandBuffer>			theCommandBuffer;

		//	Apple's page
		//
		//		https://developer.apple.com/library/content/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/TripleBuffering.html
		//
		//	explains very clearly the triple-buffering strategy implemented below.

		//	With triple buffering, when we go to draw frame n, the GPU will
		//	typically have already finished drawing frame n - 3 and signaled
		//	the semaphore to let us know that the inflight buffers from frame n - 3
		//	may be safely reused for frame n.  In the atypical case that frame n - 3
		//	has not yet completed, we must wait here for it to do so.
		dispatch_semaphore_wait(itsInflightBufferSemaphore, DISPATCH_TIME_FOREVER);
		itsInflightBufferIndex = (itsInflightBufferIndex + 1) % NUM_INFLIGHT_BUFFERS;

		//	Given that itsInflightBufferSemaphore has already been signaled,
		//	it seems unlikely that [itsMetalLayer nextDrawable] would block
		//	(maybe provably impossible, if the CAMetalLayer is doing triple buffering...
		//	hmmm... unless Metal holds onto the drawable while displaying the frame,
		//	even after releasing the data buffers).
		//	Nevertheless, Apple's CAMetalLayer documentation says
		//
		//		For best results, schedule your next​Drawable call
		//		as late as possible relative to other per-frame CPU work.
		//
		//	and also Apple's Metal Best practices guide at
		//
		//		https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/Drawables.html#//apple_ref/doc/uid/TP40016642-CH2-SW1
		//
		//	also says to
		//
		//		Always acquire a drawable as late as possible;
		//		preferably, immediately before encoding an on-screen render pass.
		//		A frame’s CPU work may include dynamic data updates and
		//		off-screen render passes that you can perform before acquiring a drawable.
		//
		//	So let's follow that advice and prepare the inflight buffers
		//	before rather than after calling [itsMetalLayer nextDrawable].
		//
		//		Design notes:
		//
		//		For the Geometry Games apps, this call
		//		to -prepareInflightDataBuffersAtIndex:modelData:
		//		is quite fast (even for Curved Spaces!) .
		//
		//		On the one hand, it's tempting to wait and prepare
		//		the inflight data buffers in the call to
		//		-encodeCommandsToCommandBuffer…, where the buffers'
		//		contents may be set along with the render commands
		//		that use them.
		//
		//		On the other hand, it makes sense to define
		//		as much of the buffers' contents as possible
		//		in platform-independent C code (so that the same code
		//		currently used for these Metal versions of the apps
		//		may be used to fill the buffers in any future
		//		DX12 and/or Vulkan versions as well), in which case
		//		the buffer-filling code must be in a separate file
		//		from the buffer-using code.
		//
		//		So for now I'm happy to leave well enough alone,
		//		and call -prepareInflightDataBuffersAtIndex:modelData:
		//		to prepare the buffers, before calling [itsMetalLayer nextDrawable].
		//
		theInflightDataBuffers = [self prepareInflightDataBuffersAtIndex:itsInflightBufferIndex modelData:(ModelData *)md];

		//	Ask itsMetalLayer for the next available color buffer.
		theCurrentDrawable = [itsMetalLayer nextDrawable];

		//	The call to nextDrawable will time out and return nil
		//	if no drawable becomes available within 1 second, and
		//	of course may fail if the layer's pixel format
		//	or other properties are invalid (or, in theory, if the view and
		//	its CAMetalLayer have disappeared, but some other object still
		//	retains a strong reference to this renderer).  So in practice,
		//	the call to nextDrawable should never fail.  But if it did ever
		//	fail unexpectedly (maybe upon waking from sleep, for example),
		//	simply abort this call to -drawViewWithModelData and wait
		//	for the animation timer to fire again.
		if (theCurrentDrawable == nil)
		{
			//	To "undo" the calls
			//
			//		dispatch_semaphore_wait(itsInflightBufferSemaphore, DISPATCH_TIME_FOREVER);
			//		itsInflightBufferIndex = (itsInflightBufferIndex + 1) % NUM_INFLIGHT_BUFFERS;
			//
			//	we made at the top of this method, we must
			//	decrement itsInflightBufferIndex and signal itsInflightBufferSemaphore.
			//
			//		Note #1:  Signaling the semaphore is important because otherwise,
			//		after 3 dispatch_semaphore_wait() calls without matching calls
			//		to dispatch_semaphore_signal(), the drawing thread (which on iOS
			//		is also the main thread!) would block forever at the next call
			//		to dispatch_semaphore_wait.
			//
			//		Note #2:  Decrementing itsInflightBufferIndex is important, to avoid
			//		any risk of writing to an inflight buffer that the GPU is still using.
			//
			itsInflightBufferIndex = (itsInflightBufferIndex + (NUM_INFLIGHT_BUFFERS - 1)) % NUM_INFLIGHT_BUFFERS;
			dispatch_semaphore_signal(itsInflightBufferSemaphore);
			return;
		}
		
		//	Create a MTLRenderPassDescriptor using theCurrentDrawable.
		theRenderPassDescriptor = [self renderPassDescriptorUsingDrawable:theCurrentDrawable modelData:md];
		
		//	Create theCommandBuffer.
		theCommandBuffer = [itsCommandQueue commandBuffer];

		//	Ask theCommandBuffer to signal theInflightBufferSemaphore when it's done rendering this frame,
		//	so we'll know when the next uniform buffer is ready for reuse.
		dispatch_semaphore_t	theInflightBufferSemaphore = itsInflightBufferSemaphore;	//	avoids implicit reference to self
		[theCommandBuffer addCompletedHandler:^(id<MTLCommandBuffer> aCommandBuffer)
		{
			UNUSED_PARAMETER(aCommandBuffer);
			dispatch_semaphore_signal(theInflightBufferSemaphore);
		}];

		//	Let the subclass encode commands to draw the scene,
		//	using the already-prepared inflight data buffers.
		//
		//		Note:  theRenderPassDescriptor uses MTLLoadActionClear, so the subclass's
		//		encodeCommandsToCommandBuffer:withRenderPassDescriptor:inflightDataBuffers:modelData:
		//		should use theRenderPassDescriptor for a single MTLRenderCommandEncoder only.
		//		An app like KaleidoPaint that requires multiple MTLRenderCommandEncoders
		//		will need to modify theRenderPassDescriptor to use MTLLoadActionLoad instead.
		//
		[self encodeCommandsToCommandBuffer: theCommandBuffer
				   withRenderPassDescriptor: theRenderPassDescriptor
						inflightDataBuffers: theInflightDataBuffers
								  modelData: md];
		
		[theCommandBuffer presentDrawable:theCurrentDrawable];
		[theCommandBuffer commit];
		
		//	KaleidoPaint may need to copy RLE-encoded flood-fill masks
		//	from its scratch buffer to invididual buffers,
		//	which it can allocate only *after* theCommandBuffer has
		//	completed and the required buffer sizes are known.
		[self didCommitCommandBuffer:theCommandBuffer modelData:md];

		//	The GPU now has sole ownership of theCurrentDrawable.
		theCurrentDrawable = nil;	//	unnecessary to explicitly set this to nil of course,
									//		but makes the point emphatically clear
	}
}

- (NSDictionary<NSString *, id> *)prepareInflightDataBuffersAtIndex:(unsigned int)anInflightBufferIndex modelData:(ModelData *)md
{
	UNUSED_PARAMETER(anInflightBufferIndex);
	UNUSED_PARAMETER(md);
	
	//	Each app-specific subclass will override this method.
	return nil;
}

- (NSDictionary<NSString *, id> *)prepareInflightDataBuffersForOffscreenRenderingAtSize:(CGSize)anImageSize modelData:(ModelData *)md
{
	//	Each app-specific subclass will override this method.

	UNUSED_PARAMETER(anImageSize);
	UNUSED_PARAMETER(md);

	return nil;
}

- (MTLRenderPassDescriptor *)renderPassDescriptorUsingDrawable:(id<CAMetalDrawable>)aDrawable modelData:(ModelData *)md
{
	id<MTLTexture>								theColorBuffer;
	MTLRenderPassDescriptor						*theRenderPassDescriptor;
	MTLRenderPassColorAttachmentDescriptor		*theColorAttachmentDescriptor;
	MTLRenderPassDepthAttachmentDescriptor		*theDepthAttachmentDescriptor;
	MTLRenderPassStencilAttachmentDescriptor	*theStencilAttachmentDescriptor;
	MTLTextureDescriptor						*theMultisampleTextureDescriptor,
												*theDepthTextureDescriptor,
												*theStencilTextureDescriptor;


	theColorBuffer = [aDrawable texture];

	theRenderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];
	
	theColorAttachmentDescriptor = [theRenderPassDescriptor colorAttachments][0];
	if ([self wantsClearWithModelData:md])
	{
		[theColorAttachmentDescriptor setClearColor:[self adjustedClearColorWithModelData:md]];	//	opaque for best performance
		[theColorAttachmentDescriptor setLoadAction:MTLLoadActionClear];
	}
	else
	{
		[theColorAttachmentDescriptor setLoadAction:MTLLoadActionDontCare];
	}

	if (itsMultisamplingFlag)
	{
		if (itsMultisampleBuffer == nil
		 || [itsMultisampleBuffer  width] != [theColorBuffer width ]
		 || [itsMultisampleBuffer height] != [theColorBuffer height])
		//	could also check [itsMultisampleBuffer sampleCount] if relevant
		{
			theMultisampleTextureDescriptor = [MTLTextureDescriptor
				texture2DDescriptorWithPixelFormat:	itsColorPixelFormat
											 width:	[theColorBuffer width]
											height:	[theColorBuffer height]
										 mipmapped:	NO];
			[theMultisampleTextureDescriptor setTextureType:MTLTextureType2DMultisample];
			[theMultisampleTextureDescriptor setSampleCount:METAL_MULTISAMPLING_NUM_SAMPLES];	//	must match value in pipeline state
			[theMultisampleTextureDescriptor setUsage:MTLTextureUsageRenderTarget];
#if TARGET_CPU_ARM64
			[theMultisampleTextureDescriptor setStorageMode:MTLStorageModeMemoryless];
#else
			[theMultisampleTextureDescriptor setStorageMode:MTLStorageModePrivate];
#endif
				

			itsMultisampleBuffer = [itsDevice newTextureWithDescriptor:theMultisampleTextureDescriptor];
		}

		[theColorAttachmentDescriptor setTexture:itsMultisampleBuffer];
		[theColorAttachmentDescriptor setResolveTexture:theColorBuffer];
		[theColorAttachmentDescriptor setStoreAction:MTLStoreActionMultisampleResolve];
	}
	else	//	! itsMultisamplingFlag
	{
		[theColorAttachmentDescriptor setTexture:theColorBuffer];
		[theColorAttachmentDescriptor setStoreAction:MTLStoreActionStore];
	}
	
	if (itsDepthBufferFlag)
	{
		if (itsDepthBuffer == nil
		 || [itsDepthBuffer  width] != [theColorBuffer width ]
		 || [itsDepthBuffer height] != [theColorBuffer height])
		//	could also check [itsDepthBuffer sampleCount] if relevant
		{
			theDepthTextureDescriptor = [MTLTextureDescriptor
				texture2DDescriptorWithPixelFormat:	MTLPixelFormatDepth32Float
											 width:	[theColorBuffer width]
											height:	[theColorBuffer height]
										 mipmapped:	NO];
			if (itsMultisamplingFlag)
			{
				[theDepthTextureDescriptor setTextureType:MTLTextureType2DMultisample];
				[theDepthTextureDescriptor setSampleCount:METAL_MULTISAMPLING_NUM_SAMPLES];
			}
			else
			{
				[theDepthTextureDescriptor setTextureType:MTLTextureType2D];
				[theDepthTextureDescriptor setSampleCount:1];
			}
			[theDepthTextureDescriptor setUsage:MTLTextureUsageRenderTarget];
#if TARGET_CPU_ARM64
			[theDepthTextureDescriptor setStorageMode:MTLStorageModeMemoryless];
#else
			[theDepthTextureDescriptor setStorageMode:MTLStorageModePrivate];
#endif

			itsDepthBuffer = [itsDevice newTextureWithDescriptor:theDepthTextureDescriptor];
		}
		
		theDepthAttachmentDescriptor = [theRenderPassDescriptor depthAttachment];
		[theDepthAttachmentDescriptor setTexture:itsDepthBuffer];
		[theDepthAttachmentDescriptor setClearDepth:1.0];
		[theDepthAttachmentDescriptor setLoadAction:MTLLoadActionClear];
		[theDepthAttachmentDescriptor setStoreAction:MTLStoreActionDontCare];
	}
	
	if (itsStencilBufferFlag)
	{
		if (itsStencilBuffer == nil
		 || [itsStencilBuffer  width] != [theColorBuffer width ]
		 || [itsStencilBuffer height] != [theColorBuffer height])
		//	could also check [itsStencilBuffer sampleCount] if relevant
		{
			theStencilTextureDescriptor = [MTLTextureDescriptor
				texture2DDescriptorWithPixelFormat:	MTLPixelFormatStencil8
											 width:	[theColorBuffer width]
											height:	[theColorBuffer height]
										 mipmapped:	NO];
			if (itsMultisamplingFlag)
			{
				[theStencilTextureDescriptor setTextureType:MTLTextureType2DMultisample];
				[theStencilTextureDescriptor setSampleCount:METAL_MULTISAMPLING_NUM_SAMPLES];
			}
			else
			{
				[theStencilTextureDescriptor setTextureType:MTLTextureType2D];
				[theStencilTextureDescriptor setSampleCount:1];
			}
			[theStencilTextureDescriptor setUsage:MTLTextureUsageRenderTarget];
#if TARGET_CPU_ARM64
			[theStencilTextureDescriptor setStorageMode:MTLStorageModeMemoryless];
#else
			[theStencilTextureDescriptor setStorageMode:MTLStorageModePrivate];
#endif

			itsStencilBuffer = [itsDevice newTextureWithDescriptor:theStencilTextureDescriptor];
		}
		
		theStencilAttachmentDescriptor = [theRenderPassDescriptor stencilAttachment];
		[theStencilAttachmentDescriptor setTexture:itsStencilBuffer];
		[theStencilAttachmentDescriptor setClearStencil:0];
		[theStencilAttachmentDescriptor setLoadAction:MTLLoadActionClear];
		[theStencilAttachmentDescriptor setStoreAction:MTLStoreActionDontCare];
	}
	
	return theRenderPassDescriptor;
}

- (bool)wantsClearWithModelData:(ModelData *)md
{
	//	Each app-specific subclass will override this method.

	UNUSED_PARAMETER(md);

	return false;
}

- (MTLClearColor)adjustedClearColorWithModelData:(ModelData *)md
{
	ColorP3Linear	theClearColorAsP3Linear;
	
	//	The clear color gets used only if -wantsClearWithModelData: returns true.

	//	Let the subclass specify a clear color
	//	in linear Display P3 coordinates.
	//	Like all ColorP3Linear's, the result
	//	will already have pre-multiplied alpha.
	//
	theClearColorAsP3Linear = [self clearColorWithModelData:md];

	//	In principle we should get the same color
	//	on iOS, MacCatalyst and macOS, even though
	//	the frame buffer pixel formats vary.

#if TARGET_OS_IOS

	double	theP3LinearColor[3] = (double [3]){
									theClearColorAsP3Linear.r,
									theClearColorAsP3Linear.g,
									theClearColorAsP3Linear.b},
			theAlpha = theClearColorAsP3Linear.a,
			theXRsRGBLinearColor[3];

	ConvertDisplayP3LinearToXRsRGBLinear(theP3LinearColor, theXRsRGBLinearColor);
	
	//	On iOS our frame buffer uses one of the pixel formats
	//
	//		MTLPixelFormatBGRA10_XR_sRGB
	//		MTLPixelFormatBGR10_XR_sRGB
	//		MTLPixelFormatBGRA8Unorm_sRGB
	//
	//	The _sRGB suffix means that the frame buffer will
	//	automatically gamma-encode the linear values we provide here.
	//	For example, if we pass the linear values
	//
	//		(0.00, 0.50, 1.00, 1.00)
	//
	//	the buffer will encode them to
	//
	//		(0.00, 0.73, 1.00, 1.00)
	//

	//	On MacCatalyst our frame buffer
	//	uses the floating-point pixel format
	//
	//		MTLPixelFormatRGBA16Float
	//
	//	The comment preceding "itsColorPixelFormat = MTLPixelFormatRGBA16Float"
	//	says hows the gamma-encoding somehow happens in spite
	//	of this not being an _sRGB pixel format.  So even
	//	on MacCatalyst we should pass linear values here.

	//	linear extended sRGB
	return MTLClearColorMake(
				theXRsRGBLinearColor[0],
				theXRsRGBLinearColor[1],
				theXRsRGBLinearColor[2],
				theAlpha);

#endif // TARGET_OS_IOS

#if TARGET_OS_OSX

	//	On macOS our frame buffer uses the pixel format
	//
	//		MTLPixelFormatBGRA8Unorm_sRGB
	//
	//	so it will automatically gamma-encode
	//	the P3 color components that we pass to it.
	
	return MTLClearColorMake(
				theClearColorAsP3Linear.r,
				theClearColorAsP3Linear.g,
				theClearColorAsP3Linear.b,
				theClearColorAsP3Linear.a);

#endif // TARGET_OS_OSX

//	For testing purposes only:
//
//		if ([itsDevice isLowPower])
//			return MTLClearColorMake(0.25, 0.75, 0.25, 1.00);	//	green
//		else
//			return MTLClearColorMake(0.75, 0.75, 0.25, 1.00);	//	yellow
//
}

- (ColorP3Linear)clearColorWithModelData:(ModelData *)md
{
	//	Each app-specific subclass will override this method.
	
	//	The clear color gets used only if -wantsClearWithModelData: returns true.

	UNUSED_PARAMETER(md);

	return (ColorP3Linear){0.0, 0.0, 0.0, 0.0};	//	fully transparent background
}

- (void)encodeCommandsToCommandBuffer:(id<MTLCommandBuffer>)aCommandBuffer
	withRenderPassDescriptor:(MTLRenderPassDescriptor *)aRenderPassDescriptor
	inflightDataBuffers:(NSDictionary<NSString *, id> *)someInflightDataBuffers
	modelData:(ModelData *)md
{
	UNUSED_PARAMETER(aCommandBuffer);
	UNUSED_PARAMETER(aRenderPassDescriptor);
	UNUSED_PARAMETER(someInflightDataBuffers);
	UNUSED_PARAMETER(md);

	//	Each app-specific subclass will override this method.
}

- (void)didCommitCommandBuffer:(id<MTLCommandBuffer>)aCommandBuffer
					 modelData:(ModelData *)md
{
	UNUSED_PARAMETER(md);

	//	Each app-specific subclass may override this method if desired.
	//	In practice, only KaleidoPaint does so.
}


#pragma mark -
#pragma mark export

- (CGImageRef)newOffscreenImageWithSize: (CGSize)aPreferredImageSizePx	//	in pixels, not points
							  modelData: (ModelData *)md
{
	CGSize									theImageSizePx;
	unsigned int							theWidthPx,
											theHeightPx;
	NSDictionary<NSString *, id>			*theInflightDataBuffers;	//	app-specific collection of buffers
	MTLRenderPassDescriptor					*theRenderPassDescriptor;
	id<MTLCommandBuffer>					theCommandBuffer;
	MTLRenderPassColorAttachmentDescriptor	*theColorAttachmentDescriptor;
	id<MTLTexture>							theColorBuffer;
	CGColorSpaceRef							theWorkingColorSpace,
											theOutputColorSpace;
	CIFormat								theCIPixelFormat;
	NSDictionary<CIContextOption, id>		*theCIContextOptions	= nil;
	CIContext								*theCIContext			= nil;
	CIImage									*theCIImage				= nil,
											*theFlippedCIImage		= nil;
	CGRect									theRect;
	CGImageRef								theCGImage				= NULL;


	//	Clamp aPreferredImageSizePx to the largest dimensions the GPU supports.
	theImageSizePx = [self clampToMaxFramebufferSize:aPreferredImageSizePx];
	
	//	Convert dimensions from floating point to integers.
	theWidthPx	= (unsigned int) theImageSizePx.width;
	theHeightPx	= (unsigned int) theImageSizePx.height;

	//	Just to be safe...
	if (theWidthPx == 0 || theHeightPx == 0)
		return NULL;

	//	Let the subclass prepare all per-frame data buffers.
	theInflightDataBuffers =
		[self prepareInflightDataBuffersForOffscreenRenderingAtSize:(CGSize){theWidthPx, theHeightPx} modelData:md];
	
	//	Create theRenderPassDescriptor.
	theRenderPassDescriptor = CreateRenderTarget(
								itsDevice,
								itsColorPixelFormat,
								itsDepthBufferFlag   ? MTLPixelFormatDepth32Float : MTLPixelFormatInvalid,
								itsStencilBufferFlag ? MTLPixelFormatStencil8     : MTLPixelFormatInvalid,
								theWidthPx,
								theHeightPx,
								itsMultisamplingFlag,
								[self adjustedClearColorWithModelData:md]);
	
	//	Create theCommandBuffer.
	theCommandBuffer = [itsCommandQueue commandBuffer];
	
	//	Encode the commands needed to draw the scene.
	[self encodeCommandsToCommandBuffer: theCommandBuffer
			   withRenderPassDescriptor: theRenderPassDescriptor
					inflightDataBuffers: theInflightDataBuffers
							  modelData: md];
	
	//	Draw the scene.
	[theCommandBuffer commit];
	[theCommandBuffer waitUntilCompleted];	//	This blocks!

	//	Copy the color buffer to a CGImage.
	
	theColorAttachmentDescriptor = theRenderPassDescriptor.colorAttachments[0];
	if (itsMultisamplingFlag)
		theColorBuffer = theColorAttachmentDescriptor.resolveTexture;
	else
		theColorBuffer = theColorAttachmentDescriptor.texture;

#if (TARGET_OS_IOS)	//	including TARGET_OS_MACCATALYST
	//	theColorBuffer is a MTLTexture created with a pixel format
	//
	//		MTLPixelFormatBGR10_XR_sRGB		(iDevice, opaque background)
	//		MTLPixelFormatBGRA10_XR_sRGB	(iDevice, transparent background)
	//		MTLPixelFormatRGBA16Float		(simulator or catalyst)
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
	theWorkingColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearSRGB);
#endif
#if (TARGET_OS_OSX)	//	excluding TARGET_OS_MACCATALYST
	//	On macOS, theWorkingColorSpace needs to be linear P3, not gamma-encoded P3.
	theWorkingColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearDisplayP3);
#endif

	theOutputColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceDisplayP3);

	//	Use a half-precision (16-bit) floating-point pixel format,
	//	to accommodate values below 0.0 and above 1.0,
	//	as extended sRGB coordinates require.
	//
	theCIPixelFormat = kCIFormatRGBAh;
	theCIContextOptions	=
						@{
							kCIContextWorkingColorSpace	: (__bridge id)theWorkingColorSpace,
							kCIContextWorkingFormat		: @(theCIPixelFormat)
						};
	theCIContext		= [CIContext contextWithMTLDevice: itsDevice
												  options: theCIContextOptions];
	if (theCIContext == nil)
		goto CleanUpNewOffscreenImageWithSize;

	theCIImage = [CIImage imageWithMTLTexture:theColorBuffer options:nil];
	if (theCIImage == nil)
		goto CleanUpNewOffscreenImageWithSize;
	
	theFlippedCIImage = [theCIImage imageByApplyingOrientation:kCGImagePropertyOrientationDownMirrored];
	if (theFlippedCIImage == nil)
		goto CleanUpNewOffscreenImageWithSize;

	theRect = CGRectMake(0.0, 0.0, theWidthPx, theHeightPx);
	theCGImage = [theCIContext createCGImage: theFlippedCIImage
									fromRect: theRect
									  format: theCIPixelFormat
								  colorSpace: theOutputColorSpace];

CleanUpNewOffscreenImageWithSize:

	CGColorSpaceRelease(theWorkingColorSpace);
	CGColorSpaceRelease(theOutputColorSpace);

	return theCGImage;
}

- (CGSize)clampToMaxFramebufferSize:(CGSize)aPreferredImageSizePx
{
	unsigned int	theMaxFramebufferSizePx;
	CGSize			theClampedImageSizePx;

	theMaxFramebufferSizePx = [self maxFramebufferSize];
	
	theClampedImageSizePx = aPreferredImageSizePx;

	if (theClampedImageSizePx.width > (CGFloat)theMaxFramebufferSizePx)
	{
		theClampedImageSizePx.height	= floor( theClampedImageSizePx.height
											* ((CGFloat)theMaxFramebufferSizePx / theClampedImageSizePx.width )
											+ 0.5);
		theClampedImageSizePx.width		= (CGFloat)theMaxFramebufferSizePx;
	}

	if (theClampedImageSizePx.height > (CGFloat)theMaxFramebufferSizePx)
	{
		theClampedImageSizePx.width		= floor( theClampedImageSizePx.width
											* ((CGFloat)theMaxFramebufferSizePx / theClampedImageSizePx.height)
											+ 0.5);
		theClampedImageSizePx.height	= (CGFloat)theMaxFramebufferSizePx;
	}
	
	//	Just to be safe...
	if (theClampedImageSizePx.width  < 0.0)
		theClampedImageSizePx.width  = 0.0;
	if (theClampedImageSizePx.height < 0.0)
		theClampedImageSizePx.height = 0.0;
	
	return theClampedImageSizePx;
}

- (unsigned int)maxFramebufferSize
{
	return GetMaxFramebufferSizeOnDevice(itsDevice);
}


#pragma mark -
#pragma mark textures

- (id<MTLTexture>)makeRGBATextureOfColor:(ColorP3Linear)aColor		//	premultiplied alpha
									size:(NSUInteger)aSize			//	power of two
{
	return [self makeRGBATextureOfColor:aColor width:aSize height:aSize];
}

- (id<MTLTexture>)makeRGBATextureOfColor:(ColorP3Linear)aColor		//	premultiplied alpha
								   width:(NSUInteger)aWidth			//	power of two
								  height:(NSUInteger)aHeight		//	power of two
{
	return [self makeRGBATextureOfColor:aColor
								  width:aWidth
								 height:aHeight
					   wideColorDesired:true];
}

- (id<MTLTexture>)makeRGBATextureOfColor:(ColorP3Linear)aColor		//	premultiplied alpha
								   width:(NSUInteger)aWidth			//	power of two
								  height:(NSUInteger)aHeight		//	power of two
						wideColorDesired:(bool)aWideColorTextureIsDesired
{
#if TARGET_OS_IOS
	double							theLinearDisplayP3Color[3],
									theLinearXRsRGBColor[3];
#endif
	simd_half4						theColor;
	NSUInteger						theThreadExecutionWidth;
	MTLTextureDescriptor			*theDescriptor;
	id<MTLTexture>					theTexture;
	NSUInteger						theThreadgroupWidth,
									theThreadgroupHeight;
	id<MTLCommandBuffer>			theCommandBuffer;
	id<MTLComputeCommandEncoder>	theComputeEncoder;

#if TARGET_OS_IOS
	//	On iOS, all rendering takes in place in extended-range linear sRGB coordinates.
	theLinearDisplayP3Color[0] = aColor.r;
	theLinearDisplayP3Color[1] = aColor.g;
	theLinearDisplayP3Color[2] = aColor.b;
	ConvertDisplayP3LinearToXRsRGBLinear(theLinearDisplayP3Color, theLinearXRsRGBColor);
	theColor	= (simd_half4)
				{
					theLinearXRsRGBColor[0],
					theLinearXRsRGBColor[1],
					theLinearXRsRGBColor[2],
					aColor.a
				};
#else
	//	On macOS, all Geometry Games rendering takes place in linear Display P3.
	theColor = (simd_half4) {aColor.r, aColor.g, aColor.b, aColor.a};
#endif

	//	If the host doesn't support non-uniform threadgroup sizes,
	//	then to support our workaround we'll increase the texture width
	//	as necessary, to ensure that it's a multiple of the thread execution width.
	theThreadExecutionWidth = [itsSolidColorPipelineState threadExecutionWidth];
	if ( ! itsNonuniformThreadGroupSizesAreAvailable )
	{
		if (aWidth % theThreadExecutionWidth != 0)
		{
			aWidth = ( (aWidth / theThreadExecutionWidth) + 1 ) * theThreadExecutionWidth;
		}
	}

	//	Note:  The texture format MTLPixelFormatRGBA16Float
	//	works in all cases, on all platforms.  In some cases
	//	we could get by with a 32-bit format instead, but
	//	for now I'd rather keep things simple.
	theDescriptor = [MTLTextureDescriptor
						texture2DDescriptorWithPixelFormat:	MTLPixelFormatRGBA16Float
												width:		aWidth
												height:		aHeight
												mipmapped:	YES];
	[theDescriptor setUsage:(MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite)];
	[theDescriptor setStorageMode:MTLStorageModePrivate];
	theTexture = [itsDevice newTextureWithDescriptor:theDescriptor];

	theCommandBuffer = [itsCommandQueue commandBuffer];

	theComputeEncoder = [theCommandBuffer computeCommandEncoder];
	[theComputeEncoder setLabel:@"solid color texture"];
	[theComputeEncoder setComputePipelineState:itsSolidColorPipelineState];
	[theComputeEncoder setTexture:theTexture atIndex:GeometryGamesTextureIndexCF];
	[theComputeEncoder setBytes:&theColor length:sizeof(simd_half4) atIndex:GeometryGamesBufferIndexCFMiscA];

	if (itsNonuniformThreadGroupSizesAreAvailable)
	{
		//	Dispatch one thread per pixel, using the first strategy
		//	described in Apple's article
		//
		//		https://developer.apple.com/documentation/metal/calculating_threadgroup_and_grid_sizes
		//
		//	There's no reason theThreadgroupWidth must equal the threadExecutionWidth,
		//	but it's a convenient choice.
		//
		theThreadgroupWidth  = [itsSolidColorPipelineState threadExecutionWidth];			//	hardware-dependent constant (typically 32)
		theThreadgroupHeight = [itsSolidColorPipelineState maxTotalThreadsPerThreadgroup]	//	varies according to program resource needs
							 / theThreadgroupWidth;
		
		[theComputeEncoder dispatchThreads:	MTLSizeMake(aWidth, aHeight, 1)
					 threadsPerThreadgroup:	MTLSizeMake(theThreadgroupWidth, theThreadgroupHeight, 1)];
	}
	else
	{
		//	Legacy method:
		//
		//	Use the second strategy described in Apple's article cited above.
		//
		//	We've already increased aWidth as needed to ensure
		//	that aWidth is a multiple of the thread execution width.
		//	Thus by letting theThreadgroupHeight be 1, we guarantee
		//	that no threadgroup will extend beyond the bounds of the image.
		//	Therefore the compute function needn't include any "defensive code"
		//	to check for out-of-bounds pixel coordinates.
		//
		theThreadgroupWidth  = theThreadExecutionWidth;	//	hardware-dependent constant (typically 32)
		theThreadgroupHeight = 1;

		[theComputeEncoder dispatchThreadgroups: MTLSizeMake(
													aWidth  / theThreadgroupWidth,
													aHeight / theThreadgroupHeight,
													1)
						  threadsPerThreadgroup: MTLSizeMake(theThreadgroupWidth, theThreadgroupHeight, 1)];
	}
	
	[theComputeEncoder endEncoding];

	[self generateMipmapsForTexture:theTexture commandBuffer:theCommandBuffer];

	[theCommandBuffer commit];

	return theTexture;
}

- (id<MTLTexture>)createGreyscaleTextureWithString:(Char16 *)aString
		width:(unsigned int)aWidthPx height:(unsigned int)aHeightPx
		fontName:(const Char16 *)aFontName fontSize:(unsigned int)aFontSize fontDescent:(unsigned int)aFontDescent
		centered:(bool)aCenteringFlag margin:(unsigned int)aMargin
{
	CGImageRef		theImage	= NULL;
	id<MTLTexture>	theTexture	= nil;

	//	Power-of-two texture sizes make mipmapping easy and effective.
	GEOMETRY_GAMES_ASSERT(
		IsPowerOfTwo(aWidthPx) && IsPowerOfTwo(aHeightPx),
		"Non power-of-two texture size requested");

	//	Create the desired mask as a CGImage.
	theImage = CreateGreyscaleMaskWithString(	aString, aWidthPx, aHeightPx,
												aFontName, aFontSize, aFontDescent,
												aCenteringFlag, aMargin, NULL);

	//	Convert theImage to a MTLTexture.
	if (theImage != NULL)
		theTexture = [self createGreyscaleTextureWithCGImage:theImage width:aWidthPx height:aHeightPx];
	else
		theTexture = [self makeRGBATextureOfColor:(ColorP3Linear){0.0, 0.0, 0.0, 1.0} width:1 height:1];
		
	//	Free theImage.
	CGImageRelease(theImage);
	
	return theTexture;
}

- (id<MTLTexture>)createGreyscaleTextureWithCGImage:(CGImageRef)aCGImage
		width:(unsigned int)aWidth height:(unsigned int)aHeight
{
	MTKTextureLoader							*theTextureLoader;
	NSDictionary<MTKTextureLoaderOption, id>	*theTextureLoaderOptions;
	NSError										*theError;
	id<MTLTexture>								theTexture;

	//	Convert aCGImage to a MTLTexture.
	//
	//		Note #1
	//			We must flip aCGImage to match Core Graphics' conventions to our own.
	//
	//		Note #2
	//			The MTKTextureLoader offers MTKTextureLoaderOptionGenerateMipmaps
	//			only for color-renderable textures, so we create
	//			a greyscale mask (using MTLPixelFormatR8Unorm) instead of
	//			an alpha mask (MTLPixelFormatA8Unorm).  More generally,
	//			MTLPixelFormatR8Unorm is a "shader-writable" pixel format,
	//			while MTLPixelFormatA8Unorm is not.
	//
	theTextureLoader = [[MTKTextureLoader alloc] initWithDevice:itsDevice];
	theTextureLoaderOptions =
	@{
		MTKTextureLoaderOptionTextureUsage			:	@(MTLTextureUsageShaderRead),
		MTKTextureLoaderOptionTextureStorageMode	:	@(MTLStorageModePrivate),
		MTKTextureLoaderOptionOrigin				:	MTKTextureLoaderOriginBottomLeft,
		MTKTextureLoaderOptionAllocateMipmaps		:	@(YES),
		MTKTextureLoaderOptionGenerateMipmaps		:	@(YES)
	};
	theTexture = [theTextureLoader newTextureWithCGImage: aCGImage
												 options: theTextureLoaderOptions
												   error: &theError];


	return theTexture;
}

- (void)generateMipmapsForTexture:(id<MTLTexture>)aTexture
			commandBuffer:(id<MTLCommandBuffer>)aCommandBuffer
{
	id<MTLBlitCommandEncoder>	theBlitEncoder;

	if ([aTexture mipmapLevelCount] > 1)
	{
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
		theBlitEncoder = [aCommandBuffer blitCommandEncoder];
		[theBlitEncoder setLabel:@"make mipmap levels"];
		[theBlitEncoder generateMipmapsForTexture:aTexture];
		[theBlitEncoder endEncoding];
	}
}

- (void)roughenTexture:(id<MTLTexture>)aTexture
		roughingFactor:(double)aRoughingFactor	//	0.0 = no roughing; 1.0 = maximal roughing
{
	__fp16							theRoughingFactor;
	id<MTLCommandBuffer>			theCommandBuffer;
	id<MTLComputeCommandEncoder>	theComputeEncoder;
	NSUInteger						theMipmapWidth,
									theMipmapHeight;
	ushort							theNumMipmapLevels,
									theMipmapLevel;
	NSUInteger						theThreadgroupWidth,
									theThreadgroupHeight;

	if (aRoughingFactor <= 0.0	//	Even though 0.0 is a legal roughing value, it would have no effect.
	 || aRoughingFactor >  1.0)
	{
		return;
	}

	if ( ! itsNonuniformThreadGroupSizesAreAvailable )
	{
		//	In the current versions of the various Geometry Games apps,
		//	the textures to be roughened all have power-of-two dimensions,
		//	so the "legacy code" below will get uniform threadgroups
		//	which exactly tile aTexture.
		//
		//	Nevertheless, just in case this code someday receives
		//	a texture with non power-of-two dimensions, let's be prepared
		//	to return immediately if we're running on an older device
		//	that doesn't support non-uniform thread group sizes.
		//
		if ( ! IsPowerOfTwo((unsigned int)[aTexture width])
		  || ! IsPowerOfTwo((unsigned int)[aTexture height])
		  || ! IsPowerOfTwo((unsigned int)[itsTextureRoughingPipelineState threadExecutionWidth]))
		{
			return;
		}
	}
		
	//	GeometryGamesComputeFunctionRoughenTexture()
	//	requires a read_write texture.
	//
	//		Note:  On macOS, Intel GPUs don't support writing
	//		to mipmap levels at all, but Apple Silicon GPUs work fine.
	//
	if ( [itsDevice readWriteTextureSupport] < MTLReadWriteTextureTier2 )
		return;

	theRoughingFactor = (__fp16) aRoughingFactor;

	theCommandBuffer = [itsCommandQueue commandBuffer];
	
	theComputeEncoder = [theCommandBuffer computeCommandEncoder];
	[theComputeEncoder setLabel:@"roughen texture"];
	[theComputeEncoder setComputePipelineState:itsTextureRoughingPipelineState];
	[theComputeEncoder setTexture:aTexture atIndex:GeometryGamesTextureIndexCF];
	[theComputeEncoder setBytes:&theRoughingFactor length:sizeof(__fp16) atIndex:GeometryGamesBufferIndexCFMiscB];

	theMipmapWidth	= [aTexture width ];
	theMipmapHeight	= [aTexture height];
	
	theNumMipmapLevels = [aTexture mipmapLevelCount];
	for (theMipmapLevel = 0; theMipmapLevel < theNumMipmapLevels; theMipmapLevel++)
	{
		[theComputeEncoder setBytes:&theMipmapLevel length:sizeof(ushort) atIndex:GeometryGamesBufferIndexCFMiscA];

		if (itsNonuniformThreadGroupSizesAreAvailable)
		{
			theThreadgroupWidth  = [itsTextureRoughingPipelineState threadExecutionWidth];			//	hardware-dependent constant (typically 32)
			if (theThreadgroupWidth > theMipmapWidth)
				theThreadgroupWidth = theMipmapWidth;
			theThreadgroupHeight = [itsTextureRoughingPipelineState maxTotalThreadsPerThreadgroup]	//	varies according to program resource needs
								 / theThreadgroupWidth;
			if (theThreadgroupHeight > theMipmapHeight)
				theThreadgroupHeight = theMipmapHeight;
		
			[theComputeEncoder dispatchThreads:	MTLSizeMake(theMipmapWidth, theMipmapHeight, 1)
						 threadsPerThreadgroup:	MTLSizeMake(theThreadgroupWidth, theThreadgroupHeight, 1)];
		}
		else
		{
			//	Legacy method

			//	At the beginning of this method we checked that
			//	the image width, the image height and the threadExecutionWidth
			//	are all powers of two, so if theMipmapWidth is greater than
			//	theThreadgroupWidth, it will be an exact integer multiple of it.
			theThreadgroupWidth  = [itsTextureRoughingPipelineState threadExecutionWidth];			//	hardware-dependent constant (typically 32)
			if (theThreadgroupWidth > theMipmapWidth)
				theThreadgroupWidth = theMipmapWidth;
			
			//	The maxTotalThreadsPerThreadgroup isn't known until runtime,
			//	and might not be a power of two.  So let's choose
			//	a threadgroup height that doesn't depend on it.
			//	The following choice might be less than maximally efficient,
			//	but at least it's completely safe.  In any case,
			//	this legacy method will get retired in a few years.
			//
			//	Again, we've ensured that all these quantities are powers of two,
			//	so the thread groups will tile aTexture exactly.
			theThreadgroupHeight = [itsTextureRoughingPipelineState threadExecutionWidth]
								 / theThreadgroupWidth;
			if (theThreadgroupHeight > theMipmapHeight)
				theThreadgroupHeight = theMipmapHeight;
		
			[theComputeEncoder dispatchThreadgroups: MTLSizeMake(
														theMipmapWidth  / theThreadgroupWidth,
														theMipmapHeight / theThreadgroupHeight,
														1)
							  threadsPerThreadgroup: MTLSizeMake(theThreadgroupWidth, theThreadgroupHeight, 1)];
		}
		
		//	Here in roughenTexture we expect power-of-two size textures,
		//	so each mipmap level will be exactly half the size of the preceding one.
		//	If we instead had a non power-of-two size texture,
		//	we'd face the question of whether to round up or down
		//	when halving the size.  The OpenGL documentation
		//
		//		https://www.khronos.org/registry/OpenGL/extensions/ARB/ARB_texture_non_power_of_two.txt
		//		(search for ”"floor" convention”)
		//
		//	says that OpenGL adopts the round-down convention (which it calls
		//	the "floor" convention) mainly because that's the convention
		//	that Direct3D uses, and it wants to be consistent.
		//	I've tried and failed to find a statement of what convention
		//	Metal uses, but it's hard to imagine that with Direct3D and OpenGL
		//	already using the round-down convention, that Metal's designers
		//	would have seen any benefit to doing it differently.
		//	Moreover, a few experiments show Metal to be consistent
		//	with the round-down convention.  For example, when a MTLDevice's
		//	newTextureWithDescriptor creates 7×7 texture, it provides
		//	three mipmap levels, which is consistent with the sequence
		//	7×7, 3×3, 1×1 that the round-down convention requires,
		//	and not with the sequence 7×7, 4×4, 2×2, 1×1 that
		//	the round-up convention would require.  In any case,
		//	by rounding down we ensure that we'll never overwrite
		//	the buffer, even if we someday got passed a texture
		//	whose mipmap sizes had been chosen by rounding up.
		//
		if (theMipmapWidth  > 1)
			theMipmapWidth  /= 2;
		if (theMipmapHeight > 1)
			theMipmapHeight /= 2;
	}
	
	[theComputeEncoder endEncoding];

	[theCommandBuffer commit];
}


@end


//	Create a render target for offscreen rendering,
//	typically in response to a Copy Image or Save Image command.
static MTLRenderPassDescriptor *CreateRenderTarget(
	id<MTLDevice>	aDevice,
	MTLPixelFormat	aColorPixelFormat,
	MTLPixelFormat	aDepthPixelFormat,	//	= MTLPixelFormatInvalid if no depth buffer is needed
	MTLPixelFormat	aStencilPixelFormat,//	= MTLPixelFormatInvalid if no stencil buffer is needed
	NSUInteger		aWidthPx,			//	in pixels, not points
	NSUInteger		aHeightPx,			//	in pixels, not points
	bool			aMultisamplingFlag,
	MTLClearColor	aClearColor)
{
	MTLTextureDescriptor						*theColorBufferDescriptor;
	id<MTLTexture>								theColorBuffer,
												theMultisampleBuffer,
												theDepthBuffer,
												theStencilBuffer;
	MTLRenderPassDescriptor						*theRenderPassDescriptor;
	MTLRenderPassColorAttachmentDescriptor		*theColorAttachmentDescriptor;
	MTLRenderPassDepthAttachmentDescriptor		*theDepthAttachmentDescriptor;
	MTLRenderPassStencilAttachmentDescriptor	*theStencilAttachmentDescriptor;
	MTLTextureDescriptor						*theMultisampleTextureDescriptor,
												*theDepthTextureDescriptor,
												*theStencilTextureDescriptor;

	//	Create theColorBuffer.
	theColorBufferDescriptor = [MTLTextureDescriptor
		texture2DDescriptorWithPixelFormat:	aColorPixelFormat
									 width:	aWidthPx
									height:	aHeightPx
								 mipmapped:	NO];
	[theColorBufferDescriptor setTextureType:MTLTextureType2D];
		//	Be sure to include MTLTextureUsageShaderRead
		//	so Core Image can read the pixels afterwards.
	[theColorBufferDescriptor setUsage:(MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead)];
	[theColorBufferDescriptor setStorageMode:MTLStorageModePrivate];
	theColorBuffer = [aDevice newTextureWithDescriptor:theColorBufferDescriptor];

	theRenderPassDescriptor = [MTLRenderPassDescriptor renderPassDescriptor];

	theColorAttachmentDescriptor = [theRenderPassDescriptor colorAttachments][0];
	[theColorAttachmentDescriptor setClearColor:aClearColor];
	[theColorAttachmentDescriptor setLoadAction:MTLLoadActionClear];	//	always MTLLoadActionClear for robustness

	if (aMultisamplingFlag)
	{
		theMultisampleTextureDescriptor = [MTLTextureDescriptor
			texture2DDescriptorWithPixelFormat:	aColorPixelFormat
										 width:	aWidthPx
										height:	aHeightPx
									 mipmapped:	NO];
		[theMultisampleTextureDescriptor setTextureType:MTLTextureType2DMultisample];
		[theMultisampleTextureDescriptor setSampleCount:METAL_MULTISAMPLING_NUM_SAMPLES];	//	must match value in pipeline state
		[theMultisampleTextureDescriptor setUsage:MTLTextureUsageRenderTarget];
#if TARGET_CPU_ARM64
		[theMultisampleTextureDescriptor setStorageMode:MTLStorageModeMemoryless];
#else
		[theMultisampleTextureDescriptor setStorageMode:MTLStorageModePrivate];
#endif
		
		theMultisampleBuffer = [aDevice newTextureWithDescriptor:theMultisampleTextureDescriptor];

		[theColorAttachmentDescriptor setTexture:theMultisampleBuffer];
		[theColorAttachmentDescriptor setResolveTexture:theColorBuffer];
		[theColorAttachmentDescriptor setStoreAction:MTLStoreActionMultisampleResolve];
	}
	else	//	! aMultisamplingFlag
	{
		[theColorAttachmentDescriptor setTexture:theColorBuffer];
		[theColorAttachmentDescriptor setStoreAction:MTLStoreActionStore];
	}
	
	if (aDepthPixelFormat != MTLPixelFormatInvalid)	//	Caller wants depth buffer?
	{
		theDepthTextureDescriptor = [MTLTextureDescriptor
			texture2DDescriptorWithPixelFormat:	MTLPixelFormatDepth32Float
										 width:	[theColorBuffer width]
										height:	[theColorBuffer height]
									 mipmapped:	NO];
		if (aMultisamplingFlag)
		{
			[theDepthTextureDescriptor setTextureType:MTLTextureType2DMultisample];
			[theDepthTextureDescriptor setSampleCount:METAL_MULTISAMPLING_NUM_SAMPLES];
		}
		else
		{
			[theDepthTextureDescriptor setTextureType:MTLTextureType2D];
			[theDepthTextureDescriptor setSampleCount:1];
		}
		[theDepthTextureDescriptor setUsage:MTLTextureUsageRenderTarget];
#if TARGET_CPU_ARM64
		[theDepthTextureDescriptor setStorageMode:MTLStorageModeMemoryless];
#else
		[theDepthTextureDescriptor setStorageMode:MTLStorageModePrivate];
#endif

		theDepthBuffer = [aDevice newTextureWithDescriptor:theDepthTextureDescriptor];
		
		theDepthAttachmentDescriptor = [theRenderPassDescriptor depthAttachment];
		[theDepthAttachmentDescriptor setTexture:theDepthBuffer];
		[theDepthAttachmentDescriptor setClearDepth:1.0];
		[theDepthAttachmentDescriptor setLoadAction:MTLLoadActionClear];
		[theDepthAttachmentDescriptor setStoreAction:MTLStoreActionDontCare];
	}
	
	if (aStencilPixelFormat != MTLPixelFormatInvalid)	//	Caller wants stencil buffer?
	{
		theStencilTextureDescriptor = [MTLTextureDescriptor
			texture2DDescriptorWithPixelFormat:	aStencilPixelFormat
										 width:	[theColorBuffer width]
										height:	[theColorBuffer height]
									 mipmapped:	NO];
		if (aMultisamplingFlag)
		{
			[theStencilTextureDescriptor setTextureType:MTLTextureType2DMultisample];
			[theStencilTextureDescriptor setSampleCount:METAL_MULTISAMPLING_NUM_SAMPLES];
		}
		else
		{
			[theStencilTextureDescriptor setTextureType:MTLTextureType2D];
			[theStencilTextureDescriptor setSampleCount:1];
		}
		[theStencilTextureDescriptor setUsage:MTLTextureUsageRenderTarget];
#if TARGET_CPU_ARM64
		[theStencilTextureDescriptor setStorageMode:MTLStorageModeMemoryless];
#else
		[theStencilTextureDescriptor setStorageMode:MTLStorageModePrivate];
#endif

		theStencilBuffer = [aDevice newTextureWithDescriptor:theStencilTextureDescriptor];
		
		theStencilAttachmentDescriptor = [theRenderPassDescriptor stencilAttachment];
		[theStencilAttachmentDescriptor setTexture:theStencilBuffer];
		[theStencilAttachmentDescriptor setClearStencil:0];
		[theStencilAttachmentDescriptor setLoadAction:MTLLoadActionClear];
		[theStencilAttachmentDescriptor setStoreAction:MTLStoreActionDontCare];
	}
	
	return theRenderPassDescriptor;
}
