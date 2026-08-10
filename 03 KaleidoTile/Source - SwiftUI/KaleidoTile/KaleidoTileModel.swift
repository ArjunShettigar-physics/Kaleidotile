//	KaleidoTileModel.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import Foundation


struct ReflectionGroup: Equatable {
	var p: Int
	var q: Int
	var r: Int
	
	init(
		_ p: Int,
		_ q: Int,
		_ r: Int
	) {
		self.p = p
		self.q = q
		self.r = r
	}
		
	static func == (lhs: ReflectionGroup, rhs: ReflectionGroup
	) -> Bool {
	
		return
			lhs.p == rhs.p
		 && lhs.q == rhs.q
		 && lhs.r == rhs.r
	}
}

//	Draw the tiling as a polyhedron with flat faces
//	or as a tiling of a curved surface?
enum TilingStyle: Int, CaseIterable, Identifiable {

	case flat
	case curved

	var id: Int { self.rawValue }
}

enum Metric {

	case Euclidean	//	signature +++
	case MinkowskiS	//	signature ++-  (spacelike vectors have positive squared length)
	case MinkowskiT	//	signature --+  ( timelike vectors have positive squared length)
	case horizontal	//	signature ++0
	case vertical	//	signature 00+
	
	func innerProduct(
		_ u: SIMD3<Double>,
		_ v: SIMD3<Double>
	) -> Double {
	
		switch self {
		case .Euclidean:	return   u.x * v.x  +  u.y * v.y   +  u.z * v.z
		case .MinkowskiS:	return   u.x * v.x  +  u.y * v.y   -  u.z * v.z
		case .MinkowskiT:	return -(u.x * v.x  +  u.y * v.y)  +  u.z * v.z
		case .horizontal:	return   u.x * v.x  +  u.y * v.y
		case .vertical:		return                                u.z * v.z
		}
	}
	
	func length(
		_ u: SIMD3<Double>
	) -> Double {
	
		return sqrt(fabs(innerProduct(u, u)))
	}

	func normalize(
		_ u: SIMD3<Double>
	) -> SIMD3<Double> {
	
		let theLength = length(u)

		//	Don't try to normalize the unnormalizable.
		let ε = 1e-4
		if theLength < ε {
			assertionFailure("normalize() received a vector of length less than ε")
			return u
		}
		
		let theNormalizedVector = (1.0/theLength) * u
		
		return theNormalizedVector
	}
}

enum GeometryType {
	case spherical
	case euclidean
	case hyperbolic
	
	var metricForVertical: Metric {		//	Euclidean tiling needs  "vertical"  00+ metric
		switch self {
		case .spherical:	return .Euclidean	//	signature +++
		case .euclidean:	return .vertical	//	signature 00+
		case .hyperbolic:	return .MinkowskiT	//	signature --+
		}
	}
	
	var metricForHorizontal: Metric {	//	Euclidean tiling needs "horizontal" ++0 metric
		switch self {
		case .spherical:	return .Euclidean	//	signature +++
		case .euclidean:	return .horizontal	//	signature ++0
		case .hyperbolic:	return .MinkowskiS	//	signature ++-
		}
	}
}

//	The triple point is the point in the base triangle
//	where the three faces types (typically with different
//	colors or images) meet.  The triple point's location
//	is stored in barycentric coordinates relative
//	to the base triangle's barycentric basis.
//	Please see the comment accompanying the definition
//	of BaseTriangle.barycentricBasis for more details.
//	The TriplePoint's three coordinates always sum to 1.0.
typealias TriplePoint = SIMD3<Double>

//	KaleidoTile lets the TriplePoint move about
//	in its parameter space, which is a triangle
//	with vertices at (1,0,0), (0,1,0) and (0,0,1),
//	reflecting off the triangles sides as needed.
//	A TriplePointIncrement says how much
//	to advance the TriplePoint each frame.
//	The TriplePointIncrement's three coordinates
//	always sum to 0.0.
typealias TriplePointIncrement = SIMD3<Double>

//	The triple-point view will scale and offset
//	the othrogonal projectino of the base triangle
//	using a transformation that acts as
//
//		          ( scale  0    0 )
//		(x, y, 1) (   0  scale  0 )
//		          (  Δx   Δy    1 )
//
struct NDCPlacement {
	var scale: Double
	var Δx: Double
	var Δy: Double
}

enum FacePaintingStyle {
	case solidColor
	case texture	//	a texture from the camera or the user's photo library
					//		(or maybe a built-in texture at launch)
	case invisible	//	face or background isn't drawn at all
}

enum TextureSource: Equatable {
	case fromCamera
	case fromPhotoLibrary
	case fromFiles
	case fromPasteboard
	case previous
	case builtInBackground(BackgroundTextureIndex)
}

struct FacePainting {

