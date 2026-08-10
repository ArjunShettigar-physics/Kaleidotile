//	GeometryGamesMesh.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import Metal


//	MeshIndexType must always be UInt16 or UInt32,
//	because those are the sizes the GPU supports.
//	GeometryGamesMesh.init() checks that this requirement is satisfied.
typealias UInt16or32 = UnsignedInteger & FixedWidthInteger

class GeometryGamesMesh<MeshVertexType: BitwiseCopyable, MeshIndexType: UInt16or32> {
										
	let itsVertices: [MeshVertexType]
	let itsIndices: [MeshIndexType]
	
	init(
		vertices: [MeshVertexType],
		indices: [MeshIndexType])
	{
		precondition(	MeshIndexType.self == UInt16.self
					 || MeshIndexType.self == UInt32.self,
			"MeshIndexType must be UInt16 or UInt32")
		
		itsVertices = vertices
		itsIndices = indices
	}
	
	func makeBuffers(
		device: MTLDevice
	) -> GeometryGamesMeshBuffers<MeshVertexType, MeshIndexType> {
	
		guard let theVertexBuffer = device.makeBuffer(
			bytes: itsVertices,
			length: itsVertices.count * MemoryLayout<MeshVertexType>.stride,
			options: [MTLResourceOptions.storageModeShared]
		) else {
			fatalError("Couldn't make theVertexBuffer in makeBuffers()")
		}
		
		guard let theIndexBuffer = device.makeBuffer(
			bytes: itsIndices,
			length: itsIndices.count * MemoryLayout<MeshIndexType>.stride,
			options: [MTLResourceOptions.storageModeShared]
		) else {
			fatalError("Couldn't make theIndexBuffer in makeBuffers()")
		}
		
		let theMeshBuffers = GeometryGamesMeshBuffers<MeshVertexType, MeshIndexType>(
			vertexCount: itsVertices.count,
			indexCount: itsIndices.count,
			vertexBuffer: theVertexBuffer,
			indexBuffer: theIndexBuffer,
			mtlIndexType: itsMTLIndexType)
		
		return theMeshBuffers
	}
	
	var itsMTLIndexType: MTLIndexType {
	
		let theMTLIndexType: MTLIndexType
		if MeshIndexType.self == UInt16.self {
			theMTLIndexType = MTLIndexType.uint16
		}
		else
		if MeshIndexType.self == UInt32.self {
			theMTLIndexType = MTLIndexType.uint32
		}
		else {
			fatalError("MeshIndexType must be UInt16 or UInt32")
		}
	
		return theMTLIndexType
	}
}

class GeometryGamesMeshBuffers<MeshVertexType: BitwiseCopyable, MeshIndexType: UInt16or32> {

	let vertexCount: Int
	let indexCount: Int
	
	let vertexBuffer: MTLBuffer
	let indexBuffer: MTLBuffer
	
	let mtlIndexType: MTLIndexType
	
	init(
		vertexCount: Int,
		indexCount: Int,
		vertexBuffer: MTLBuffer,
		indexBuffer: MTLBuffer,
		mtlIndexType: MTLIndexType
	) {
		self.vertexCount = vertexCount
		self.indexCount = indexCount
		self.vertexBuffer = vertexBuffer
		self.indexBuffer = indexBuffer
		self.mtlIndexType = mtlIndexType
	}
}

struct GeometryGamesPlainVertex {

	var pos: SIMD3<Float32>	//	position (x,y,z)
	var nor: SIMD3<Float16>	//	unit-length normal vector (nx, ny, nz)
}


// MARK: -
// MARK: Unit sphere

//	What polyhedron should unitSphereMesh() start with?
enum SphereBase {

	//	An icosahedron works best for most purposes
	//	because it distributes the curvature more evenly.
	case icosahedron
	
	//	For 4D Maze and the Torus Games' 3D mazes we start
	//	with an octahedron instead, because its intersections
	//	with the coordinate planes are regular 2ⁿ-gons,
	//	which mate perfectly with cylindrical tubes
	//	running parallel to the x, y and z axes.
	//
	//		Note:  The octahedron-based mesh also
	//		offers the possibility of drawing only
	//		a half, a quarter or an eighth of the sphere.
	//
	case octahedron
}

