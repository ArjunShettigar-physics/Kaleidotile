//	KaleidoTileGPUDefinitions.h
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

#ifndef KaleidoTileGPUDefinitions_h
#define KaleidoTileGPUDefinitions_h

#include <simd/simd.h>

enum
{
	VertexAttributePosition		= 0,
	VertexAttributeNormal		= 1,
	VertexAttributeTexCoords	= 2
};

//	Buffer indices for vertex functions ("VF")
enum
{
	BufferIndexVFVertexAttributes	= 0,
	BufferIndexVFUniforms			= 1,
	BufferIndexVFInstanceData		= 2
};

//	Buffer indices for fragment functions ("FF")
enum
{
	BufferIndexFFColor	= 0
};


//	A GPU fragment function typically uses
//	only one texture and one texture sampler at a time.
//	Additional TextureIndexes would be needed
//	only if the fragment function wanted
//	to combine two or more textures at render time.
enum
{
	TextureIndexPrimary	= 0
};
enum
{
	SamplerIndexPrimary	= 0
};


typedef struct
{
	simd_float4x4	itsViewProjectionMatrix;
	simd_half3		itsDiffuseEvaluator,
					itsSpecularEvaluator;
					
} KaleidoTileUniformData;

#endif	//	KaleidoTileGPUDefinitions_h