	//	On the one hand, we'd have (trivially) simpler code
	//	if we defined a FacePainting to be an enum with associated values
	//
	//		enum FacePainting {
	//			case solidColor(SIMD4<Float16>)
	//			case texture(TextureSource)
	//			case invisible
	//		}
	//
	//	On the other hand, by including a FacePaintingStyle enum
	//	as part of a FacePainting struct, we can keep the most
	//	recently chosen color and texture for possible future use.
	//	For example, if the user chooses a color, then switches
	//	to a texture, then returns to the color picker, it will
	//	remember the previously chosen color.  Conversely, if
	//	the user chooses a texture and then switches to a color,
	//	s/he will have the option of returning to the previously
	//	chosen texture.
	
	//	Is the face or background colored, textured or invisible?
	var style: FacePaintingStyle
	
	//	If the face is colored, what color?
	var color: SIMD4<Float16>	// premultiplied linear extended-range sRGB
			= SIMD4<Float16>(1.0, 1.0, 1.0, 1.0)

	//	If the face is textured, what was the source?
	//
	//		Note:  We rely on the renderer to load a default texture
	//		for each face and for the background, even if they're not initially used.
	//
	var textureSource: TextureSource = .previous
}

let π = Double.pi


@Observable class KaleidoTileModel: GeometryGamesUpdatable {

	var itsOrientation: simd_double3x3 = matrix_identity_double3x3
	
	//	Assuming a constant frame rate, with gFramePeriod seconds
	//	from the start of one frame to the start of the next,
	//	let itsIncrement be the small additional motion
	//	that we want to post-multiply (meaning left-multiply,
	//	because we're using the right-to-left matrix convention)
	//	for each successive frame.
	//
	var itsIncrement: simd_double3x3?	//	= nil when tiling isn't moving

	var itsBaseTriangle: BaseTriangle = BaseTriangle(reflectionGroup: ReflectionGroup(2,3,5)) {
		didSet {
			itsOrientation = matrix_identity_double3x3
			itsIncrement = adaptIncrementToGeometry(
							oldGeometry: oldValue.geometry,
							newGeometry: itsBaseTriangle.geometry)
			changeCount += 1
		}
	}
	var itsTilingStyle: TilingStyle = .flat {
		didSet {
			Task { enqueueSoundRequest("pop.wav") }
			changeCount += 1
		}
	}
	
	//	Store the itsTriplePoint and itsTriplePointIncrement
	//	independently of itsBaseTriangle, so that even
	//	when the user changes the symmetry group,
	//	the aesthetic nature of the tiling will remain the same.
	var itsTriplePoint: TriplePoint = TriplePoint(0.502, 0.351, 0.147)
	var itsTriplePointIncrement: TriplePointIncrement?	//	= nil when triple point isn't moving
								= TriplePointIncrement(0.0013, +0.0031, -0.0044)
	
	//	Colored, textured or invisible faces and background?
	//	The indices 0, 1 and 2 refer to faces on the polyhedron,
	//	while the index 3 refers to the background image.
	var itsFacePaintings: [FacePainting] = [

		FacePainting(
			style: .solidColor,
			color: SIMD4<Float16>(0.50, 0.00, 1.00, 1.00)),

		FacePainting(
			style: .solidColor,
			color: SIMD4<Float16>(1.00, 0.75, 0.00, 1.00)),

		FacePainting(
			style: .texture,
			color: SIMD4<Float16>(0.00, 0.75, 0.25, 1.00),	//	seen only if user switches to .solidColor
			textureSource: .previous),

		FacePainting(
			style: .texture,
			color: SIMD4<Float16>(0.50, 0.50, 0.50, 1.00),	//	seen only if user switches to .solidColor
			textureSource: .builtInBackground(defaultBackground))
	]
	
	var itsShowPlainImages: Bool = true {
		didSet { changeCount += 1 }
	}
	var itsShowReflectedImages: Bool = true {
		didSet { changeCount += 1 }
	}
	var itsCutAlongMirrorLines: Bool = false {
		didSet { changeCount += 1 }
	}
	var itsSnapToArchimedeanSolids: Bool = true

	var changeCount: UInt64 = 0
	func updateModel() -> UInt64 {

		if let theIncrement = itsIncrement {
			applyOrientationIncrement(theIncrement)
		}
		
		if let theTriplePointIncrement = itsTriplePointIncrement {
			applyTriplePointIncrement(theTriplePointIncrement)
		}
		
		return changeCount
	}

	func applyOrientationIncrement(
		_ anIncrement: simd_double3x3
	) {
		itsOrientation = anIncrement * itsOrientation	//	right-to-left matrix action
		keepTilingCentered()
		itsOrientation = gramSchmidt(itsOrientation, geometry: itsBaseTriangle.geometry)

		changeCount += 1
	}