func unitSphereMesh<MeshIndexType: UInt16or32>(
	baseShape: SphereBase,
	refinementLevel: Int
) -> GeometryGamesMesh<GeometryGamesPlainVertex, MeshIndexType> {

	//	Starting with an icosahedron or octahedron, we call
	//	subdivideUnitRadiusPolyhedronMesh() several times
	//	to subdivide the mesh, each time replacing each old facet
	//	with four new ones:
	//
	//		  /\		//
	//		 /__\		//
	//		/_\/_\		//
	//
	//	So if we start with an icosahedron, the refinementLevel
	//	determines the number of faces as follows:
	//
	//		0	  20 faces
	//		1	  80 faces
	//		2	 320 faces
	//		3	1280 faces
	//		etc.
	//
	//	If we instead start with an octahedron,
	//	the number of faces will be
	//
	//		0	   8 faces
	//		1	  32 faces
	//		2	 128 faces
	//		3	 512 faces
	//		etc.
	//

	//	Design note:  In apps like Crystal Flight that use
	//	a level-of-detail approach, this code is "inefficient"
	//	in that for each successive refinement level
	//	it redundantly re-computes all previous levels.
	//	But we don't mind the inefficiency, because this code
	//	gets called only when the user creates the meshes.
	//	The simplicity of the code is more important
	//	than trivial runtime optimizations.

	var theMesh: GeometryGamesMesh<GeometryGamesPlainVertex, MeshIndexType>
	switch baseShape {
	
	case .icosahedron:
		theMesh = unitIcosahedronMesh()
		
	case .octahedron:
		theMesh = unitOctahedronMesh()
	}

	for _ in 0 ..< refinementLevel {
		theMesh = subdivideUnitRadiusPolyhedronMesh(theMesh)
	}
	
	return theMesh
}

private func unitIcosahedronMesh<MeshIndexType: UInt16or32>(
) -> GeometryGamesMesh<GeometryGamesPlainVertex, MeshIndexType> {

	//	Vertices

	//	The icosahedron's (unnormalized) vertices sit at
	//
	//			( 0, ±1, ±φ)
	//			(±1, ±φ,  0)
	//			(±φ,  0, ±1)
	//
	//	where φ is the golden ratio.  The golden ratio is a root
	//	of the irreducible polynomial φ² - φ - 1,
	//	with numerical value φ = (1 + √5)/2 ≈ 1.6180339887…

	let φ = 0.5 * (1.0 + sqrt(5.0))
		//	golden ratio
		//	≈ 1.61803398874989484820
	
	let theNormalizationFactor = 1.0 / sqrt(φ*φ + 1.0)
		//	inverse length of unnormalized vertex
		//	 = 1/√(φ² + 1) ≈ 0.52573111211913360603
	
	let a = 1.0 * theNormalizationFactor
	let b =  φ  * theNormalizationFactor

	//	The icosahedron's 12 vertices, normalized to unit length
	let theVertexPositions = [
	
		[ 0.0, -a,  -b  ],
		[ 0.0, +a,  -b  ],
		[ 0.0, -a,  +b  ],
		[ 0.0, +a,  +b  ],

		[ -a,  -b,  0.0 ],
		[ +a,  -b,  0.0 ],
		[ -a,  +b,  0.0 ],
		[ +a,  +b,  0.0 ],

		[ -b,  0.0, -a  ],
		[ -b,  0.0, +a  ],
		[ +b,  0.0, -a  ],
		[ +b,  0.0, +a  ]
	]
	
	let theVertices = theVertexPositions.map() { v in
		GeometryGamesPlainVertex(
			pos: SIMD3<Float32>( Float32(v[0]), Float32(v[1]), Float32(v[2]) ),
			nor: SIMD3<Float16>( Float16(v[0]), Float16(v[1]), Float16(v[2]) ) )
	}
		
	//	Facets

	//	The icosahedron's 20 facets
	let theIndices: [MeshIndexType] =
	[
		//	Winding order is clockwise when viewed
		//	from outside the icosahedron in a left-handed coordinate system.

		//	side-based faces

		 0,  8,  1,
		 1, 10,  0,
		 2, 11,  3,
		 3,  9,  2,

		 4,  0,  5,
		 5,  2,  4,
		 6,  3,  7,
		 7,  1,  6,

		 8,  4,  9,
		 9,  6,  8,
		10,  7, 11,
		11,  5, 10,

		//	corner-based faces
		
		 0,  4,  8,
		 2,  9,  4,
		 1,  8,  6,
		 3,  6,  9,
		 0, 10,  5,
		 2,  5, 11,
		 1,  7, 10,
		 3, 11,  7
	]
		
	let theIcosahedronMesh = GeometryGamesMesh<GeometryGamesPlainVertex, MeshIndexType>(
								vertices: theVertices,
								indices: theIndices)
	
	return theIcosahedronMesh
}

