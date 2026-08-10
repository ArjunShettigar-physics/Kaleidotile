//	GeometryGamesRenderer.h
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#import "GeometryGames-Common.h"
#import <CoreGraphics/CoreGraphics.h>
#import <CoreImage/CoreImage.h>
#import <Metal/Metal.h>


#define METAL_MULTISAMPLING_NUM_SAMPLES		4	//	4 samples per pixel

//	In practice, CAMetalLayer keeps a set of three framebuffer textures,
//	which makes sense because while the first is being displayed to the user,
//	the GPU can be rendering into the second, and the CPU can be preparing
//	to submit the third.
//
//	Let's use the same number of instances of each per-frame ("in-flight") buffer.
//
#define NUM_INFLIGHT_BUFFERS	3


@class CAMetalLayer;

@interface GeometryGamesRenderer : NSObject
{
	//	These instances variables are visible only to subclasses.
	
	bool						itsMultisamplingFlag,
								itsDepthBufferFlag,
								itsStencilBufferFlag;
//	The renderer shouldn't be storing itsOnscreenNativeSizePx.
//	See comment in GeometryGamesRenderer.m, in initWithLayer.
	CGSize						itsOnscreenNativeSizePx;

	id<MTLDevice>				itsDevice;

	MTLPixelFormat				itsColorPixelFormat;

	//	The reason for making itsCommandQueue visible to subclasses,
	//	rather than keeping it private to the GeometryGamesRenderer itself,
	//	is that functions like SpinGraphicsRenderer's -refreshTilingForGroup:
	//	need to create buffers of storage type MTLResourceStorageModePrivate,
	//	which they populate by blitting from shared-storage buffers.
	//	Using a single MTLCommandQueue accessible to the subclass
	//	insures that all MTLCommandBuffers, whether for blitting or rendering,
	//	get executed in the order in which they are submitted.
	//
	id<MTLCommandQueue>			itsCommandQueue;
	
	//	Once all targeted devices support non-uniform threadgroup sizes
	//	we can remove this flag.  In the meantime, it's convenient
	//	to test for non-uniform threadgroup size availability
	//	once and for all, at launch.
	bool						itsNonuniformThreadGroupSizesAreAvailable;
}

- (id)initWithLayer:(CAMetalLayer *)aLayer device:(id<MTLDevice>)aDevice
	multisampling:(bool)aMultisamplingFlag depthBuffer:(bool)aDepthBufferFlag stencilBuffer:(bool)aStencilBufferFlag
	mayExportWithTransparentBackground:(bool)aMayExportWithTransparentBackgroundFlag;

- (MTLPixelFormat)colorPixelFormat;
- (CGColorSpaceRef)colorSpaceRef;

- (void)setUpGraphicsWithModelData:(ModelData *)md;
- (void)shutDownGraphicsWithModelData:(ModelData *)md;

- (void)viewSizeOrScaleFactorDidChange:(CGSize)aNativeSizePx modelData:(ModelData *)md;

- (void)drawViewWithModelData:(ModelData *)md;
- (NSDictionary<NSString *, id> *)prepareInflightDataBuffersAtIndex:(unsigned int)anInflightBufferIndex modelData:(ModelData *)md;
- (NSDictionary<NSString *, id> *)prepareInflightDataBuffersForOffscreenRenderingAtSize:(CGSize)anImageSize modelData:(ModelData *)md;
- (bool)wantsClearWithModelData:(ModelData *)md;
- (ColorP3Linear)clearColorWithModelData:(ModelData *)md;
- (void)encodeCommandsToCommandBuffer:(id<MTLCommandBuffer>)aCommandBuffer
		withRenderPassDescriptor:(MTLRenderPassDescriptor *)aRenderPassDescriptor
		inflightDataBuffers:(NSDictionary<NSString *, id> *)someInflightDataBuffers
		modelData:(ModelData *)md;
- (void)didCommitCommandBuffer:(id<MTLCommandBuffer>)aCommandBuffer modelData:(ModelData *)md;

- (CGImageRef)newOffscreenImageWithSize:(CGSize)aPreferredImageSizePx
				modelData:(ModelData *)md;
- (CGSize)clampToMaxFramebufferSize:(CGSize)aPreferredImageSizePx;
- (unsigned int)maxFramebufferSize;

- (id<MTLTexture>)makeRGBATextureOfColor:(ColorP3Linear)aColor size:(NSUInteger)aSize;
- (id<MTLTexture>)makeRGBATextureOfColor:(ColorP3Linear)aColor width:(NSUInteger)aWidth height:(NSUInteger)aHeight;
- (id<MTLTexture>)makeRGBATextureOfColor:(ColorP3Linear)aColor width:(NSUInteger)aWidth height:(NSUInteger)aHeight
					wideColorDesired:(bool)aWideColorTextureIsDesired;
- (id<MTLTexture>)createGreyscaleTextureWithString:(Char16 *)aString
		width:(unsigned int)aWidthPx height:(unsigned int)aHeightPx
		fontName:(const Char16 *)aFontName fontSize:(unsigned int)aFontSize fontDescent:(unsigned int)aFontDescent
		centered:(bool)aCenteringFlag margin:(unsigned int)aMargin;
- (id<MTLTexture>)createGreyscaleTextureWithCGImage:(CGImageRef)aCGImage width:(unsigned int)aWidth height:(unsigned int)aHeight;

- (void)generateMipmapsForTexture:(id<MTLTexture>)aTexture commandBuffer:(id<MTLCommandBuffer>)aCommandBuffer;
- (void)roughenTexture:(id<MTLTexture>)aTexture roughingFactor:(double)aRoughingFactor;

@end