	func keepTilingCentered() {

		//	Pre-multiply by a generator whenever necessary
		//	to ensure that the tiling's central triangle
		//	always covers the north pole.
		
		var keepGoing: Bool
		repeat {
		
			keepGoing = false
			
			for theGenerator in itsBaseTriangle.generators {
			
				let theCandidate = itsOrientation * theGenerator	//	right-to-left matrix action

				let u = itsOrientation[2]	//	  current   image of tiling's center
				let v = theCandidate[2]		//	candidate's image of tiling's center
				
				var theCandidateIsCloser: Bool
				switch itsBaseTriangle.geometry {
				
				case .spherical:
					theCandidateIsCloser = (v.z > u.z)
					
				case .euclidean:
					theCandidateIsCloser = (v.x * v.x  +  v.y * v.y
										 <  u.x * u.x  +  u.y * u.y)
					
				case .hyperbolic:
					theCandidateIsCloser = (v.z < u.z)
				}
				
				if theCandidateIsCloser {
					itsOrientation = theCandidate
					keepGoing = true
				}
			}
			
		} while keepGoing
	}
	
	func adaptIncrementToGeometry(
		oldGeometry: GeometryType,
		newGeometry: GeometryType
	) -> simd_double3x3? {
	
		//	If itsIncrement is nil, there's nothing to adapt.
		guard var m = itsIncrement else {
			return nil
		}
		
		//	When the user switches from a Euclidean tiling to a hyperbolic tiling,
		//	the motion will look qualitatively the same.  But when the user
		//	switches to or from a spherical tiling, the direction of motion
		//	would be consistent with the triangles on the back side of the sphere,
		//	not the front.  So for visually satisfying results, when
		//	the user switches to or from a spherical tiling,
		//	let's negate the translational matrix elements m[2][0] and m[2][1].
		//	But leave the rotational matrix element m[1][0] the same.
		if (oldGeometry == .spherical) != (newGeometry == .spherical) {
			m[2][0] = -m[2][0]
			m[2][1] = -m[2][1]
		}
		
		//	For a small motion in any of the three geometries
		//	we expect the matrix entries on m's main diagonal
		//	to be close to 1.0 and off-diagonal entries to be close to 0.0.
		//	The relationship between the entries below the main diagonal
		//	and those above it depends on the geometry.
		switch newGeometry {
		
		case .spherical:
			m[0][1] = -m[1][0]
			m[0][2] = -m[2][0]
			m[1][2] = -m[2][1]
			
		case .euclidean:
			m[0][1] = -m[1][0]
			m[0][2] =   0.0
			m[1][2] =   0.0
			
		case .hyperbolic:
			m[0][1] = -m[1][0]
			m[0][2] =  m[2][0]
			m[1][2] =  m[2][1]
		}
		
		let thePreciseMatrix = gramSchmidt(m, geometry: newGeometry)
		
		return thePreciseMatrix
	}
	
	func applyTriplePointIncrement(
		_ aTriplePointIncrement: TriplePointIncrement
	) {
	
		itsTriplePoint += aTriplePointIncrement
		keepTriplePointInBaseTriangle()
		normalizeTriplePoint()
		
		changeCount += 1
	}
	
	func keepTriplePointInBaseTriangle() {
	
		//	We want itsTriplePoint to stay within the triangle
		//	where all weights are positive, that is, within
		//	the triangle with vertices at (1,0,0), (0,1,0) and (0,0,1).
		//	If it leaves that triangle, reflect it back in
		//	and adjust the increment accordingly.
		
		var progress: Bool
		repeat {
		
			progress = false

			for i in 0...2 {
			
				if itsTriplePoint[i] < 0.0 {
				
					//	The following formulas do the right thing.
					//	The proof is basically to make some sketches
					//	of what's going on.
				
					var reflectedTriplePoint = TriplePoint()
					reflectedTriplePoint[(i+0)%3] =      -itsTriplePoint[(i+0)%3]
					reflectedTriplePoint[(i+1)%3] = 1.0 - itsTriplePoint[(i+2)%3]
					reflectedTriplePoint[(i+2)%3] = 1.0 - itsTriplePoint[(i+1)%3]
					itsTriplePoint = reflectedTriplePoint
					
					if let theTriplePointIncrement = itsTriplePointIncrement {
					
						var reflectedTriplePointIncrement = TriplePointIncrement()
						reflectedTriplePointIncrement[(i+0)%3] = -theTriplePointIncrement[(i+0)%3]
						reflectedTriplePointIncrement[(i+1)%3] = -theTriplePointIncrement[(i+2)%3]
						reflectedTriplePointIncrement[(i+2)%3] = -theTriplePointIncrement[(i+1)%3]
						itsTriplePointIncrement = reflectedTriplePointIncrement
					}

					changeCount += 1

					progress = true
				}
			}
			
		} while progress
	}
	