private func unitOctahedronMesh<MeshIndexType: UInt16or32>(
) -> GeometryGamesMesh<GeometryGamesPlainVertex, MeshIndexType> {

	//	Vertices

	//	The octahedron's vertices sit at
	//
	//			(±1,  0,  0)
	//			( 0, ±1,  0)
	//			( 0,  0, ±1)
	//
	let theVertexPositions = [
	
		[-1.0,  0.0,  0.0],
		[ 1.0,  0.0,  0.0],
		[ 0.0, -1.0,  0.0],
		[ 0.0,  1.0,  0.0],
		[ 0.0,  0.0, -1.0],
		[ 0.0,  0.0,  1.0]
	]

	let theVertices = theVertexPositions.map() { v in
		GeometryGamesPlainVertex(
			pos: SIMD3<Float32>( Float32(v[0]), Float32(v[1]), Float32(v[2]) ),
			nor: SIMD3<Float16>( Float16(v[0]), Float16(v[1]), Float16(v[2]) ) )
	}
	
	//	Facets

	//	The octahedron's 8 facets
	let theIndices: [MeshIndexType] =
	[
		//	Winding order is clockwise when viewed
		//	from outside the octahedron in a left-handed coordinate system.

		//	The Torus Games' 3D Maze may or may not want to draw only
		//	the exposed parts of each sphere (probably not, to keep the code simple).
		//	In any case, the 4D Maze app should definitely not bother with partial spheres:
		//	with no repeating images the performance penalty is negligible
		//	and drawing only whole spheres keeps the code simple.

		//		If drawing partial spheres,
		//		for the 1/8 sphere at x ≥ 0, y ≥ 0, z ≥ 0,
		//		use only this face (and its subdivisions)
		5, 1, 3,

		//		If drawing partial spheres,
		//		for the 1/4 sphere at x ≥ 0, y ≥ 0,
		//		use the previous face along with this one
		//		(and their subdivisions):
		4, 3, 1,

		//		If drawing partial spheres,
		//		for the 1/2 sphere at x ≥ 0,
		//		use the previous faces along with these ones
		//		(and their subdivisions):
		4, 1, 2,
		5, 2, 1,
		
		//		If drawing partial spheres,
		//		for the full sphere,
		//		use the previous faces along with these ones
		//		(and their subdivisions):
		4, 0, 3,
		4, 2, 0,
		5, 3, 0,
		5, 0, 2
	]
		
	let theOctahedronMesh = GeometryGamesMesh<GeometryGamesPlainVertex, MeshIndexType>(
								vertices: theVertices,
								indices: theIndices)
	
	return theOctahedronMesh
}

