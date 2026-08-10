//	GeometryGamesUtilities-SIMD.h
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#pragma once

#import <simd/simd.h>

extern simd_float3x3	ConvertMatrix33ToSIMD(const double aMatrix[3][3]);

extern simd_float4x4	ConvertMatrix44ToSIMD(const double aMatrix[4][4]);
extern simd_float4x4	ConvertMatrix44fToSIMD(const float aMatrix[4][4]);

extern simd_float2		ConvertVector2toSIMD(const double aVector[2]);
extern simd_float2		ConvertVector2ftoSIMD(const float aVector[2]);

extern simd_float3		ConvertVector3toSIMD(const double aVector[3]);
extern simd_float3		ConvertVector3ftoSIMD(const float aVector[3]);

extern simd_float4		ConvertVector4toSIMD(const double aVector[4]);
extern simd_half4		ConvertVector4toSIMDHalf(const double aVector[4]);
extern simd_float4		ConvertVector4ftoSIMD(const float aVector[4]);
extern simd_half4		ConvertVector4ftoSIMDHalf(const float aVector[4]);
extern simd_half4		ConvertLinearDisplayP3ToSIMDHalf(double r, double g, double b, double a);

extern float			EuclideanDeterminantSIMD(simd_float4x4 *m);