	func normalizeTriplePoint() {
	
		let theSum = reduce_add(itsTriplePoint)	//	should be 1.0 with only tiny numerical error
		if abs(theSum - 1.0) > 0.01 {
			assertionFailure("itsTriplePoint components don't sum to 1")
			itsTriplePoint = TriplePoint(1.0/3.0, 1.0/3.0, 1.0/3.0)
		}
		itsTriplePoint /= theSum

		changeCount += 1
	}
}

func gramSchmidt(
	_ mIn: simd_double3x3,
	geometry: GeometryType
) -> simd_double3x3 {

	//	Remove numerical errors, so the matrix stays
	//	in the required group ( O(3), Isom(E²) or O(2,1) ).

	var m = mIn

	let theMetricPair: simd_double2x3
	switch geometry {
	
	case .spherical:
		theMetricPair = simd_double2x3(
			SIMD3<Double>(+1, +1, +1),
			SIMD3<Double>(+1, +1, +1)
		)
		
	case .euclidean:
		theMetricPair = simd_double2x3(
			SIMD3<Double>(+1, +1,  0),	//	horizontal metric
			SIMD3<Double>( 0,  0, +1)	//	vertical metric
		)
		
	case .hyperbolic:
		theMetricPair = simd_double2x3(
			SIMD3<Double>(+1, +1, -1),	//	for spacelike vectors
			SIMD3<Double>(-1, -1, +1)	//	for timelike vectors
		)
	}
	
	for i in (0...2).reversed() {	//	start with the last row, which may use a different metric

		let theMetric = theMetricPair[i == 2 ? 1 : 0]
		
		//	Normalize row i to unit length.
		//
		//		Because m is already approximately orthonormal,
		//		we know the arguments passed to the sqrt() function
		//		will always be close to 1.0, so no need to worry
		//		about checking for non-positive values.
		//
		let theLength = sqrt( dot(theMetric, m[i] * m[i]) )
		m[i] /= theLength
		
		//	Make all preceding rows orthogonal to row i.
		for j in 0 ..< i {
		
			let theInnerProduct = dot(theMetric, m[i] * m[j])
			
			m[j] -= theInnerProduct * m[i]
		}
	}
	
	return m
}


// MARK: -
// MARK: Base triangle

//	The base triangle is a triangle with angles π/p, π/q and π/r
//	that gets reflected around by the (p,q,r) triangle group
//	to generate the tiling.  The base triangle's edges lie
//	on the tiling's lines of symmetry.  The base triangle
//	gets cut into three differently-colored quadrilaterals,
//	which meet at the so-called "triple point".
//
struct BaseTriangle {

	var reflectionGroup: ReflectionGroup {
		didSet {
			if reflectionGroup != oldValue {
				enqueueSoundRequest("thud.wav")
				refreshForNewReflectionGroup()
			}
		}
	}
	
	var geometry: GeometryType = .spherical
	var vertices: [SIMD3<Double>] = []	//	three unit-length vertices
	var outradius: Double = 0.0
	var generators: [simd_double3x3] = []

	//	The barycentric basis is a rescaling of the base triangle's
	//	three vertices, with the lengths chosen so that
	//	the barycentric coordinates
	//
	//		(1,0,0), (0,1,0) and (0,0,1)
	//			give the base triangle's vertices (trivially true!),
	//
	//		(0, 1/2, 1/2), (1/2, 0, 1/2) and (1/2, 1/2, 0)
	//			give the intersections of the angle bisectors
	//			with the opposite sides, and
	//
	//		(1/3, 1/3, 1/3)
	//			gives the base triangle's incenter
	//			(always at the north pole, by construction).
	//
	//	In all cases the stated coordinates give a vector
	//	that points in the correct direction, but whose
	//	length is essentially arbitrary.
	//
	var barycentricBasis: simd_double3x3 = simd_double3x3()
	
	//	After projecting orthogonally onto the xy plane,
	//	how should we scale and offset the base triangle
	//	so that it fills roughly 90% of the "normalized
	//	device coordinates", which run from -1.0...+1.0
	//	in each direction.
	//
	var ndcPlacement: NDCPlacement = NDCPlacement(scale: 1.0, Δx: 0.0, Δy: 0.0)
	
	
	init(reflectionGroup: ReflectionGroup) {
	
		self.reflectionGroup = reflectionGroup

		refreshForNewReflectionGroup()
	}
	