private func subdivideUnitRadiusPolyhedronMesh<MeshIndexType: UInt16or32>(
	_ mesh: GeometryGamesMesh<GeometryGamesPlainVertex, MeshIndexType>
) -> GeometryGamesMesh<GeometryGamesPlainVertex, MeshIndexType> {

	let theSrcVertices = mesh.itsVertices
	let theSrcIndices = mesh.itsIndices

	precondition(
		theSrcIndices.count % 3 == 0,
		"The number of source indices must be a multiple of 3")
	
	let theSrcVertexCount = theSrcVertices.count
	let theSrcFacetCount  = theSrcIndices.count / 3


	//	We'll subdivide the mesh, replacing each old facet with four new ones.
	//
	//		  /\		//
	//		 /__\		//
	//		/_\/_\		//
	//
	
	let theSubdivisionFacetCount = 4 * theSrcFacetCount
	
	//	Euler's formula says that for any cell decomposition of a sphere
	//
	//		v - e + f = 2
	//
	//	Our meshes are comprised exclusively of triangles, so
	//
	//		e = 3f/2
	//
	//	Combining those two formulas gives
	//
	//		v = f/2 + 2
	//
	//	The diagram above shows that
	//
	//		subdivisionF = 4 * originalF
	//
	//	so
	//
	//		subdivisionV = subdivisionF/2 + 2
	//					 = (4*originalF)/2 + 2
	//					 = 2*originalF + 2
	//
	let theSubdivisionVertexCount =  2 * theSrcFacetCount  +  2

	//	Allocate arrays for the subdivision.
	
	var theSubdivisionVertices = Array(
			repeating: GeometryGamesPlainVertex(pos: .zero, nor: .zero),
			count: theSubdivisionVertexCount)

	var theSubdivisionIndices = Array(
			repeating: MeshIndexType(0),
			count: 3 * theSubdivisionFacetCount)

	//	Keep a running count of the number of vertices
	//	we've written into theSubdivisionVertices,
	//	so we always know where to write the next one.
	//
	var theVertexCount = 0

	//	First copy the source mesh vertex positions to the destination mesh...
	for i in 0 ..< theSrcVertexCount {
		theSubdivisionVertices[i] = theSrcVertices[i]
	}
	theVertexCount += theSrcVertexCount

	//	...and then create one new vertex on each edge.
	//
	//	Use theNewVertexTable[][] to index them,
	//	so two facets sharing an edge can share the same vertex.
	//
	//	theNewVertexTable[v0][v1] takes the indices v0 and v1 of two old vertices,
	//	and gives the index of the new vertex that sits at the midpoint of the edge
	//	that connects v0 and v1.
	//
	//	The size of theNewVertexTable grows as the square of the number of source vertices.
	//	For modest meshes this won't be a problem.  For larger meshes a fancier algorithm,
	//	with linear rather than quadratic memory demands, could be used.
	//
	//	Initialize all of theNewVertexTable[][]'s entries to
	//
	//		notPresent =MeshIndexType.max ( = 0xFFFF or 0xFFFFFFFF )
	//
	//	to indicate that no new vertices have yet been created.
	//	This seems easier than working with optional values
	//	(which would be of type "MeshIndexType?").
	//
	let notPresent = MeshIndexType.max
	var theNewVertexTable: [ [ MeshIndexType ] ]
		= Array(
			repeating: Array(
					repeating: notPresent,
					count: theSrcVertexCount),
			count: theSrcVertexCount
		)

	//	For each edge in the source mesh, create a new vertex at its midpoint.
	for i in 0 ..< theSrcFacetCount {
		for j in 0 ..< 3 {
		
			let v0 = Int(theSrcIndices[3*i +    j   ])	//	Cast from MeshIndexType to Int
			let v1 = Int(theSrcIndices[3*i + (j+1)%3])
			
			if theNewVertexTable[v0][v1] == notPresent {
			
				precondition(
					theVertexCount < theSubdivisionVertexCount,
					"Internal error #1 in subdivideUnitRadiusPolyhedronMesh()")

				//	The new vertex will sit midway between vertices v0 and v1.
				let theMidpoint
					= normalize(0.5 * (theSubdivisionVertices[v0].pos + theSubdivisionVertices[v1].pos))
					//	normalize() should be safe here, because we'll never pass it a zero vector
				theSubdivisionVertices[theVertexCount].pos = theMidpoint
				theSubdivisionVertices[theVertexCount].nor = SIMD3<Float16>(theMidpoint)

				//	Record the new vertex at [v1][v0] as well as [v0][v1],
				//	so only one new vertex will get created for each edge.
				theNewVertexTable[v0][v1] = MeshIndexType(theVertexCount)
				theNewVertexTable[v1][v0] = MeshIndexType(theVertexCount)

				theVertexCount += 1
			}
		}
	}
	precondition(
		theVertexCount == theSubdivisionVertexCount,
		"Internal error #2 in subdivideUnitRadiusPolyhedronMesh()")

	//	For each facet in the source mesh,
	//	create four smaller facets in the subdivision.
	for i in 0 ..< theSrcFacetCount {
	
		//	Call the old vertices incident to this facet v0, v1 and v2
		let v0 = Int(theSrcIndices[3*i + 0])	//	Cast from MeshIndexType to Int
		let v1 = Int(theSrcIndices[3*i + 1])
		let v2 = Int(theSrcIndices[3*i + 2])

		//	Call the new vertices -- which sit at the midpoints
		//	of the old edges -- vv0, vv1, and vv2.
		//	Each vv_j sits opposite the corresponding v_j .
		let vv0 = theNewVertexTable[v1][v2]
		let vv1 = theNewVertexTable[v2][v0]
		let vv2 = theNewVertexTable[v0][v1]

		//	Create the new facets.

		theSubdivisionIndices[3*(4*i + 0) + 0] = vv0
		theSubdivisionIndices[3*(4*i + 0) + 1] = vv1
		theSubdivisionIndices[3*(4*i + 0) + 2] = vv2

		theSubdivisionIndices[3*(4*i + 1) + 0] = MeshIndexType(v0)
		theSubdivisionIndices[3*(4*i + 1) + 1] = vv2
		theSubdivisionIndices[3*(4*i + 1) + 2] = vv1

		theSubdivisionIndices[3*(4*i + 2) + 0] = MeshIndexType(v1)
		theSubdivisionIndices[3*(4*i + 2) + 1] = vv0
		theSubdivisionIndices[3*(4*i + 2) + 2] = vv2

		theSubdivisionIndices[3*(4*i + 3) + 0] = MeshIndexType(v2)
		theSubdivisionIndices[3*(4*i + 3) + 1] = vv1
		theSubdivisionIndices[3*(4*i + 3) + 2] = vv0
	}

	let theSubdivisionMesh = GeometryGamesMesh<GeometryGamesPlainVertex, MeshIndexType>(
								vertices: theSubdivisionVertices,
								indices: theSubdivisionIndices)

	return theSubdivisionMesh
}


