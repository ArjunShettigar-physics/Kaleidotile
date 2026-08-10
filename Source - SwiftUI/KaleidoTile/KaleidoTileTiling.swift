//  KaleidoTileTiling.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import Metal


typealias KaleidoTileTile = simd_float3x3


//	In hyperbolic geometry, the tiling radius controls how many rings
//	of tiles get generated before the algorithm stops.
//
//	The original value of 5.5 was tuned for triangle groups like (2,3,7),
//	whose fundamental triangle is small, so many rings already fit within
//	that radius. But for very obtuse/wide groups -- e.g. large p such as
//	(18,2,4) -- the fundamental triangle is intrinsically much bigger
//	(Gauss-Bonnet: area = π(1 - 1/p - 1/q - 1/r)), so a radius of 5.5
//	barely reaches past the first ring, leaving the rest of the (correctly
//	rendered, but now-supported) 2...18 range looking sparse.
//
//	Raising the radius to 9.0 fixes this two ways at once:
//	  1) it directly generates several more rings for wide/obtuse groups
//	     like (18,2,4) (about 33x more tile instances than at 5.5), and
//	  2) it gives enough of a margin that panning the view (the existing
//	     drag gesture, which performs a genuine hyperbolic translation)
//	     doesn't immediately run off the edge of the generated data --
//	     dragging to re-center the view on a different point is the most
//	     effective way to bring compressed outer rings into clear view,
//	     since the Poincaré disk model necessarily compresses infinitely
//	     many rings near the boundary for ANY radius choice.
//
//	9.0 was chosen empirically (by porting this exact algorithm and
//	measuring instance counts): even (2,3,7) -- provably the densest
//	possible (p,q,r) reflection group, since it has the smallest possible
//	fundamental-triangle area of any hyperbolic triangle group -- produces
//	only ~340,000 instances at this radius, which is still cheap for
//	Metal's instanced rendering and takes well under the frame budget to
//	regenerate on parameter changes.
let coshHyperbolicTilingRadius = cosh(9.0)


struct KaleidoTileTiling {

	let device: MTLDevice
	
	var preparedBaseTriangle: BaseTriangle {
		didSet {
			if preparedBaseTriangle.reflectionGroup != oldValue.reflectionGroup {
				refreshTiling()
			}
		}
	}

	var plainInstanceCount: Int = 0
	var plainInstances: MTLBuffer?		//	if non-nil, contains an array of KaleidoTileTiles

	var reflectedInstanceCount: Int = 0
	var reflectedInstances: MTLBuffer?	//	if non-nil, contains an array of KaleidoTileTiles

	var identityInstance: MTLBuffer!	//	will contain the identity matrix only
	

	init(
		device: MTLDevice,
		baseTriangle: BaseTriangle
	) {
	
		self.device = device
		self.preparedBaseTriangle = baseTriangle
		
		identityInstance = copyInstancesToBuffer([matrix_identity_float3x3])
		
		refreshTiling()
	}
	
	mutating func refreshTiling() {

		//	The tiling changes only rarely, so we may
		//	create a new MTLBuffer each time it does.
		//	No need for a GeometryGamesBufferPool.
		
		let (thePlainInstances, theReflectedInstances) = makeTiling()

		plainInstanceCount = thePlainInstances.count
		plainInstances = copyInstancesToBuffer(thePlainInstances)

		reflectedInstanceCount = theReflectedInstances.count
		reflectedInstances = copyInstancesToBuffer(theReflectedInstances)
	}
	
	func getTiling(
	) -> (Int, MTLBuffer?, Int, MTLBuffer?) {
	
		return (plainInstanceCount, plainInstances, reflectedInstanceCount, reflectedInstances)
	}
	
	func getIdentityInstance(
	) -> (Int, MTLBuffer?, Int, MTLBuffer?) {
	
		return (1, identityInstance, 0, nil)
	}
	