	mutating func refreshForNewReflectionGroup() {
	
		//	Is this a spherical, Euclidean or hyperbolic tiling?
		geometry = getGeometry(reflectionGroup: reflectionGroup)
		
		//	Before reading the following code, draw yourself a figure
		//	as follows.  Begin with an arbitrary triangle and label
		//	its angles π/p, π/q and π/r.  Draw the inscribed circle.
		//	Draw segments from each of the triangle's vertices to the center
		//	of the inscribed circle.  By symmetry, these are the angle
		//	bisectors.  Now draw segments from each point of tangency
		//	(where the inscribed circle touches the triangle) to the
		//	center of the inscribed circle.  These segments meet the
		//	triangle at right angles.  The segments you've drawn divide
		//	the triangle into six smaller triangles.  Focus your attention
		//	on one of the small triangles incident to the vertex of angle π/p.
		//	Label the small triangle's angles π/2p, π/2 and θ_p.
	
		//	Compute the base triangle's dimensions as described
		//	in the paragraph immediately above.
		let (inradius, incenterToVertexDistances, θ)
			= getTriangleDimensions(
				geometry: geometry,
				reflectionGroup: reflectionGroup)
		
		//	Compute the base triangle's vertices, as unit-length vectors.
		vertices = getVertices(
				geometry: geometry,
				incenterToVertexDistances: incenterToVertexDistances,
				θ: θ)
		
		//	Compute the base triangle's outradius.
		outradius = reduce_max(incenterToVertexDistances)
		
		//	Compute the reflections across the base triangle's sides.
		generators = getGenerators(
				geometry: geometry,
				inradius: inradius,
				θ: θ)
		
		//	Compute the barycentricBasis.
		barycentricBasis = getBarycentricBasis(vertices: vertices)
		
		//	Compute the placement in normalized device coordinates (NDC).
		ndcPlacement = getNDCPlacement(vertices: vertices)
	}
}

func getGeometry(
	reflectionGroup: ReflectionGroup
) -> GeometryType {

	//	The geometry will be spherical, Euclidean or hyperbolic
	//	according to whether the angle sum is greater than,
	//	equal to, or less than π.
	//
	//			π/p + π/q + π/r  ⋛  π
	//
	//	Multiply through by pqr/π to convert to an integer equation
	//
	//			qr + pr + pq  ⋛  pqr
	//
	//	The numbers p, q and r will be small enough that we needn't worry
	//	about overflows.
	
	let p = reflectionGroup.p
	let q = reflectionGroup.q
	let r = reflectionGroup.r
	
	let theValue = q*r + p*r + p*q - p*q*r
	
	if theValue > 0 {
		return .spherical
	} else if theValue == 0 {
		return .euclidean
	} else {	//	theValue < 0
		return .hyperbolic
	}
}