// MARK: -
// MARK: Unit cylinder


enum CylinderStyle {

	//	An antiprism works best for most purposes
	//	because it provides twice as many potential
	//	horizon lines as the user walks around it,
	//	compared to a cylinder with the same number
	//	of facets.
	case antiprism
	
	//	For the 4D Maze and the Torus Games' 3D maze we use
	//	an ordinary prism instead, so that it may mate perfectly
	//	with the octahedron-based spheres that it connects to.
	case prism
}

func unitCylinderMesh<MeshIndexType: UInt16or32>(
	style cylinderStyle: CylinderStyle,
	refinementLevel: Int
) -> GeometryGamesMesh<GeometryGamesPlainVertex, MeshIndexType> {

	//	Construct a mesh that models a cylinder whose cross-section
	//	in the xy plane is a unit circle, and whose ends sit at z = ±1
	
	//	The refinementLevel will be small (typically 4, or at most 5).
	//	Substantially larger values would require a ridiculously large
	//	number of vertices and facets.
	precondition(
		refinementLevel >= 0 && refinementLevel < 16,
		"Unreasonably large (or perhaps negative) refinementLevel")
	
	//	At the coarsest level, triangulate the cylinder as a triangular antiprism,
	//	with 3 vertices at each end and 3 triangles pointing in each direction.
	//	For each successive refinement level, double the numbers of vertices and faces:
	//
	//		level 0		    6 facets (triangular antiprism)
	//		level 1		   12 facets (hexagonal antiprism)
	//		level 2		   24 facets
	//		level 3		   48 facets
	//		...
	//
	let n = (3 << refinementLevel)
	
	//	Note the number of vertices and facets.
	let theVertexCount = 2 * n
	let theFacetCount  = 2 * n

	let Δθ = 2.0 * Double.pi /  Double(theVertexCount)

	let theVertices = (0 ..< theVertexCount).map() { i in
		
		let theNumHalfSteps: Int
		switch cylinderStyle {
		case .antiprism:	theNumHalfSteps = i
		case .prism:		theNumHalfSteps = (i - i%2)	//	(0,1,2,3,4,…) -> (0,0,2,2,4,…)
		}
		let θ = Double(theNumHalfSteps) * Δθ

		let cosθ = cos(θ)
		let sinθ = sin(θ)

		let theVertex = GeometryGamesPlainVertex(
							pos: SIMD3<Float32>(
									Float32(cosθ),
									Float32(sinθ),
									Float32((i%2 == 0) ? -1.0 : +1.0) ),
							nor: SIMD3<Float16>(
									Float16(cosθ),
									Float16(sinθ),
									Float16(0.0) ) )
		
		return theVertex
	}

	//	Let the facets wind clockwise when viewed from the outside
	//	in a left-handed coordinate system.
	//
	//		Note: Swift's type inference system handles
	//		this code a lot more quickly if we define
	//		the indices first as Ints and then convert
	//		them to MeshIndexType afterwards.
	//
	let theIndicesAsInts = ( 0 ..< theFacetCount/2 ).flatMap() { i in
	
		let theFacetPair = [
		
			(2*i + 0) % theVertexCount,
			(2*i + 2) % theVertexCount,
			(2*i + 1) % theVertexCount,

			(2*i + 1) % theVertexCount,
			(2*i + 2) % theVertexCount,
			(2*i + 3) % theVertexCount
		]
		
		return theFacetPair
	}
	let theIndices = theIndicesAsInts.map() { i in MeshIndexType(i) }
	
	
	let theCylinderMesh = GeometryGamesMesh<GeometryGamesPlainVertex, MeshIndexType>(
							vertices: theVertices,
							indices: theIndices)

	return theCylinderMesh
}

