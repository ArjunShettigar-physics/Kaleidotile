//	KaleidoTileGPUFunctions.metal
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

#include <metal_stdlib>
using namespace metal;
#include "KaleidoTileGPUDefinitions.h"	//	Include this *after* "using namespace metal"
										//		if you might need to use uint32_t
										//		in "KaleidoTileGPUDefinitions.h"


//	Note on data types:  The talk WWDC 2016 session #606, whose transcript is available at
//
//		https://asciiwwdc.com/2016/sessions/606
//
//	says
//
//		the most important thing to remember when you're choosing data types
//		is that A8 and later GPUs have 16-bit register units, which means that
//		for example if you're using a 32-bit data type, that's twice the register space,
//		twice the bandwidth, potentially twice the power and so-forth,
//		it's just twice as much stuff.
//
//		So, accordingly you will save registers, you will get faster performance,
//		you'll get lower power by using smaller data types.
//
//		Use half and short for arithmetic wherever you can.
//
//		Energy wise, half is cheaper than float.
//
//		And float is cheaper than integer, but even among integers, smaller integers are cheaper than bigger ones.
//
//		And the most effective thing you can do to save registers is
//		to use half for texture reads and interpolates because most of the time
//		you really do not need float for these.
//		And note I do not mean your texture formats.
//		I mean the data types you're using to store the results of a texture sample or an interpolate.
//
//		And one aspect of A8 in later GPUs that is fairly convenient and
//		makes using smaller data types easier than on some other GPUs is
//		that data type conversions are typically free, even between float and half,
//		which means that you don't have to worry, oh am I introducing too many conversions
//		in this by trying to use half here?
//

constant bool	gTexture				[[ function_constant(0) ]];	//	8-bit boolean
constant bool	gSolidColor = ! gTexture;
constant bool	gDirectionalLighting	[[ function_constant(1) ]];	//	8-bit boolean
constant bool	gSpecularReflection		[[ function_constant(2) ]];	//	8-bit boolean
constant bool	gDimming				[[ function_constant(3) ]];	//	8-bit boolean


#pragma mark -
#pragma mark Polyhedron faces

struct VertexInput
{
	float3	pos [[ attribute(VertexAttributePosition)											]];
	half3	nor [[ attribute(VertexAttributeNormal),	function_constant(gDirectionalLighting)	]];
	float2	tex [[ attribute(VertexAttributeTexCoords),	function_constant(gTexture)				]];
};

//	If we want to use more than one custom clip-plane,
//	we must define separate VertexOutput and FragmentInput structures,
//	because the former must export a clip_distance vector,
//	which the latter cannot accept.  Without custom-planes,
//	it would be fine to use the VertexOutput structure
//	directly as the fragment function's input.
//
struct VertexOutput
{
	//	Even though the page
	//
	//		https://docs.unity3d.com/Manual/SL-ShaderPerformance.html
	//
	//	in nominally about the Unity game engine, it offers
	//	some general-purpose advice regarding floating-point precision:
	//
	//		For world space positions and texture coordinates,
	//			use float precision.
	//
	//		For everything else [colors etc.], start with half precision.
	//			Increase only if necessary.
	//
	//		...
	//
	//		All modern desktop GPUs will always compute everything
	//			in full float precision …
	//
	//		Mobile GPUs have actual half precision support.
	//			This is usually faster, and
	//			uses less power to do calculations.
	//
	//	And by the way, the WWDC 2016 #606, whose transcript is available at
	//
	//		https://asciiwwdc.com/2016/sessions/606
	//
	//	mentions that
	//
	//		And one aspect of A8 in later GPUs that is fairly convenient
	//		and makes using smaller data types easier than on some other GPUs
	//		is that data type conversions are typically free, even between float and half,
	//		which means that you don't have to worry, oh am I introducing
	//		too many conversions in this by trying to use half here?
	//
	float4	position		[[ position													]];
	half	diffuseFactor	[[ user(diffuse),   function_constant(gDirectionalLighting)	]];
	half	specularFactor	[[ user(specular),  function_constant(gDirectionalLighting)	]];
	float2	texCoords		[[ user(texcoords), function_constant(gTexture)				]];
};
struct FragmentInput
{
	half	diffuseFactor	[[ user(diffuse),   function_constant(gDirectionalLighting)	]];
	half	specularFactor	[[ user(specular),  function_constant(gDirectionalLighting)	]];
	float2	texCoords		[[ user(texcoords), function_constant(gTexture)				]];
};


vertex VertexOutput KaleidoTileVertexFunction(
	VertexInput						in					[[ stage_in								]],
	constant KaleidoTileUniformData	&uniforms			[[ buffer(BufferIndexVFUniforms)		]],
	const device float3x3			*trianglePlacements	[[ buffer(BufferIndexVFInstanceData)	]],
	ushort							iid					[[ instance_id							]]	)
{
	VertexOutput	out;
	float3			theTransformedPosition;
	
	theTransformedPosition = trianglePlacements[iid] * in.pos;
	out.position = uniforms.itsViewProjectionMatrix * float4(theTransformedPosition, 1.0);

	if (gDirectionalLighting) {
	
		half3	theTransformedNormal;
		
		//	Directional lighting is used only for spherical geometry (traditional polyhedra),
		//	in which case the normal covector transforms as if it were an ordinary vector.
		theTransformedNormal = half3x3(trianglePlacements[iid]) * in.nor;
		out.diffuseFactor
			= 0.25h  +  0.75h * max(0.0h, dot(uniforms.itsDiffuseEvaluator, theTransformedNormal) );
		out.specularFactor
			= (gSpecularReflection ?
				0.25h * pow(max(0.0h, dot(uniforms.itsSpecularEvaluator, theTransformedNormal) ), 64.0h) :
				0.0);
	}

	if (gTexture) {
		out.texCoords = in.tex;
	}

	return out;
}