func getTriangleDimensions(
	geometry: GeometryType,
	reflectionGroup: ReflectionGroup
) -> (Double, SIMD3<Double>, SIMD3<Double>) {	//	returns (inradius, incenter-to-vertex distances, θ's)

	let pqr = SIMD3<Double>(
				Double(reflectionGroup.p),
				Double(reflectionGroup.q),
				Double(reflectionGroup.r) )

	//	The base triangle has angles π/p, π/q and π/r.
	//	Break into cases to analyze it.
	//	The spherical and hyperbolic cases are almost identical.
	//	The Euclidean case is exceptional.
	//
	let θ: [Double]
	let theInradius: Double
	let theIncenterToVertexDistances: [Double]
	switch geometry {
	
	case .spherical:

		//	Let theSides[i] be the length of the big triangle's
		//	side opposite vertex i.
		//	Use the spherical law of cosines for angles to solve
		//	for the length of side c in terms of the angles A,B,C.
		//
		//		cos C = -cos A cos B + sin A sin B cos c
		//
		let theSides = (0...2).map() { i in
			
			//	The Swift compiler needs help understanding that
			//	the given expression evaluates to a Double.  If we try
			//	to return the expression directly -- without first
			//	assigning it to the variable theResult -- we get
			//
			//		The compiler is unable to type-check this expression
			//		in reasonable time; try breaking up the expression
			//		into distinct sub-expressions.
			//
			let p = pqr[   i   ]	//	makes type checking easier for Swift compiler
			let q = pqr[(i+1)%3]
			let r = pqr[(i+2)%3]
			let theResult: Double =
				acos( (cos(π/p) + cos(π/q)*cos(π/r)) / (sin(π/q)*sin(π/r)) )
			
			return theResult
		}

		//	Let theTangents[i] be the length of the segment from
		//	vertex i to either point of tangency where the inscribed
		//	circle touches the triangle's side.  Clearly
		//
		//		theSides[i] = theTangents[(i+1)%3] + theTangents[(i+2)%3]
		//
		//	so it's easy to solve for theTangents.
		//
		let theTangents = (0...2).map() { i in
			
			let i1 = (i+1)%3	//	makes type checking easier for Swift compiler
			let i2 = (i+2)%3
			let theResult: Double =
				0.5 * (theSides[i1] + theSides[i2] - theSides[i])
			
			return theResult
		}

		//	Now consider each of the six small triangles described
		//	in the documentation at the beginning of this function.
		//	Apply the spherical law of cosines for angles to solve
		//	for θ_p, θ_q, and θ_r.
		//
		θ = (0...2).map() { i in
			
			let theResult: Double =
				acos( cos(theTangents[i]) * sin(π/(2.0*pqr[i])) )
			
			return theResult
		}

		//	Apply the spherical law of cosines for angles
		//	to solve for the inradius.
		theInradius = acos( cos(π/(2.0*pqr[0])) / sin(θ[0]) )

		//	Apply the spherical law of cosines for angles once more
		//	to solve for the radial distance from the incenter
		//	to each vertex of the large triangle.
		theIncenterToVertexDistances = (0...2).map() { i in
			
			let theResult: Double =
				acos( 1.0 / (tan(π/(2.0*pqr[i])) * tan(θ[i])) )
			
			return theResult
		}

	case .euclidean:
	
		//	The θ's are the complements of π/2p, π/2q and π/2r.
		θ = (0...2).map() { i in
			let theResult: Double = 0.5 * π * (1.0 - 1.0/pqr[i])
			return theResult
		}

		//	In the Euclidean case, the base triangle's inradius
		//	may be anything we want.
		theInradius = 0.1

		//	Solve for the radial distance from the incenter
		//	to each vertex of the large triangle.
		theIncenterToVertexDistances = (0...2).map() { i in
			let theResult: Double = theInradius / sin(π/(2.0*pqr[i]))
			return theResult
		}

	case .hyperbolic:

		//	The hyperbolic case is identical to the spherical case,
		//	except that cosh() and acosh() sometimes appear in place
		//	of cos() and acos().

		//	Let theSides[i] be the length of the big triangle's
		//	side opposite vertex i.
		//	Use the hyperbolic law of cosines for angles to solve
		//	for the length of side c in terms of the angles A,B,C.
		//
		//		cos C = -cos A cos B + sin A sin B cosh c
		//
		let theSides = (0...2).map() { i in
		
			let p = pqr[   i   ]	//	makes type checking easier for Swift compiler
			let q = pqr[(i+1)%3]
			let r = pqr[(i+2)%3]
			let theResult: Double =
				acosh( (cos(π/p) + cos(π/q)*cos(π/r)) / (sin(π/q)*sin(π/r)) )
			
			return theResult
		}

		//	Let theTangents[i] be the length of the segment from
		//	vertex i to either point of tangency where the inscribed
		//	circle touches the triangle's side.  Clearly
		//
		//		theSides[i] = theTangents[(i+1)%3] + theTangents[(i+2)%3]
		//
		//	so it's easy to solve for theTangents.
		//
		let theTangents = (0...2).map() { i in
			
			let theResult: Double =
				0.5 * (theSides[(i+1)%3] + theSides[(i+2)%3] - theSides[i])
			
			return theResult
		}

		//	Now consider each of the six small triangles described
		//	in the documentation at the beginning of this function.
		//	Apply the hyperbolic law of cosines for angles to solve
		//	for θ_p, θ_q, and θ_r.
		//
		θ = (0...2).map() { i in
		
			let theResult: Double =
				acos( cosh(theTangents[i]) * sin(π/(2.0*pqr[i])) )
			
			return theResult
		}

		//	Apply the hyperbolic law of cosines for angles
		//	to solve for the inradius.
		theInradius = acosh( cos(π/(2.0*pqr[0])) / sin(θ[0]) )

		//	Apply the hyperbolic law of cosines for angles once more
		//	to solve for the radial distance from the incenter
		//	to each vertex of the large triangle.
		theIncenterToVertexDistances = (0...2).map() { i in
			
			let theResult: Double =
				acosh( 1.0 / (tan(π/(2.0*pqr[i])) * tan(θ[i])) )
			
			return theResult
		}
	}

	return (theInradius, SIMD3<Double>(theIncenterToVertexDistances), SIMD3<Double>(θ))
}

func getVertices(
	geometry: GeometryType,
	incenterToVertexDistances: SIMD3<Double>,
	θ: SIMD3<Double>
) -> [SIMD3<Double>] {	//	base triangle's three vertices as unit-length vectors

	let theVertices = [
	
		//	The -π/2 term puts the point of tangency,
		//	where the side opposite vertex 0 touches the unit circle,
		//	on the negative y axis.  We do this for purely
		//	aesthetic reasons, so the triangle will "look horizontal"
		//	when drawn in the triple-point view.

		polarToRectangular(
			geometry: geometry,
			r: incenterToVertexDistances[0],
			θ: -0.5*π + 2.0*θ[2] + θ[0]
		),

		polarToRectangular(
			geometry: geometry,
			r: incenterToVertexDistances[1],
			θ: -0.5*π - θ[1]
		),

		polarToRectangular(
			geometry: geometry,
			r: incenterToVertexDistances[2],
			θ: -0.5*π + θ[2]
		)
	]
	
	return theVertices
}

