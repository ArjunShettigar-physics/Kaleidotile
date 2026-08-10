//	GeometryGamesMeshes.h
//
//	© 2023 by Jeff Weeks
//	See TermsOfUse.txt

#pragma once

#include <stdio.h>

extern void	GetUnitSphereMeshSize(unsigned int aRefinementLevel,
				unsigned int *aNumMeshVertices, unsigned int *aNumMeshFacets);
extern void	MakeUnitSphereMesh(unsigned int aRefinementLevel,
				double (*aVertexBuffer)[4], unsigned int aVertexBufferByteCount,
				unsigned int (*aFacetBuffer)[3], unsigned int aFacetBufferByteCount);

extern void	GetUnitCylinderMeshSize(unsigned int aRefinementLevel,
				unsigned int *aNumMeshVertices, unsigned int *aNumMeshFacets);
extern void	MakeUnitCylinderMesh(unsigned int aRefinementLevel,
				double (*aVertexBuffer)[4], unsigned int aVertexBufferByteCount,
				unsigned int (*aFacetBuffer)[3], unsigned int aFacetBufferByteCount);