	func makeTiling(
	) -> ([KaleidoTileTile], [KaleidoTileTile]) {	//	(plain instances, reflected instances)

		//	As we tile outwards, keep track of the region tiled so far
		//	by maintaining its perimeter as a circular doubly-linked list.
		//	Each PerimeterSegment represents a single edge of a single triangle.

		enum InstanceChirality {
			case positive	//	same as base triangle
			case negative	//	mirror image of base triangle
			
			func flipped() -> InstanceChirality {
				switch self {
				case .positive:  return .negative
				case .negative:  return .positive
				}
			}
		}

		//	To avoid a lot of traffic with the memory manager,
		//	we'll let PerimeterSegments be structs (not classes)
		//	and allocate ~10000 of them in one big block of memory.
		//	Each PerimeterSegment refers to it leftNeighbor and
		//	rightNeighbor using array indices, not class references.
		//
		struct PerimeterSegment {

			//	Where is the adjacent instance of the fundamental triangle?
			var placement: simd_double3x3

			//	Is the adjacent instance of the fundamental triangle
			//	positively or negatively oriented?
			var chirality: InstanceChirality

			//	Which side of the fundamental triangle does
			//	this PerimeterSegment represent?
			var side: Int	//	∈ {0, 1, 2}

			//	Viewed from within the tiled region looking outwards,
			//	this PerimeterSegment connects to a neighbor on its left
			//	and a neighbor on its right.
			var leftNeighbor: Int
			var rightNeighbor: Int

			//	"Free valence" means how many additional images
			//	of the fundamental triangle a given vertex may accommodate.
			//	For example, in the (2,3,7) triangle group,
			//	each image of the vertex of (rotational) order 3
			//	will be surrounded by a total of 3 + 3 = 6 images
			//	of the fundamental triangle (3 positively oriented
			//	and 3 negatively oriented).  If, at a given stage of the tiling,
			//	only 2 of those 6 potential images have been tiled,
			//	then that image of the vertex has valence 2
			//	and free valence 6 - 2 = 4.
			//
			//	What is the free valence of the vertex on the left
			//	(with "left" defined as above, viewing the PerimeterSegment
			//	from within the tiled region looking outwards) ?
			var leftFreeValence: Int

			//	If the tiling algorithm cannot continue past
			//	this PerimeterSegment without placing an image
			//	of the fundamental triangle beyond the allowable radius,
			//	mark this PerimeterSegment as inactive.
			//	An inactive PerimeterSegment remains part of the perimeter,
			//	even though the tiling algorithm does not attempt to push
			//	beyond it.  The tiling algorithm will terminate when
			//	the perimeter contains no more active PerimeterSegments.
			var isActive: Bool
		}
		
		//	In practice, the largest number of tile instances we'll
		//	ever need will be for the hyperbolic (2,3,7) tiling --
		//	provably the densest possible (p,q,r) reflection group,
		//	since (2,3,7) has the smallest fundamental-triangle area
		//	of any hyperbolic triangle group. At the tiling radius of
		//	9.0 (see coshHyperbolicTilingRadius above), (2,3,7) uses
		//	roughly 340,000 total instances (measured by simulating
		//	this exact algorithm). 500,000 leaves ~47% headroom above
		//	that measured worst case.
		let theMaxExpectedInstances = 500_000

		//	The initial triangle will have 3 PerimeterSegments.
		//	Thereafter every time we add a tile instance, we'll
		//	add 2 more PerimeterSegments (abandoning the used
		//	PerimeterSegment without recycling it).
		let theMaxPerimeterSegments = 2*theMaxExpectedInstances + 1
		
		//	Create the array of empty PerimeterSegments.
		var ps = Array(	//	ps = the perimeter segments
				repeating:
					PerimeterSegment(
						placement: matrix_identity_double3x3,
						chirality: .positive,
						side: 0,
						leftNeighbor: 0,
						rightNeighbor: 0,
						leftFreeValence: 0,
						isActive: true),
				count: theMaxPerimeterSegments)
		var theAllocatedSegmentCount = 0	//	number of segments allocated from our memory pool
		var theActiveSegmentCount = 0		//	number of active segments in the current perimeter

		//	As we create the tiling, store
		//	plain and reflected instances separately.
		//
		var thePlainInstances: [KaleidoTileTile] = []
		var theReflectedInstances: [KaleidoTileTile] = []
		
		//	For convenience
		let pqr = SIMD3<Int>(
					preparedBaseTriangle.reflectionGroup.p,
					preparedBaseTriangle.reflectionGroup.q,
					preparedBaseTriangle.reflectionGroup.r )
		let gen = preparedBaseTriangle.generators
		
		//	Start with an instance of the base triangle
		//	centered at the north pole.
		//
		thePlainInstances.append(matrix_identity_float3x3)
		ps[0] = PerimeterSegment(
					placement: matrix_identity_double3x3,
					chirality: .positive,
					side: 0,
					leftNeighbor: 1,
					rightNeighbor: 2,
					leftFreeValence: 2*pqr[2] - 1,
					isActive: true)
		ps[1] = PerimeterSegment(
					placement: matrix_identity_double3x3,
					chirality: .positive,
					side: 1,
					leftNeighbor: 2,
					rightNeighbor: 0,
					leftFreeValence: 2*pqr[0] - 1,
					isActive: true)
		ps[2] = PerimeterSegment(
					placement: matrix_identity_double3x3,
					chirality: .positive,
					side: 2,
					leftNeighbor: 0,
					rightNeighbor: 1,
					leftFreeValence: 2*pqr[1] - 1,
					isActive: true)
		theAllocatedSegmentCount += 3
		theActiveSegmentCount += 3
		
		//	In the Euclidean case, the tiling radius depends
		//	on the size of the base triangle.
		let theEuclideanTilingRadius: Double?
			= preparedBaseTriangle.geometry == .euclidean ?
				
					//	Start with view's outradius in intrinsic units...
					
					0.5 * characteristicViewSizeIU(geometry: .euclidean)
					
					//	...and then add in twice the base triangle's outradius,
					//
					//	once because the tiling may get translated
					//		by up to one base-triangle-outradius,
					//
					//	and then a second time because one of the view's corners
					//		might be sitting under a copy of the base triangle
					//		whose incenter sits up to one base-triangle-outradius away.
					
					+ 2.0 * preparedBaseTriangle.outradius
				:
				nil
	
		//	Now start going round and round the circular doubly-linked list
		//	of PerimeterSegments, adding more instances of the base triangle
		//	and pushing the perimeter outward.  Keep going as long as
		//	active PerimeterSegments remain.
		//
		var theSegment = 0
		while theActiveSegmentCount > 0 {
		
			if ps[theSegment].isActive {

				//	If we push outward across this segment,
				//	where will the next image of the fundamental triangle lie?
				let theNewPlacement = ps[theSegment].placement	//	right-to-left matrix action
									* gen[ ps[theSegment].side ]
				let theNewChirality = ps[theSegment].chirality.flipped()
				
				//	Does theNewPlacement fall within the tiling radius?
				if instanceFallsWithinTilingRadius(
					instanceIncenter: theNewPlacement[2],
					euclideanTilingRadius: theEuclideanTilingRadius) {

					//	Add a new triangle instance to the appropriate array.
					let theNewInstance = convertDouble3x3toFloat3x3(theNewPlacement)
					switch theNewChirality {
					case .positive:     thePlainInstances.append(theNewInstance)
					case .negative: theReflectedInstances.append(theNewInstance)
					}

					//	Push the perimeter across this image of the fundamental triangle.
					
					//	Have we got two more PerimeterSegments in our memory pool?
					//	If not, terminate the tiling immediately.
					if theAllocatedSegmentCount + 2 > theMaxPerimeterSegments {
						break	//	break from enclosing while-loop
					}

					//	Initialize the two new segments and install them
					//	into the perimeter in place of theSegment.

					let theNewLeftSegment  = theAllocatedSegmentCount + 0
					let theNewRightSegment = theAllocatedSegmentCount + 1
					theAllocatedSegmentCount += 2
					theActiveSegmentCount += (2 - 1)	//	two new segments added, one old one removed

					ps[theNewLeftSegment ].placement = theNewPlacement
					ps[theNewRightSegment].placement = theNewPlacement

					ps[theNewLeftSegment ].chirality = theNewChirality
					ps[theNewRightSegment].chirality = theNewChirality

					switch ps[theSegment].chirality {

					case .positive:
						ps[theNewLeftSegment ].side = (ps[theSegment].side + 1) % 3
						ps[theNewRightSegment].side = (ps[theSegment].side + 2) % 3
						
					case .negative:
						ps[theNewLeftSegment ].side = (ps[theSegment].side + 2) % 3
						ps[theNewRightSegment].side = (ps[theSegment].side + 1) % 3
						
					}

					ps[theNewLeftSegment].leftNeighbor  = ps[theSegment].leftNeighbor
					ps[theNewLeftSegment].rightNeighbor = theNewRightSegment
					ps[ps[theNewLeftSegment].leftNeighbor].rightNeighbor = theNewLeftSegment

					ps[theNewRightSegment].leftNeighbor  = theNewLeftSegment
					ps[theNewRightSegment].rightNeighbor = ps[theSegment].rightNeighbor
					ps[ps[theNewRightSegment].rightNeighbor].leftNeighbor = theNewRightSegment

					ps[theNewLeftSegment ].leftFreeValence	= ps[theSegment].leftFreeValence - 1
					ps[theNewRightSegment].leftFreeValence	= 2*pqr[ps[theSegment].side] - 1
					ps[ps[theNewRightSegment].rightNeighbor].leftFreeValence -= 1

					ps[theNewLeftSegment ].isActive = true
					ps[theNewRightSegment].isActive = true
				
					//	If a free valence reaches zero, the perimeter has folded in on itself.
					//	Remove the two "cancelling" edges from the perimeter.
					//
					//	Note #1.  The perimeter length (before pushing aross
					//	the current triangle image) should always be at least 3.
					//	It should (I think) be exactly 3 only when the tiling first begins
					//	and, in the spherical case, when the tilings ends
					//	at the antipodal triangle.  The latter case gets detected
					//	in the code immediately below, which checks whether
					//	the tiling folds in on both sides simultaneously.
					//
					//	Note #2.  In a more generic tiling you'd have to worry
					//	about the tiled region overlapping itself in less friendly ways.
					//	Fortunately for the (p,q,r) triangle groups the only cases
					//	that arise are simple fold-ins and the insertion of the
					//	antipodal triangle in the spherical triangle tilings.
					//
				
					//	Are both sides folding in?
					if ps[theNewLeftSegment].leftFreeValence == 0
					&& ps[ps[theNewRightSegment].rightNeighbor].leftFreeValence == 0 {
					
						//	If both sides are folding in simultaneously,
						//	this means (I think) that we've reached the antipodal triangle
						//	in a spherical tiling.  If this assumption is correct,
						//	we can stop here.
						
						break	//	break from enclosing while() loop
					}
				
					if ps[theNewLeftSegment].leftFreeValence == 0 {	//	Is the left side folding in?
					
						ps[theNewRightSegment].leftFreeValence
							= ps[theNewRightSegment].leftFreeValence
							+ ps[ps[theNewLeftSegment].leftNeighbor].leftFreeValence
							- 2*pqr[ps[theSegment].side]

						ps[theNewRightSegment].leftNeighbor = ps[ps[theNewLeftSegment].leftNeighbor].leftNeighbor
						ps[ps[theNewRightSegment].leftNeighbor].rightNeighbor = theNewRightSegment
					
						if ps[theNewLeftSegment ].isActive {					//	always true
							theActiveSegmentCount -= 1
						}
						if ps[ps[theNewLeftSegment ].leftNeighbor].isActive {	//	probably true
							theActiveSegmentCount -= 1
						}
					
						//	On the next pass through the loop,
						//	examine the segment to the left of the fold-in.
						theSegment = ps[theNewRightSegment].leftNeighbor

					} else if ps[ps[theNewRightSegment].rightNeighbor].leftFreeValence == 0 {
								//	Is the right side folding in?
						
						ps[ps[ps[theNewRightSegment].rightNeighbor].rightNeighbor].leftFreeValence
							= ps[ps[ps[theNewRightSegment].rightNeighbor].rightNeighbor].leftFreeValence
							+ ps[theNewRightSegment].leftFreeValence
							- 2*pqr[ps[theSegment].side]
					
						ps[theNewLeftSegment].rightNeighbor = ps[ps[theNewRightSegment].rightNeighbor].rightNeighbor
						ps[ps[theNewLeftSegment].rightNeighbor].leftNeighbor = theNewLeftSegment

						if ps[theNewRightSegment].isActive {					//	always true
							theActiveSegmentCount -= 1
						}
						if ps[ps[theNewRightSegment].rightNeighbor].isActive {	//	probably true
							theActiveSegmentCount -= 1
						}
					
						//	On the next pass through the loop,
						//	examine the segment to the left of theNewLeftSegment.
						theSegment = ps[theNewLeftSegment].leftNeighbor

					} else {	//	neither side is folding in
					
						//	On the next pass through the loop,
						//	examine the next segment to the left.
						theSegment = ps[theNewLeftSegment].leftNeighbor
					}
				
				} else {	//	theNewPlacement lies beyond the tiling radius
				
					//	We've reach the edge of the desired tiling.
					//	Deactivate the segment and move on.
					
					ps[theSegment].isActive = false
					theActiveSegmentCount -= 1
					theSegment = ps[theSegment].leftNeighbor
				}

			} else {	// the segment is inactive
			
				//	Move on to the next segment.
				theSegment = ps[theSegment].leftNeighbor
			}
		}
		
		func instanceFallsWithinTilingRadius(
			instanceIncenter: SIMD3<Double>,
			euclideanTilingRadius: Double?	//	used only for Euclidean tilings
		) -> Bool {
			
			switch preparedBaseTriangle.geometry {
			
			case .spherical:
			
				//	In spherical geometry, every instance is close enough.
				return true
				
			case .euclidean:
			
				guard let theTilingRadius = euclideanTilingRadius else {
					assertionFailure("euclideanTilingRadius is nil in instanceFallsWithinTilingRadius()")
					return false
				}

				//	Accept the instance iff the instanceIncenter
				//	lies within a disk of radius theTilingRadius.
				return
					instanceIncenter.x * instanceIncenter.x
				  + instanceIncenter.y * instanceIncenter.y
				  < theTilingRadius * theTilingRadius
				
			case .hyperbolic:
							
				//	Accept the instance iff the instanceIncenter
				//	lies within the hyperbolic tiling radius
				//	(see coshHyperbolicTilingRadius above).
				return instanceIncenter.z < coshHyperbolicTilingRadius
			}
		}

		return (thePlainInstances, theReflectedInstances)
	}

	func copyInstancesToBuffer(
		_ tileInstances: [KaleidoTileTile]
	) -> MTLBuffer {

		precondition(
			!tileInstances.isEmpty,
			"copyInstancesToBuffer() received empty tileInstances array")

		guard let theInstanceBuffer = device.makeBuffer(
					bytes: tileInstances,
					length: tileInstances.count * MemoryLayout<KaleidoTileTile>.stride,
					options: [])
		else {
			preconditionFailure("Couldn't create theInstanceBuffer")
		}
		
		return theInstanceBuffer
	}
}