func polarToRectangular(
	geometry: GeometryType,
	r: Double,
	θ: Double
) -> SIMD3<Double> {

	switch geometry {
	
	case .spherical:
		return SIMD3<Double>(
				sin(r) * cos(θ),
				sin(r) * sin(θ),
				cos(r) )
	
	case .euclidean:
		return SIMD3<Double>(
				r * cos(θ),
				r * sin(θ),
				1.0 )
		
	case .hyperbolic:
		return SIMD3<Double>(
				sinh(r) * cos(θ),
				sinh(r) * sin(θ),
				cosh(r) )
		
	}
}

func getGenerators(
	geometry: GeometryType,
	inradius: Double,
	θ: SIMD3<Double>
) -> [simd_double3x3] {	//	returns the reflections across the base triangle's three sides

	//	Compute the reflection matrix for each side of the base triangle.
	//	By construction, the base triangle's incenter sits at the north pole (0,0,1)
	//	and the side opposite vertex 0 touches the incircle at a point
	//	on the negative y axis.
	//
	//	Our plan is to start with a reflection in the direction of the y-axis,
	//	conjugate it by a translation to get generator0, and then
	//	conjugate by rotations to get generator1 and generator2.
	
	let theYReflection = simd_double3x3.init(diagonal: SIMD3<Double>(+1.0, -1.0, +1.0))
	let theYTranslation = yTranslation(distance: -inradius, geometry: geometry)
	let theYTranslationInverse = geometricInverse(theYTranslation, geometry: geometry)
	let theGenerator0 = theYTranslation	//	right-to-left matrix action
					  * theYReflection
					  * theYTranslationInverse

	//	Rotate theGenerator0 about the base triangle's incenter,
	//	which sits at the north pole (0,0,1), to get
	//	theGenerator1 and theGenerator2.  The sketch you made
	//	from the comment near the top of BaseTriangle.init()
	//	should make this clear.  Viewed from above the north pole,
	//	the vertices of angle π/p, π/q and π/r go
	//	in counterclockwise order in a left-handed coordinate system.
	
	let theZRotation1 = zRotation( -2.0 * θ[2] )
	let theZRotation1Inverse = theZRotation1.transpose	//	inverse = transpose in this case
	let theGenerator1 = theZRotation1	//	right-to-left matrix action
					  * theGenerator0
					  * theZRotation1Inverse
	
	let theZRotation2 = zRotation( +2.0 * θ[1] )
	let theZRotation2Inverse = theZRotation2.transpose	//	inverse = transpose in this case
	let theGenerator2 = theZRotation2	//	right-to-left matrix action
					  * theGenerator0
					  * theZRotation2Inverse
	
	return [
		theGenerator0,
		theGenerator1,
		theGenerator2
	]
}

func yTranslation(
	distance d: Double,
	geometry: GeometryType
) -> simd_double3x3 {

	let theTranslation: simd_double3x3
	switch geometry {
	
	case .spherical:
	
		theTranslation = simd_double3x3(
			SIMD3<Double>( 1.0,   0.0,     0.0   ),
			SIMD3<Double>( 0.0,  cos(d), -sin(d) ),
			SIMD3<Double>( 0.0, +sin(d),  cos(d) ) )
		
	case .euclidean:
	
		theTranslation = simd_double3x3(
			SIMD3<Double>( 1.0, 0.0, 0.0 ),
			SIMD3<Double>( 0.0, 1.0, 0.0 ),
			SIMD3<Double>( 0.0,  d,  1.0 ) )
		
	case .hyperbolic:
	
		theTranslation = simd_double3x3(
			SIMD3<Double>( 1.0,   0.0,     0.0   ),
			SIMD3<Double>( 0.0, cosh(d), sinh(d) ),
			SIMD3<Double>( 0.0, sinh(d), cosh(d) ) )
	}
	
	return theTranslation
}

func zRotation(
	_ φ: Double
) -> simd_double3x3 {

	//	A rotation about the z axis uses the same matrix
	//	no matter what the geometry is.
	
	let theRotation = simd_double3x3(
		SIMD3<Double>(  cos(φ), -sin(φ), 0.0 ),
		SIMD3<Double>( +sin(φ),  cos(φ), 0.0 ),
		SIMD3<Double>(   0.0,     0.0,   1.0 ) )
	
	return theRotation
}