fragment half4 KaleidoTileFragmentFunction(
	FragmentInput in		[[ stage_in														]],
	constant half4 &color	[[ buffer(BufferIndexFFColor),   function_constant(gSolidColor)	]], // premultiplied linear extended-range sRGB
	texture2d<half> texture	[[ texture(TextureIndexPrimary), function_constant(gTexture)	]],
	sampler textureSampler	[[ sampler(SamplerIndexPrimary), function_constant(gTexture)	]]	)
{
	half4	tmpRawColor,
			tmpShadedColor,
			tmpFinalColor;

	if (gTexture)
	{
		tmpRawColor = texture.sample(textureSampler, in.texCoords);
	}
	else	//	gSolidColor
	{
		tmpRawColor = color;
	}

	if (gDirectionalLighting)
	{
		tmpShadedColor = half4(in.diffuseFactor,  in.diffuseFactor,  in.diffuseFactor,  1.0h             ) * tmpRawColor
					   + half4(in.specularFactor, in.specularFactor, in.specularFactor, in.specularFactor) * tmpRawColor.a;
	}
	else
	{
		tmpShadedColor = tmpRawColor;
	}
	
	if (gDimming)
	{
		tmpFinalColor = half4(
			0.5 * tmpShadedColor.r,
			0.5 * tmpShadedColor.g,
			0.5 * tmpShadedColor.b,
			tmpShadedColor.a );
	}
	else
	{
		tmpFinalColor = tmpShadedColor;
	}

	return tmpFinalColor;
}


#pragma mark -
#pragma mark Background texture

struct BackgroundVertexInput
{
	float2	pos [[ attribute(VertexAttributePosition)								]];
	float2	tex [[ attribute(VertexAttributeTexCoords),	function_constant(gTexture)	]];
};

struct BackgroundVertexOutput
{
	float4	position	[[ position						]];
	float2	texCoords	[[ function_constant(gTexture)	]];
};


vertex BackgroundVertexOutput KaleidoTileBackgroundVertexFunction(
	BackgroundVertexInput	in	[[ stage_in ]])
{
	BackgroundVertexOutput	out;

	out.position	= float4(in.pos, 0.5, 1.0);
	out.texCoords	= in.tex;

	return out;
}

fragment half4 KaleidoTileBackgroundFragmentFunction(
	BackgroundVertexOutput	in	[[ stage_in														]],
	constant half4 &color		[[ buffer(BufferIndexFFColor),   function_constant(gSolidColor)	]],
		// premultiplied linear extended-range sRGB
	texture2d<half>	texture		[[ texture(TextureIndexPrimary), function_constant(gTexture)	]],
	sampler	textureSampler		[[ sampler(SamplerIndexPrimary), function_constant(gTexture)	]])
{
	half4	tmpColor;

	if (gTexture)
	{
		tmpColor = texture.sample(textureSampler, in.texCoords);
	}
	else	//	gSolidColor
	{
		tmpColor = color;
	}

	return tmpColor;
}


#pragma mark -
#pragma mark Triple point

struct TriplePointVertexInput
{
	float2	pos [[ attribute(VertexAttributePosition)	]];
	float2	tex [[ attribute(VertexAttributeTexCoords)	]];
};

struct TriplePointVertexOutput
{
	float4	position	[[ position ]];
	float2	texCoords;
};


vertex TriplePointVertexOutput KaleidoTileTriplePointVertexFunction(
	TriplePointVertexInput	in	[[ stage_in ]])
{
	TriplePointVertexOutput	out;

	out.position	= float4(in.pos, 0.5, 1.0);
	out.texCoords	= in.tex;

	return out;
}

fragment half4 KaleidoTileTriplePointFragmentFunction(
	TriplePointVertexOutput	in	[[ stage_in ]] )
{
	half	r0sq,
			r1sq,
			r2sq,
			r3sq,
			theRadiusSquared,
			theAlpha,
			s,
			t;
	half4	theInnerColor,
			theOuterColor,
			theColor;

	//	Transition radii
	//
	//	The transition from white to black happends between
	//	radius 0.7 and radius 0.8.  The transition from
	//	opaque to transparent happens between 0.9 and 1.0.
	//
	//	These fairly gentle transitions give better results
	//	at small pixel sizes.
	//
	r0sq = 0.7h * 0.7h;	//	square of inner radius of brightness transition
	r1sq = 0.8h * 0.8h;	//	square of outer radius of brightness transition
	r2sq = 0.9h * 0.9h;	//	square of inner radius of opacity transition
	r3sq = 1.0h * 1.0h;	//	square of outer radius of opacity transition

	theRadiusSquared	= (half)in.texCoords[0] * (half)in.texCoords[0]
						+ (half)in.texCoords[1] * (half)in.texCoords[1];
	
	theAlpha			= clamp(
							(r3sq - theRadiusSquared) / (r3sq - r2sq),
							0.0h,
							1.0h);
	
	s					= clamp(
							(r1sq - theRadiusSquared) / (r1sq - r0sq),
							0.0h,
							1.0h);
	t					= 1.0h - s;

	theInnerColor = half4(1.0h, 1.0h, 1.0h, 1.0h);	//	half4(0.0h, 0.0h, 1.0h, 1.0h);
	theOuterColor = half4(0.0h, 0.0h, 0.0h, 1.0h);	//	half4(0.0h, 1.0h, 0.0h, 1.0h);

	theColor = s * theInnerColor
			 + t * theOuterColor;

	return theColor * theAlpha;	//	premultiplied alpha
}
