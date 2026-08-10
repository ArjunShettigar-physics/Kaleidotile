//  KaleidoTileMeshMaker.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import Metal


struct KaleidoTileVertexData {

	let pos: SIMD3<Float32>	//	position (x,y,z)
	let nor: SIMD3<Float16>	//	normal vector (nx, ny, nz)
	let tex: SIMD2<Float32>	//	texture coordinates (u,v)
	
	init(p: SIMD3<Float32>, n: SIMD3<Float16>, t: SIMD2<Float32>) {
		pos = p
		nor = n
		tex = t
	}
	
	//	This init() takes a nested set of tuples as its sole argument,
	//	so we can write the contents of a vertex buffer as succinctly as possible.
	init( _ v: (
		_ : (_ : Float32, _ : Float32, _ : Float32),
		_ : (_ : Float16, _ : Float16, _ : Float16),
		_ : (_ : Float32, _ : Float32))
	) {
		pos = SIMD3<Float32>(v.0.0, v.0.1, v.0.2)
		nor = SIMD3<Float16>(v.1.0, v.1.1, v.1.2)
		tex = SIMD2<Float32>(v.2.0, v.2.1)
	}
}

struct KaleidoTileMeshMaker {

	let vertexBufferPool: GeometryGamesBufferPool	//	manages inflight buffers for vertices
	let faceBufferPool: GeometryGamesBufferPool		//	manages inflight buffers for faces

	init(device: MTLDevice) {
	
		//	Create GeometryGamesBufferPools so we can
		//	cycle through a small set of inflight buffers
		//	while the triple point is moving and the mesh
		//	is getting re-made for every frame.
		//
		//	makeMeshes() will ensure the correct buffer sizes.
		
		vertexBufferPool = GeometryGamesBufferPool(
			device: device,
			initialBufferSize: 1 * MemoryLayout<KaleidoTileVertexData>.stride,
			storageMode: .storageModeShared,
			bufferLabel: "Vertex buffer")
		
		faceBufferPool = GeometryGamesBufferPool(
			device: device,
			initialBufferSize: 1 * MemoryLayout<UInt16>.stride,
			storageMode: .storageModeShared,
			bufferLabel: "Face buffer")
	}
	