func getBarycentricBasis(
	vertices: [SIMD3<Double>]	//	three unit-length vertices
) -> simd_double3x3 {

	//	Our goal here is to rescale the base triangle's three vertices
	//	to satisfy the conditions listed in the comment accompanying
	//	the definition of the barycentricBasis.
	//
	//	Let the triangle's three original vertices be
	//	u = {u₀,u₁,u₂}, v = {v₀,v₁,v₂} and w = {w₀,w₁,w₂},
	//	and search for constants a, b and c such that
	//	the midpoint between a u and b v lies in the plane
	//	spanned by {0,0,0}, {0,0,1} and w, and similarly
	//	for the midpoints of the other two pairs.
	//
	//	The coplanarity condition just mentioned amounts to saying
	//	that the midpoint between a u and b v has the same ratio
	//	of its 0th and 1st coordinates as does w.  Writing out
	//	the ratios gives three linear equations in three variables,
	//	with solution
	//
	//		a = v₀ w₁ - v₁ w₀,
	//		b = w₀ u₁ - w₁ u₀,
	//		c = u₀ v₁ - u₁ v₀
	//
	//	Note that any consistent scalar multiple of a, b and c
	//	would work equally well.  I suspect the present formulas
	//	will yield positive a, b and c whenever the vertices u, v and w
	//	wind counterclockwise around the north pole (0,0,1).
	
	let u = vertices[0]
	let v = vertices[1]
	let w = vertices[2]
	
	let a =  v.x * w.y  -  v.y * w.x
	let b =  w.x * u.y  -  w.y * u.x
	let c =  u.x * v.y  -  u.y * v.x
	
	let theBarycentricBasis = simd_double3x3( a*u, b*v, c*w )
	
	return theBarycentricBasis
}

func getNDCPlacement(
	vertices: [SIMD3<Double>]	//	three unit-length vertices
) -> NDCPlacement {

	let minX = vertices.reduce( Double.greatestFiniteMagnitude,
				{ minSoFar, vertex in min(minSoFar, vertex[0]) })
	let maxX = vertices.reduce(-Double.greatestFiniteMagnitude,
				{ maxSoFar, vertex in max(maxSoFar, vertex[0]) })
	let minY = vertices.reduce( Double.greatestFiniteMagnitude,
				{ minSoFar, vertex in min(minSoFar, vertex[1]) })
	let maxY = vertices.reduce(-Double.greatestFiniteMagnitude,
				{ maxSoFar, vertex in max(maxSoFar, vertex[1]) })

	guard minX < maxX && minY < maxY else {
		assertionFailure("Impossible error:  base triangle has zero thickness")
		return NDCPlacement(scale: 3.0, Δx: 0.0, Δy: 0.0)
	}
	
	//	We want to fill only 90% of the width or height,
	//	to allow space for the triple-point "handle".
	let thePaddingFactor = 0.9
	
	let theXScale = 2.0 * thePaddingFactor / (maxX - minX)
	let theYScale = 2.0 * thePaddingFactor / (maxY - minY)
	
	let theScale = min(theXScale, theYScale)
	
	let theXOffset = -0.5*(minX + maxX) * theScale
	let theYOffset = -0.5*(minY + maxY) * theScale

	return NDCPlacement(
			scale: theScale,
			Δx: theXOffset,
			Δy: theYOffset)
}

func geometricInverse(
	_ m: simd_double3x3,
	geometry: GeometryType
) -> simd_double3x3 {	//	returns m⁻¹

	//	Computes the same thing as m.inverse,
	//	but with literally no loss of precision
	//	in the spherical and hyperbolic cases.
	//	That tiny bit of extra precision, if it's
	//	ever useful at all, could be relevant
	//	when doing large hyperbolic tilings,
	//	because such errors accumulate
	//	exponentially fast in hyperbolic geometry.
	
	var mInverse: simd_double3x3
	switch geometry {
	
	case .spherical:
	
		//	For matrices in O(3),
		//	the transpose is the inverse.
		mInverse = m.transpose
		
	case .euclidean:

		//	A Euclidean isometry factors as an element of O(2)
		//	followed by a translation.
		//
		//		(a  b  0)     (a  b  0) (1  0  0)
		//		(c  d  0)  =  (c  d  0) (0  1  0)
		//		(e  f  1)     (0  0  1) (e  f  1)
		//
		//	Its inverse is
		//
		//		( 1  0  0) (a  c  0)     (   a       c    0 )
		//		( 0  1  0) (b  d  0)  =  (   b       d    0 )
		//		(-e -f  1) (0  0  1)     (-ae-bf  -ce-df  1 )

		let a = m[0][0]
		let b = m[0][1]
		let c = m[1][0]
		let d = m[1][1]
		let e = m[2][0]
		let f = m[2][1]
		
		mInverse = simd_double3x3(
			SIMD3<Double>(     a,          c,     0 ),
			SIMD3<Double>(     b,          d,     0 ),
			SIMD3<Double>(-a*e - b*f, -c*e - d*f, 1 ) )

	case .hyperbolic:
	
		//	For matrices in O(2,1),
		//	the transpose is the inverse
		//	with some entries negated.
		
		mInverse = m.transpose
		
		mInverse[0][2] = -mInverse[0][2]
		mInverse[1][2] = -mInverse[1][2]
		mInverse[2][0] = -mInverse[2][0]
		mInverse[2][1] = -mInverse[2][1]
	}
	
	return mInverse
}
