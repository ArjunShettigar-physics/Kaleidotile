//  GeometryGamesGPUFunctions.metal
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#include <metal_stdlib>
using namespace metal;
#include "GeometryGamesGPUDefinitions.h"


#pragma mark -
#pragma mark Solid color compute function

kernel void GeometryGamesComputeFunctionSolidColor(
	texture2d<half, access::write>	aTexture	[[ texture(GeometryGamesTextureIndexCF)		]],
	constant half4					&aColor		[[ buffer(GeometryGamesBufferIndexCFMiscA)	]],
	ushort2							aGridID		[[ thread_position_in_grid					]] )
{
	aTexture.write(aColor, aGridID);
}


#pragma mark -
#pragma mark Texture roughening compute function

half RandomFloat16(ushort2 aGridID);

kernel void GeometryGamesComputeFunctionRoughenTexture(
	texture2d<half, access::read_write>	aTexture			[[ texture(GeometryGamesTextureIndexCF)		]],
	constant ushort						&aMipmapLevel		[[ buffer(GeometryGamesBufferIndexCFMiscA)	]],
	constant half						&aRoughingFactor	[[ buffer(GeometryGamesBufferIndexCFMiscB)	]],
	ushort2								aGridID				[[ thread_position_in_grid					]] )
{
	half4	tmpColorIn,
			tmpColorOut;
	half	tmpDarkeningFactor;

	//	Note that GeometryGamesComputeFunctionRoughenTexture()
	//	generates the same pattern each time we call it,
	//	which is fine for our purposes.  If we wanted to get
	//	a different pattern each time, the CPU could pass us
	//	a random constant which we'd pass into RandomFloat
	//	to splice into its initial value of "n".

	tmpColorIn			= aTexture.read(aGridID, aMipmapLevel);
	tmpDarkeningFactor	= 1.0h - aRoughingFactor * RandomFloat16(aGridID);
	tmpColorOut			= tmpColorIn * half4(tmpDarkeningFactor, tmpDarkeningFactor, tmpDarkeningFactor, 1.0h);

	//	The following call would fail on any GPU that doesn't
	//	support read-write access to a texture in the given pixel format.
	//	On macOS, Intel GPUs don't support writing to mipmap levels at all,
	//	but Apple Silicon GPUs work fine.
	//
	aTexture.write(tmpColorOut, aGridID, aMipmapLevel);
}

half RandomFloat16(
	ushort2	aGridID)
{
	uint32_t	n;
	
	//	Use an Xorshift algorithm, as illustrated at
	//
	//		https://en.wikipedia.org/wiki/Xorshift
	//
	//	Note that we don't try to maintain any sort of state,
	//	we just take aGridID as given and scramble it up
	//	in hopes of getting a sufficiently "random" 32-bit unsigned integer.
	
	n = ( ((uint32_t)aGridID[0] << 16) | (uint32_t)aGridID[1] );
	
	n ^= (n << 13);
	n ^= (n >>  7);
	n ^= (n << 17);
	n ^= (n >>  2);	//	adding these last two lines gives the pattern
	n ^= (n <<  5);	//		a more woven look (instead of a stripy look)
	
	//	1/2³² = 2.3283064365386962890625E-10
	return half(n * 2.3283064365386962890625e-10);
}