	func makeMeshes(
		baseTriangle: BaseTriangle,
		tilingStyle: TilingStyle,
		triplePoint: TriplePoint,
		cutAlongMirrorLines: Bool,
		forUseWith commandBuffer: MTLCommandBuffer
	) -> (Int, [MTLBuffer], Int, MTLBuffer)
		//	Returns
		//	(
		//		vertex count = (n+1)²,
		//		array of three vertex buffers,
		//			each containing (n+1)² instances of KaleidoTileVertexData
		//			(the three vertex buffers corresond to the three quads
		//			into which the triple point splits the base triangle),
		//
		//		face buffer index count = 6n²
		//		face buffer containing 6n² indices for 2n² faces,
		//			each index being a UInt16
		//			(the three vertex buffers all share the same face buffer)
		//	)
	{
		//	Coordinate system
		//
		//		x axis points rightward
		//		y axis points upward
		//		z axis points forward
		//
		
		let theMetricV = baseTriangle.geometry.metricForVertical
		let theMetricH = baseTriangle.geometry.metricForHorizontal

		//	Convert the triplePoint from barycentric coordinates
		//	to physical coordinates.
		let theUnscaledTriplePoint = baseTriangle.barycentricBasis * triplePoint
		let theTriplePoint = theMetricV.normalize(theUnscaledTriplePoint)	//	≠ zero

		//	The base triangle's vertices never move, but we must
		//	adjust their lengths to be coplanar with the surrounding
		//	images of the triple point.
		let theScaledVertices = baseTriangle.vertices.map() { unitLengthVertex in
			let theFactor = fabs(theMetricV.innerProduct(theTriplePoint, unitLengthVertex))
			return theFactor * unitLengthVertex
		}

		//	The crossing points lie midway between theTriplePoint
		//	and each of theTriplePoint's reflected images.
		let theCrossingPoints = baseTriangle.generators.map() { generator in
			let theReflectedImage = generator * theTriplePoint
			return 0.5 * (theTriplePoint + theReflectedImage)
		}

		//	How fine a mesh is needed?
		let n = meshSize(
					reflectionGroup: baseTriangle.reflectionGroup,
					tilingStyle: tilingStyle)
		let theVertexCount = (n + 1) * (n + 1)
		vertexBufferPool.ensureSize(theVertexCount * MemoryLayout<KaleidoTileVertexData>.stride)
		
		//	Create the vertices for each of the three meshes,
		//	one mesh for each quad.
		var theVertexBuffers: [MTLBuffer] = []
		for i in 0...2 {	//	which quad

			//	To cut along mirror lines, shrink the base triangle
			//	in the x- and y- (but not the z-) directions
			//	to leave a little gap between its translates.
			let theFactor = (cutAlongMirrorLines ?
								SIMD3<Double>(0.98, 0.98, 1.00) :
								SIMD3<Double>(1.00, 1.00, 1.00) )

			//	Locate the quad corners.
			//	The quad's four corners are indexed like this:
			//
			//		2  3
			//		0  1
			//
			let theCorners = [
				theFactor * theScaledVertices[i],
				theFactor * theCrossingPoints[(i+2)%3],
				theFactor * theCrossingPoints[(i+1)%3],
				theFactor * theTriplePoint
			]

			//	Assign aesthetically pleasing texture coordinates.
			let theCornerTextureCoordinates = chooseTextureCoordinates(
												corners: theCorners,
												metricH: theMetricH)

			//	Allocate theVertexBuffer.
			let theVertexBuffer = vertexBufferPool.get(forUseWith: commandBuffer)
			let theVertices = theVertexBuffer.contents().bindMemory(
												to: KaleidoTileVertexData.self,
												capacity: theVertexCount)

			//	Set the vertices' positions, normals and texture coordinates.
			if n == 1 {	//	use TilingStyle.flat (maybe forced, for (2,2,n) tilings)
			
				//	Create a single flat quad.

				//	Only spherical tilings get directional lighting,
				//	so only they need normal vectors.
				//	For TilingStyle.flat, use a single normal vector
				//	orthogonal to the face.
				//
				let theNormal = (baseTriangle.geometry == .spherical ?
									theMetricV.normalize(baseTriangle.vertices[i]) :
									.zero)
				
				for j in 0...3 {
					theVertices[j] = KaleidoTileVertexData(
						p: SIMD3<Float32>(theCorners[j]),
						n: SIMD3<Float16>(theNormal),
						t: SIMD2<Float32>(theCornerTextureCoordinates[j]))
				}

			} else {	//	use TilingStyle.curved ((2,2,n) tilings have been excluded)

				//	Create a full mesh.
				for j in 0 ... n {
					for k in 0 ... n {
					
						//	SwiftUI's type checker was pretty slow
						//	with the original expressions for thePosition
						//	and theTextureCoordinates, so I split them
						//	into smaller pieces.
						
						let c₀ = Double( (n - j) * (n - k) )
						let c₁ = Double( (n - j) *    k    )
						let c₂ = Double(    j    * (n - k) )
						let c₃ = Double(    j    *    k    )
						
						let cor₀ = c₀ * theCorners[0]
						let cor₁ = c₁ * theCorners[1]
						let cor₂ = c₂ * theCorners[2]
						let cor₃ = c₃ * theCorners[3]
						
						//	For a properly weighted vector we'd need
						//	to divide the sum
						//
						//		cor₀ + cor₁ + cor₂ + cor₃
						//
						//	by n², but because we're going to normalize
						//	the result anyhow, we can skip the division by n².
						//
						let thePosition = theMetricV.normalize(
											cor₀ + cor₁ + cor₂ + cor₃ )

						//	With a spherical curved-style tiling,
						//	the unit-length position vector may
						//	also serve as a normal vector.
						//	Euclidean and hyperbolic tilings use
						//	no directional lighting, and therefore
						//	need no normal vectors.
						//
						let theNormal = (baseTriangle.geometry == .spherical ?
											thePosition : .zero)

						
						let tex₀ = c₀ * theCornerTextureCoordinates[0]
						let tex₁ = c₁ * theCornerTextureCoordinates[1]
						let tex₂ = c₂ * theCornerTextureCoordinates[2]
						let tex₃ = c₃ * theCornerTextureCoordinates[3]
						
						let theUnnormalizedTexCoordSum = tex₀ + tex₁ + tex₂ + tex₃

						let theTextureCoordinates = theUnnormalizedTexCoordSum / Double(n*n)
						
						//	For n = 4, the indexing scheme looks like this
						//
						//		20 21 22 23 24
						//		15 16 17 18 19
						//		10 11 12 13 14
						//		 5  6  7  8  9
						//		 0  1  2  3  4
						//
						//	and works similarly for other values of n.
						//
						theVertices[(n+1)*j + k] = KaleidoTileVertexData(
							p: SIMD3<Float32>(thePosition),
							n: SIMD3<Float16>(theNormal),
							t: SIMD2<Float32>(theTextureCoordinates) )
					}
				}
			}
			
			theVertexBuffers.append(theVertexBuffer)

		}	//	end of which quad
		
		//	The three meshes all share a single face buffer.
		//
		//		Note:  In KaleidoTile the user views the polyhedron or tiling
		//		from the negative z axis in a left-handed coordinate system.
		//		From that point of view, the winding order of a triangle
		//		near the north pole (0,0,+1) is counterclockwise.
		//		Note that the user, in effect, sees Euclidean and hyperbolic
		//		tilings "from underneath" (that is, from the negative z side),
		//		and a spherical tiling's front faces lie on the inside of the sphere.
		//
		let theFaceIndexCount = 2 * 3 * n * n
		faceBufferPool.ensureSize(theFaceIndexCount * MemoryLayout<UInt16>.stride)
		let theFaceBuffer = faceBufferPool.get(forUseWith: commandBuffer)
		let theFaceIndices = theFaceBuffer.contents().bindMemory(
											to: UInt16.self,
											capacity: theFaceIndexCount)
		for j in 0 ... (n-1) {
			for k in 0 ... (n-1) {
			
				let bi = 6*(n*j + k)	//	"bi" = "base index"

				theFaceIndices[bi + 0] = UInt16( (n + 1)*j + k + 0           )
				theFaceIndices[bi + 1] = UInt16( (n + 1)*j + k + 1           )
				theFaceIndices[bi + 2] = UInt16( (n + 1)*j + k + (n + 1)     )

				theFaceIndices[bi + 3] = UInt16( (n + 1)*j + k + (n + 1)     )
				theFaceIndices[bi + 4] = UInt16( (n + 1)*j + k + 1           )
				theFaceIndices[bi + 5] = UInt16( (n + 1)*j + k + (n + 1) + 1 )
			}
		}

		return (theVertexCount, theVertexBuffers, theFaceIndexCount, theFaceBuffer)
	}

	func meshSize(
		reflectionGroup: ReflectionGroup,
		tilingStyle: TilingStyle
	) -> Int {
	
		switch tilingStyle {
		
		case .flat:
		
			//	Realize a flat quad as a 1 × 1 mesh.
			return 1
			
		case .curved:
			
			let p = reflectionGroup.p
			let q = reflectionGroup.q
			let r = reflectionGroup.r

			//	The triangle's area will be
			//
			//		(π/p + π/q + π/r) - π	in the spherical case,
			//		0						in the euclidean case, and
			//		π - (π/p + π/q + π/r)	in the hyperbolic case.
			//
			//	The sign of
			//
			//		  (π/p + π/q + π/r) - π
			//		= (π/pqr) [(qr + rp + pq) - pqr]
			//
			//	determines the geometry.  Moreover, the second factor's
			//	exact value gives a pretty good idea which tiling it is.
			
			switch q*r + r*p + p*q - p*q*r {
			
			case 4:		//	(2,2,n)
				return  1			//	will get rendered as .flat, no matter what
			
			case 3:		//	(2,3,3)
				return 16
			
			case 2:		//	(2,3,4)
				return 16
			
			case 1:		//	(2,3,5)
				return  8
			
			case 0:		//	all euclidean tilings
				return  1
			
			case -1:	//	(2,3,7)		(but no others, I'm guessing)
				return  4
			
			case -2:	//	(2,3,8)		(and others???)
				return  4
			
			default:	//	all other hyperbolic tilings
				return  16
			}
		}
	}

	func chooseTextureCoordinates(
		corners: [SIMD3<Double>],	//	four co-planar corners
		metricH: Metric
	) -> [SIMD2<Double>] {	//	texture coordinates for the four corners

		//	We'll choose texture coordinates so that the texture image
		//	maps onto the quad without distortion when tilingStyle == .flat
		//	-- whether or not the tilingStyle really is flat at this moment.
		//	On that assumption, we expect all four corners to lie
		//	in a single plane orthogonal to corner 0.
		//	Assign corner 0 the texture coordinate (1/2, 0).
		//	Assign corner 3 the texture coordinate (1/2, 1).
		//	Assign the remaining texture coordinate so as to respect aspect ratios.

		//	How small must a face be before we revert to default texture coordinates?
		let theMinTextureAxisLength = 0.001
		let theFallbackTextureCoordinates = [
			SIMD2<Double>(0.5, 0.0),
			SIMD2<Double>(1.0, 0.5),
			SIMD2<Double>(0.0, 0.5),
			SIMD2<Double>(0.5, 1.0),
		]

		//	How long is the diagonal from corner 0 to corner 3?
		let theAxisA = corners[3] - corners[0]
		let theLengthA = metricH.length(theAxisA)
		if theLengthA < theMinTextureAxisLength {
			return theFallbackTextureCoordinates
		}

		//	Rescale everything to normalize the aforementioned diagonal to length one.
		let theRescaledCorners = corners.map() { corner in corner / theLengthA }
		let theUnitLengthAxisA = theAxisA / theLengthA

		//	Find an orthogonal axis.
		let theAxisB = theRescaledCorners[1] - theRescaledCorners[2]
		let theInnerProduct = metricH.innerProduct(theAxisB, theUnitLengthAxisA)
		let theProjection = theInnerProduct * theUnitLengthAxisA
		let theOrthogonalAxis = theAxisB - theProjection
		let theOrthogonalAxisLength = metricH.length(theOrthogonalAxis)
		if theOrthogonalAxisLength < theMinTextureAxisLength {
			return theFallbackTextureCoordinates
		}
		let theUnitLengthOrthogonalAxis = theOrthogonalAxis / theOrthogonalAxisLength

		//	Compute the texture coordinates relative to the given axes.
		let theCornerTextureCoordinates = theRescaledCorners.map() { corner in

			let theRelativePosition = corner - theRescaledCorners[0]

			return SIMD2<Double>(
				0.5 + metricH.innerProduct(theRelativePosition, theUnitLengthOrthogonalAxis	),
				0.0 + metricH.innerProduct(theRelativePosition, theUnitLengthAxisA			)
			)
		}
		
		return theCornerTextureCoordinates
	}
}
