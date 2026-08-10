//  KaleidoTileGestures.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import SwiftUI


let maxRotationalSpeed: Double = 4.0	//	radians/second
let minRotationalSpeed: Double = 0.1	//	radians/second, to suppress any small unintended motions

let maxTranslationalSpeed: Double = 4.0	//	radians/second, or equivalent
let minTranslationalSpeed: Double = 0.1	//	radians/second, to suppress any small unintended motions
let maxFrameθ: Double = maxTranslationalSpeed * gFramePeriod
let minFrameθ: Double = minTranslationalSpeed * gFramePeriod

let maxTriplePointSpeed: Double = 2.0	//	seconds⁻¹
let minTriplePointSpeed: Double = 0.1	//	seconds⁻¹, to suppress any small unintended motions
let maxTriplePointIncrementLength: Double = maxTriplePointSpeed * gFramePeriod
let minTriplePointIncrementLength: Double = minTriplePointSpeed * gFramePeriod


// MARK: -
// MARK: Drag gesture (main view)

func kaleidoTileDragGesture(
	modelData: KaleidoTileModel,
	viewSize: CGSize,
	inertia: Bool,
	previousPoint: GestureState<SIMD3<Double>?>
		//	on unit-radius sphere, Euclidean plane, or hyperboloid
) -> some Gesture {

	let theGeometry = modelData.itsBaseTriangle.geometry

	let theDragGesture = DragGesture()
	.updating(previousPoint) { value, thePreviousPoint, transaction in
		
		//	Suppress the usual per-frame increment
		//	while the user is manually translating the tiling.
		modelData.itsIncrement = nil
		
		//	On the first call to updating() during a given drag,
		//	thePreviousPoint will be nil and we'll use the drag's
		//	startLocation instead. Thereafter we'll store the point
		//	from one call for use in the next.
		//
		let p₀ = thePreviousPoint ??
					mapToSurface(
						touchPoint: value.startLocation,
						viewSize: viewSize,
						geometry: theGeometry)

		let p₁ = mapToSurface(
					touchPoint: value.location,
					viewSize: viewSize,
					geometry: theGeometry)

		let (theAxis, θ) = parallelTransportAxisAndDistance(
							p₀: p₀,
							p₁: p₁,
							geometry: theGeometry)

		let theIncrement = translationAlongGeodesic(
							axis: theAxis,
							θ: θ,
							geometry: theGeometry)

		modelData.applyOrientationIncrement(theIncrement)

		//	Update thePreviousPoint for use in the next call to updating().
		thePreviousPoint = p₁
	}
	.onEnded() {value in
	
		//	Caution:  This onEnded callback gets called
		//	when the gesture ends normally, but not when,
		//	say, a DragGesture gets interrupted when
		//	the user places a second finger on the display.

		if inertia {
		
			let theTouchPoint₀ = value.location
			let theTouchPoint₁ = CGPoint(
				x: value.location.x + gFramePeriod * value.velocity.width,
				y: value.location.y + gFramePeriod * value.velocity.height)

			let p₀ = mapToSurface(
						touchPoint: theTouchPoint₀,
						viewSize: viewSize,
						geometry: theGeometry)

			let p₁ = mapToSurface(
						touchPoint: theTouchPoint₁,
						viewSize: viewSize,
						geometry: theGeometry)

			let (theAxis, θ) = parallelTransportAxisAndDistance(
										p₀: p₀,
										p₁: p₁,
										geometry: theGeometry)

			let theClampedθ = min(θ, maxFrameθ)

			//	If the user tries to stop the motion at the end of a drag,
			//	but leaves some some residual motion ( θ < minFrameθ ),
			//	set theIncrement to nil to stop the motion entirely.
			//
			let theIncrement = theClampedθ > minFrameθ ?
								translationAlongGeodesic(
									axis: theAxis,
									θ: theClampedθ,
									geometry: theGeometry) :
								nil
			
			modelData.itsIncrement = theIncrement

		} else { // inertia == false

			modelData.itsIncrement = nil
		
			if gGetScreenshotOrientations {
				print("itsOrientation = \(modelData.itsOrientation)")
			}
		}
	}
	
	return theDragGesture
}

func mapToSurface(
	touchPoint: CGPoint,	//	0 ≤ touchPoint.x|y ≤ viewSize.width|height
	viewSize: CGSize,
	geometry: GeometryType
) -> SIMD3<Double> {

	precondition(
		viewSize.width > 0.0 && viewSize.height > 0.0,
		"mapToSurface() received viewSize of non-positive width or height")

	//	Shift the coordinates to place the origin at the center of the view.
	var x = touchPoint.x - 0.5 * viewSize.width
	var y = touchPoint.y - 0.5 * viewSize.height

	//	Flip from iOS's Y-down coordinates
	//	to Metal's Y-up coordinates.
	y = -y

	//	Convert the coordinates to intrinsic units (IU).
	let theIntrinsicUnitsPerPixelOrPoint = intrinsicUnitsPerPixelOrPoint(
												viewWidth: viewSize.width,
												viewHeight: viewSize.height,
												geometry: geometry)
	x *= theIntrinsicUnitsPerPixelOrPoint
	y *= theIntrinsicUnitsPerPixelOrPoint
	
	let p = mapOrthogonallyOntoSurface(x: x, y: y, geometry: geometry)
		
	return p
}

func parallelTransportAxisAndDistance(
	p₀: SIMD3<Double>,	//	unit vector
	p₁: SIMD3<Double>,	//	unit vector
	geometry: GeometryType
) -> (SIMD3<Double>, Double)	//	(the axis, the angle) that parallel transports p₀ to p₁.
								//	The axis has unit length, relative to the appropriate metric.
								//	The "angle" is the distance along
								//	the unit sphere, Euclidean plane or hyperbolic plane.
								//	The angle is always non-negative.
{
	let theAxis: SIMD3<Double>
	let θ: Double
	switch geometry {
	
	case .spherical:
	
		//	Take a cross product to get the axis of rotation.

		let theCrossProduct = SIMD3<Double>(
								p₀.y * p₁.z  -  p₀.z * p₁.y,
								p₀.z * p₁.x  -  p₀.x * p₁.z,
								p₀.x * p₁.y  -  p₀.y * p₁.x )

		let theCrossProductLength = sqrt( theCrossProduct.x * theCrossProduct.x
										+ theCrossProduct.y * theCrossProduct.y
										+ theCrossProduct.z * theCrossProduct.z )
		
		if theCrossProductLength > 0.0 {
		
			//	Normalize theCrossProduct to unit length
			//	to get a normalized axis of rotation.
			theAxis = theCrossProduct / theCrossProductLength

			//	p₀ and p₁ are both unit vectors, so
			//
			//		theCrossProductLength = |p₀|·|p₁|·sin(θ)
			//							  = sin(θ)
			//
			//		Note:  Using theCosine = p₀·p₁
			//		could be less numerically precise.
			//
			let theSine = theCrossProductLength
			let theSafeSine = min(theSine, 1.0)	//	guard against theSine = 1.0000000000001
			θ = asin(theSafeSine)

		} else {	//	theCrossProductLength = 0.0
		
			//	p₀ and p₁ are equal (or collinear) and the motion is the identity.
			//	We can pick an arbitrary axis and report zero distance.
			//
			//		Note #1:  The touch input values are discrete,
			//		so we shouldn't have to worry about including
			//		any sort of tolerance here.
			//
			//		Note #2:  We're unlikley to ever receive p₁ = -p₀.
			//
			theAxis = SIMD3<Double>(1.0, 0.0, 0.0)
			θ = 0.0
		}
		
	case .euclidean:
	
		let Δx = p₁.x - p₀.x
		let Δy = p₁.y - p₀.y
		
		let theTranslationDistance = sqrt(Δx*Δx + Δy*Δy)
		
		if theTranslationDistance > 0.0 {
		
			theAxis = SIMD3<Double>(
						-Δy / theTranslationDistance,
						+Δx / theTranslationDistance,
						0.0)

			θ = theTranslationDistance
		
		} else {	//	theTranslationDistance = 0.0
		
			theAxis = SIMD3<Double>(1.0, 0.0, 0.0)
			θ = 0.0
		}
		
	case .hyperbolic:

		//	Take a cross product to get the axis of rotation.
		//
		//	Conceptually,
		//		the hyperbolic cross product A×B of two vectors A and B
		//		is defined to be the unique vector that
		//
		//			1. is orthogonal to both A and B,
		//
		//			2. has length equal to |A||B|sinh(θ),
		//				where θ is the "angle" between A and B
		//				("angle" = distance along unit hyperboloid)
		//				(hmmm... but what about non-timelike vectors?),
		//				and
		//
		//			3. satisfies the usual left/right-hand rule,
		//				meaning that if you are viewing your coordinate system
		//				as left-handed (resp right-handed) then the triple
		//				(A, B, A × B) is also left-handed (resp right-handed).
		//
		//	Computationally,
		//		we may use the usual Euclidean-metric formula for the cross product,
		//		but with the last component negated to account for the Minkowksi space metric.
		//		That is, we may compute
		//
		//			A×B = ( A₁B₂ - A₂B₁,
		//				    A₂B₀ - A₀B₂,
		//				  -(A₀B₁ - A₁B₀) )
		//
		//		It's then straightforward to check that this formula
		//		satisfies the three parts of the conceptual definition:
		//
		//		1.
		//			<A, A×B> = A₀(A₁B₂ - A₂B₁) + A₁(A₂B₀ - A₀B₂) + A₂(A₀B₁ - A₁B₀)
		//					 = A₀A₁B₂ - A₀A₂B₁ + A₁A₂B₀ - A₁A₀B₂ + A₂A₀B₁ - A₂A₁B₀
		//					 = 0
		//
		//			<B, A×B> = … = 0
		//
		//		2.
		//		  -------------------------------
		//			|A×B|² = <A×B, A×B>
		//				   =
		//					 (A₁B₂ - A₂B₁)(A₁B₂ - A₂B₁)
		//					 (A₂B₀ - A₀B₂)(A₂B₀ - A₀B₂)
		//					-(A₀B₁ - A₁B₀)(A₀B₁ - A₁B₀)
		//				   =
		//					 A₁B₂A₁B₂ - 2A₂B₁A₁B₂ + A₂B₁A₂B₁
		//					 A₂B₀A₂B₀ - 2A₀B₂A₂B₀ + A₀B₂A₀B₂
		//					-A₀B₁A₀B₁ + 2A₁B₀A₀B₁ - A₁B₀A₁B₀)
		//		  -------------------------------
		//			|A|²|B|²sinh²(θ)
		//		  = |A|²|B|²(cosh²(θ) - 1)
		//		  = |A|²|B|²cosh²(θ) - |A|²|B|²
		//		  = <A,B>² - <A,A><B,B>
		//		  =
		//		      (A₀B₀ + A₁B₁ - A₂B₂)(A₀B₀ + A₁B₁ - A₂B₂)
		//		    - (A₀A₀ + A₁A₁ - A₂A₂)(B₀B₀ + B₁B₁ - B₂B₂)
		//		  =
		//			  [
		//				 A₀B₀A₀B₀ + A₁B₁A₀B₀ - A₂B₂A₀B₀
		//				 A₀B₀A₁B₁ + A₁B₁A₁B₁ - A₂B₂A₁B₁
		//			   - A₀B₀A₂B₂ - A₁B₁A₂B₂ + A₂B₂A₂B₂
		//			  ]
		//			-
		//			  [
		//				 A₀A₀B₀B₀ + A₁A₁B₀B₀ - A₂A₂B₀B₀
		//				 A₀A₀B₁B₁ + A₁A₁B₁B₁ - A₂A₂B₁B₁
		//			   - A₀A₀B₂B₂ - A₁A₁B₂B₂ + A₂A₂B₂B₂
		//			  ]
		//		  =
		//			 A₁B₂A₁B₂ - 2A₂B₁A₁B₂ + A₂B₁A₂B₁
		//			 A₂B₀A₂B₀ - 2A₀B₂A₂B₀ + A₀B₂A₀B₂
		//			-A₀B₁A₀B₁ + 2A₁B₀A₀B₁ - A₁B₀A₁B₀)
		//		  -------------------------------
		//		 => |A×B|² = |A|²|B|²sinh²(θ)
		//
		//		3.
		//		  As soon as we verify that the left/right-hand rule
		//		  is satisfied for one arbitrary example, such as
		//
		//			 A  = (  0,   0,     1  )
		//			 B  = (  0,  5/12, 13/12)
		//			A×B = (-5/12, 0,     0  )
		//
		//		  then by continuity we know it's satisfied for all
		//		  "positive timelike" vectors A and B (because it
		//		  can't suddenly change direction).
		//
		
		let theCrossProduct = SIMD3<Double>(
								  p₀.y * p₁.z  -  p₀.z * p₁.y,
								  p₀.z * p₁.x  -  p₀.x * p₁.z,
								-(p₀.x * p₁.y  -  p₀.y * p₁.x) )
								
		let theCrossProductLengthSquared = theCrossProduct.x * theCrossProduct.x
										 + theCrossProduct.y * theCrossProduct.y
										 - theCrossProduct.z * theCrossProduct.z
		
		//	Because p₀ and p₁ are timelike, the cross product p₀×p₁
		//	should be spacelike.  So its squared length should be positive
		//	whenever p₀ and p₁ are non-collinear.
		//
		if theCrossProductLengthSquared > 0.0 {

			let theCrossProductLength = sqrt(theCrossProductLengthSquared)

			//	Normalize theCrossProduct to unit length
			//	to get a normalized axis of rotation.
			theAxis = theCrossProduct / theCrossProductLength

			//	p₀ and p₁ are both unit vectors, so
			//
			//		theCrossProductLength = |p₀|·|p₁|·sinh(θ)
			//							  = sinh(θ)
			//
			//		Note:  Using theCosh = -<p₀,p₁>
			//		could be less numerically precise.
			//
			let theSinh = theCrossProductLength
			θ = asinh(theSinh)

		} else {	//	theCrossProductLengthSquared = 0.0  (should never be negative)
		
			//	p₀ and p₁ are equal (or collinear) and the motion is the identity.
			//	We can pick an arbitrary axis and report zero distance.
			//
			//		Note:  The touch input values are discrete,
			//		so we shouldn't have to worry about including
			//		any sort of tolerance here.
			//
			theAxis = SIMD3<Double>(1.0, 0.0, 0.0)
			θ = 0.0
		}
	}
	
	return (theAxis, θ)
}

func translationAlongGeodesic(
	axis: SIMD3<Double>,	//	unit length, relative to the appropriate metric
	θ: Double,				//	distance along the unit sphere, Euclidean plane or hyperbolic plane
	geometry: GeometryType
) -> simd_double3x3 {

	let u = axis	//	for brevity

	let theTranslation: simd_double3x3
	switch geometry {
	
	case .spherical:
		
		//	Rodrigues's rotation formula
		//
		//	First consider the task of rotating an arbitrary vector v
		//	through an angle θ about the axis u.  (Don't think
		//	about matrices just yet!)  The vector v naturally decomposes
		//	into components parallel and perpendicular to u:
		//
		//		v = v∥ + v⟂
		//
		//	The component v∥ is easily obtained as
		//
		//		v∥ = (v·u)u
		//
		//	(but we won't need to use that fact).
		//
		//	For v⟂ we must resist the temptation to write v⟂ = v - v∥,
		//	and instead note that
		//
		//		u × v		has the same magnitude as v⟂
		//						but is rotated 90° around u
		//
		//		u × (u × v)	has the same magnitude as v⟂
		//						but is rotated 180° around u
		//
		//	and thus
		//
		//		v⟂ = - u × (u × v)
		//
		//	The rotation through an angle θ about the axis u maps
		//
		//		v∥	↦	v∥
		//
		//		v⟂	↦	cos(θ) v⟂  +  sin(θ) u × v
		//
		//	Hence
		//
		//		v  =  v∥  +  v⟂
		//		   ↦  v∥  +  cos(θ) v⟂  +  sin(θ) u × v
		//		   =  (v - v⟂)  +  cos(θ) v⟂  +  sin(θ) u × v
		//		   =  v  +  (cos(θ) - 1) v⟂  +  sin(θ) u × v
		//		   =  v  +  (cos(θ) - 1)( - u × (u × v) )  +  sin(θ) u × v
		//		   =  v  +  (1 - cos(θ))( u × (u × v) )  +  sin(θ) u × v
		//
		//	My source for these ideas was
		//
		//		en.wikipedia.org/wiki/Rodrigues'_rotation_formula
		//
		//	which includes a nice figure illustrating these relationships.

		//	The operation of "taking a cross product with u" is linear,
		//	and may be expressed as the following matrix.  That is,
		//
		//		u × v = k v		(right-to-left matrix action)
		//
		let k = simd_double3x3(
			SIMD3<Double>(  0.0,   u[2], -u[1] ),
			SIMD3<Double>( -u[2],  0.0,   u[0] ),
			SIMD3<Double>(  u[1], -u[0],  0.0  )
		)

		//	To take the cross product with u twice in a row,
		//	square the matrix k.  That is,
		//
		//		u × (u × v) = k² v
		//
		let kk = k * k

		//	Applying the matrices k and k² converts the vector formula
		//
		//		v  ↦  v  +  (1 - cos(θ))( u × (u × v) )  +  sin(θ) u × v
		//
		//	into a matrix formula
		//
		//		v  ↦  v + (1 - cos(θ)) k² v + sin(θ) k v
		//		   =  ( I + (1 - cos(θ)) k² + sin(θ) k ) v
		//
		//	Evaluate that matrix
		//
		//		I + (1 - cos(θ)) k² + sin(θ) k
		//
		theTranslation = matrix_identity_double3x3
					   + (1.0 - cos(θ)) * kk
					   + sin(θ) * k

	case .euclidean:

		theTranslation = simd_double3x3(
			SIMD3<Double>(    1.0,       0.0,    0.0 ),
			SIMD3<Double>(    0.0,       1.0,    0.0 ),
			SIMD3<Double>( u[1] * θ, -u[0] * θ , 1.0 )
		)

	case .hyperbolic:

		//	Rodrigues's rotation formula
		//
		//		Caution:  In parallelTransportAxisAndDistance()'s
		//		conceptual definition of the hyperbolic cross product,
		//		the definition of the angle θ is a bit dicey if the two vectors
		//		aren't both timelike.  Let's hope the computational formula
		//		remains invariant under Lorentz transformations, as it should,
		//		given that it's invariant when both vectors are timelike.
		//
		//	Let's try to adapt Rodrigues's rotation formula to the hyperbolic case.
		//	As in the spherical case (see above) a given vector v naturally
		//	decomposes into components parallel and perpendicular to u:
		//
		//		v = v∥ + v⟂
		//
		//	For v⟂ the results are analogous to what we got in the spherical case,
		//	except that u × (u × v) now gives v⟂ directly, rather than its opposite.
		//	(Proof:  Do the computation in a coordinate system where u is parallel
		//	to the x-axis and v⟂ is parallel to the z-axis, and note the effect
		//	of the minus sign in the formula for the hyperbolic cross product.)
		//
		//		u × v		has the same magnitude as v⟂
		//						but is orthogonal to the uv-plane
		//
		//		u × (u × v)	has the same magnitude and direction as v⟂
		//
		//	That is
		//
		//		v⟂ = u × (u × v)
		//
		//	The translation through an "angle" θ about the "axis" u maps
		//
		//		v∥	↦	v∥
		//
		//		v⟂	↦	cosh(θ) v⟂  +  sinh(θ) u × v
		//
		//	Hence
		//
		//		v  =  v∥  +  v⟂
		//		   ↦  v∥  +  cosh(θ) v⟂  +  sinh(θ) u × v
		//		   =  (v - v⟂)  +  cosh(θ) v⟂  +  sinh(θ) u × v
		//		   =  v  +  (cosh(θ) - 1) v⟂  +  sinh(θ) u × v
		//		   =  v  +  (cosh(θ) - 1)( u × (u × v) )  +  sinh(θ) u × v
		//

		//	As in the spherical case, the operation of
		//	"taking a cross product with u" is linear,
		//	and may be expressed as a matrix:
		//
		//		u × v = k v		(right-to-left matrix action)
		//
		//	The only difference is that the last column is now
		//	the negative of what it was in the spherical case, to account
		//	for the negation in the hyperbolic cross product's last component.
		//
		let k = simd_double3x3(
			SIMD3<Double>(  0.0,   u[2], +u[1] ),
			SIMD3<Double>( -u[2],  0.0,  -u[0] ),
			SIMD3<Double>(  u[1], -u[0],  0.0  )
		)

		//	To take the cross product with u twice in a row,
		//	square the matrix k.  That is,
		//
		//		u × (u × v) = k² v
		//
		let kk = k * k

		//	Applying the matrices k and k² converts the vector formula
		//
		//		v  ↦  v  +  (1 - cos(θ))( u × (u × v) )  +  sin(θ) u × v
		//
		//	into a matrix formula
		//
		//		v  ↦  v + (cosh(θ) - 1) k² v + sinh(θ) k v
		//		   =  ( I + (cosh(θ) - 1) k² + sinh(θ) k ) v
		//
		//	Evaluate that matrix
		//
		//		I + (cosh(θ) - 1) k² + sinh(θ)
		//
		theTranslation = matrix_identity_double3x3
					   + (cosh(θ) - 1) * kk
					   + sinh(θ) * k
	}

	return theTranslation
}

// MARK: -
// MARK: Rotation gesture (main view)

func kaleidoTileRotateGesture(
	modelData: KaleidoTileModel,
	previousAngle: GestureState<Double>
) -> some Gesture {

	//	When running on macOS (as a "designed for iPadOS" app)
	//	rotations will be recognized iff
	//
	//		Settings > Trackpad > Scroll & Zoom > Rotate
	//
	//	is enabled.  Fortunately that seems to be the default setting.
	
	let theRotateGesture = RotateGesture(minimumAngleDelta: .zero)
	.updating(previousAngle) { value, thePreviousAngle, transaction in

		//	Suppress the usual per-frame increment
		//	while the user is manually rotating the figure.
		modelData.itsIncrement = nil

		let theNewAngle = value.rotation.radians
		
		//	RotateGesture() sometimes returns theNewAngle = NaN. Ouch!
		if theNewAngle.isNaN {
			return
		}

		var Δθ = theNewAngle - thePreviousAngle

		//	Avoid discontinuous jumps by 2π ± ε
		if Δθ > π { Δθ -= 2.0 * π }
		if Δθ < π { Δθ += 2.0 * π }

		//	A rotation about the z-axis is the same in all three geometries.
		let theIncrementAsQuaternion = simd_quatd(angle: Δθ, axis: SIMD3<Double>(0.0, 0.0, -1.0))
		let theIncrementAsMatrix = simd_double3x3(theIncrementAsQuaternion)
		modelData.applyOrientationIncrement(theIncrementAsMatrix)

		//	Update thePreviousAngle for next time.
		thePreviousAngle = theNewAngle
	}
	.onEnded() { _ in

		//	Trying to decide whether the user wants the tiling
		//	to keep rotating or not at the end of the gesture is trickier
		//	than it seems. So let's just stop rotating, no matter what.
		//	The 2-finger rotation is an awkward gesture for the user
		//	to perform in any case. The 1-finger rotation -- with
		//	the user's finger near the edge of the display -- is
		//	an easier way to rotate a spherical tiling about an axis
		//	orthogonal to the display.
		//
		modelData.itsIncrement = nil	//	redundant but clear
	}
	
	return theRotateGesture
}


// MARK: -
// MARK: Triple point drag gesture

func triplePointDragGesture(
	modelData: KaleidoTileModel,
	viewSize: CGSize,
	inertia: Bool,
	archimedeanSolidName: Binding<LocalizedStringKey?>
) -> some Gesture {

	let theGeometry = modelData.itsBaseTriangle.geometry
	let theNDCPlacement = modelData.itsBaseTriangle.ndcPlacement
	let theBarycentricBasis = modelData.itsBaseTriangle.barycentricBasis

	let theDragGesture = DragGesture(minimumDistance: 0.0)
	.onChanged() { value in
		
		//	Suppress the usual per-frame increment
		//	while the user is manually moving the triple point.
		modelData.itsTriplePointIncrement = nil

#if os(iOS)
		//	iOS is happy to update the archimedeanSolidName immediately,
		//	with no need to enclose it in a Task.
		archimedeanSolidName.wrappedValue = nil
#endif
#if os(macOS)
		//	On macOS an immediate call to
		//		archimedeanSolidName.wrappedValue = nil
		//	produces a runtime error
		//
		//		Modifying state during view update,
		//		this will cause undefined behavior.
		//
		//	Maybe iOS and macOS handle the updating() callback differently?
		//
		//		Caution: By enclosing this code in a Task,
		//		we run the risk that the archimedeanSolidName
		//		could get set to nil after the onEnded() callback
		//		has returned, in which case onEnded()'s possibly
		//		non-nil Archimedean name could get overwritten
		//		with this delayed nil value.
		//
		Task() {
			archimedeanSolidName.wrappedValue = nil
		}
#endif

		let theTriplePoint = mapToClampedBarycentricCoords(
								touchPoint: value.location,
								viewSize: viewSize,
								geometry: theGeometry,
								ndcPlacement: theNDCPlacement,
								barycentricBasis: theBarycentricBasis)
			
		modelData.itsTriplePoint = theTriplePoint

		modelData.changeCount += 1
		
	}
	.onEnded() { value in
	
		//	Caution:  This onEnded callback gets called
		//	when the gesture ends normally, but not
		//	if the gesture gets canceled for any reason.

		let theSnapToArchimedeanTolerance = 0.125
		if modelData.itsSnapToArchimedeanSolids,
		   let theArchimedeanPoint
				= nearbyArchimedeanPoint(
					modelData.itsTriplePoint,
					geometry: modelData.itsBaseTriangle.geometry,
					barycentricBasis: modelData.itsBaseTriangle.barycentricBasis,
					scale: modelData.itsBaseTriangle.ndcPlacement.scale,
					tolerance: theSnapToArchimedeanTolerance)
		{
		   
			modelData.itsTriplePoint = theArchimedeanPoint.triplePoint
			modelData.itsTriplePointIncrement = nil

			//	theArchimedeanName will be non-nil for
			//	the traditional Platonic and Archimedian solids,
			//	but not for any other regular or semi-regular tilings.
			let theArchimedeanName = archimedeanName(modelData: modelData)
			archimedeanSolidName.wrappedValue = theArchimedeanName
			
			enqueueSoundRequest("click.wav")
			
		} else {	//	didn't snap to an Archimedean solid

			//	If you were pushing a child on a bicycle in real life,
			//	just before you let go you'd give the bicycle an extra shove.
			//	Perhaps based on this same subconscious habit,
			//	when people drag the triple point, they tend to give it
			//	an "extra shove" before letting go, with the result that
			//	the triple move moves faster after than let go than it was
			//	moving for most of the time they had their finger down on it.
			//	To compensate, let's halve theFrameIncrement.
			//
			let Δt = 0.5 * gFramePeriod

			let theTouchPoint₀ = value.location
			let theTouchPoint₁ = CGPoint(
				x: value.location.x + Δt * value.velocity.width,
				y: value.location.y + Δt * value.velocity.height)

			let theBarycentricPoint₀ = mapToClampedBarycentricCoords(
										touchPoint: theTouchPoint₀,
										viewSize: viewSize,
										geometry: theGeometry,
										ndcPlacement: theNDCPlacement,
										barycentricBasis: theBarycentricBasis)
			let theBarycentricPoint₁ = mapToClampedBarycentricCoords(
										touchPoint: theTouchPoint₁,
										viewSize: viewSize,
										geometry: theGeometry,
										ndcPlacement: theNDCPlacement,
										barycentricBasis: theBarycentricBasis)
		
			modelData.itsTriplePoint = theBarycentricPoint₀
			
			var theIncrement: TriplePointIncrement
				= theBarycentricPoint₁ - theBarycentricPoint₀
			var theDistance = length(theIncrement)
			if theDistance > maxTriplePointIncrementLength {
				let theFactor = maxTriplePointIncrementLength / theDistance
				theIncrement *= theFactor
				theDistance *= theFactor
			}
			let theNonMinisculeIncrement =
				theDistance > minTriplePointIncrementLength ? theIncrement : nil

			if inertia {
				modelData.itsTriplePointIncrement = theNonMinisculeIncrement
			} else {
				modelData.itsTriplePointIncrement = nil
			}

			archimedeanSolidName.wrappedValue = nil
		}

		modelData.changeCount += 1
	}
	
	return theDragGesture
}

func mapToClampedBarycentricCoords(
	touchPoint: CGPoint,	//	0 ≤ touchPoint.x|y ≤ viewSize.width|height
	viewSize: CGSize,
	geometry: GeometryType,
	ndcPlacement: NDCPlacement,
	barycentricBasis: simd_double3x3
) -> TriplePoint {

	precondition(
		viewSize.width > 0.0 && viewSize.height > 0.0,
		"mapToBarycentricCoords() received viewSize of non-positive width or height")

	//	Rescale to 0.0 ... 1.0 coordinates
	var x = touchPoint.x / viewSize.width
	var y = touchPoint.y / viewSize.height
	
	//	Convert to normalized device coordinates (NDC),
	//	which run from -1.0 ... +1.0 in each direction.
	x = 2.0*x - 1.0
	y = 2.0*y - 1.0

	//	Flip from iOS's Y-down coordinates
	//	to Metal's Y-up coordinates.
	y = -y

	//	Convert from normalized device coordinates (NDC)
	//	to the x and y coordinates of the touch point
	//	in the tiling's ambient space.  The z coordinate
	//	is undefined and unnecessary, because we're
	//	about to project the touch point orthogonally
	//	onto the tiled surface.
	x -= ndcPlacement.Δx
	y -= ndcPlacement.Δy
	if ndcPlacement.scale > 0.0 {
		x /= ndcPlacement.scale
		y /= ndcPlacement.scale
	} else {
		assertionFailure("ndcPlacement.scale is non-positive")
	}
	
	let thePointOnSurface = mapOrthogonallyOntoSurface(
								x: x,
								y: y,
								geometry: geometry,
								mapToNorthernHemisphere: true)

	let theTransformation = barycentricBasis.inverse
	let theRawBarycentricPoint = theTransformation * thePointOnSurface	//	right-to-left matrix action
	let theClampedBarycentricPoint = max(.zero, theRawBarycentricPoint)
	let theSum = reduce_add(theClampedBarycentricPoint)

	//	We must normalize the sum of the barycentric coordinates to 1.0.
	//	It seems unlikely theSum would be zero, but let's check it anyhow.
	let theBarycentricPoint = theSum > 0.0 ?
								theClampedBarycentricPoint / theSum :
								SIMD3<Double>(1.0/3.0, 1.0/3.0, 1.0/3.0)
	
	return theBarycentricPoint
}

enum ArchimedeanPoint: CaseIterable {
	
	//	This enum serves to enumerate the TriplePoints
	//	corresponding to Archimedean tilings.
	//	For the groups △(2,3,3), △(2,3,4) and △(2,3,5)
	//	it also provides the names of the corresponding
	//	classical polyhedra.

	case vertex0
	case vertex1
	case vertex2
	case edgepoint0	//	where the angle bisector at vertex 0 meets the opposite edge
	case edgepoint1
	case edgepoint2
	case center		//	the incenter, where the three angle bisectors meet

	var triplePoint: TriplePoint {
		switch self {
		case .vertex0:		return TriplePoint(1.0, 0.0, 0.0)
		case .vertex1:		return TriplePoint(0.0, 1.0, 0.0)
		case .vertex2:		return TriplePoint(0.0, 0.0, 1.0)
		case .edgepoint0:	return TriplePoint(0.0, 0.5, 0.5)
		case .edgepoint1:	return TriplePoint(0.5, 0.0, 0.5)
		case .edgepoint2:	return TriplePoint(0.5, 0.5, 0.0)
		case .center:		return TriplePoint(1.0/3.0, 1.0/3.0, 1.0/3.0)
		}
	}
	
	var name233: LocalizedStringKey {
		switch self {
		case .vertex0:		return "octahedron"
		case .vertex1:		return "tetrahedron"
		case .vertex2:		return "tetrahedron"
		case .edgepoint0:	return "cuboctahedron"
		case .edgepoint1:	return "truncated tetrahedron"
		case .edgepoint2:	return "truncated tetrahedron"
		case .center:		return "truncated octahedron"
		}
	}
	
	var name234: LocalizedStringKey {
		switch self {
		case .vertex0:		return "cuboctahedron"
		case .vertex1:		return "cube"
		case .vertex2:		return "octahedron"
		case .edgepoint0:	return "rhombicuboctahedron"
		case .edgepoint1:	return "truncated octahedron"
		case .edgepoint2:	return "truncated cube"
		case .center:		return "truncated cuboctahedron"
		}
	}
	
	var name235: LocalizedStringKey {
		switch self {
		case .vertex0:		return "icosidodecahedron"
		case .vertex1:		return "dodecahedron"
		case .vertex2:		return "icosahedron"
		case .edgepoint0:	return "rhombicosidodecahedron"
		case .edgepoint1:	return "truncated icosahedron"
		case .edgepoint2:	return "truncated dodecahedron"
		case .center:		return "truncated icosidodecahedron"
		}
	}
}

func nearbyArchimedeanPoint(
	_ triplePoint: TriplePoint,
	geometry: GeometryType,
	barycentricBasis: simd_double3x3,
	scale: Double,	//	factor by which the triple-point view enlarges the base triangle
	tolerance: Double
) -> ArchimedeanPoint? {

	//	Convert the triplePoint from parameter space to tiling space.
	let theTriplePoint = barycentricBasis * triplePoint	//	right-to-left matrix action
	let theNormalizedTriplePoint = geometry.metricForVertical.normalize(theTriplePoint)

	for archimedeanPoint in ArchimedeanPoint.allCases {

		//	Convert the archimedeanPoint from parameter space to tiling space.
		let theArchimedeanPoint = barycentricBasis * archimedeanPoint.triplePoint	//	right-to-left matrix action
		let theNormalizedArchimedeanPoint = geometry.metricForVertical.normalize(theArchimedeanPoint)

		let theOffset = theNormalizedTriplePoint - theNormalizedArchimedeanPoint
		let theDistance = geometry.metricForHorizontal.length(theOffset)
		let theScaledDistance = scale * theDistance	//	= distance in triple-point view

		if theScaledDistance < tolerance {
			return archimedeanPoint
		}
	}
	
	return nil
}

func archimedeanName(
	modelData: KaleidoTileModel
) -> LocalizedStringKey? {

	//	If the triple point is in motion, don't try to assign a name.
	if modelData.itsTriplePointIncrement != nil {
		return nil
	}
	
	var p = modelData.itsBaseTriangle.reflectionGroup.p
	var q = modelData.itsBaseTriangle.reflectionGroup.q
	var r = modelData.itsBaseTriangle.reflectionGroup.r
	
	var a = modelData.itsTriplePoint[0]
	var b = modelData.itsTriplePoint[1]
	var c = modelData.itsTriplePoint[2]

	//	We provide names only for the groups △(2,3,3), △(2,3,4) and △(2,3,5).
	
	//	If there's a '2', move it to the first position.
	//	Otherwise return nil.
	if p == 2 {
		//	no change needed
	} else if q == 2 {
		(p,q) = (q,p)
		(a,b) = (b,a)
	} else if r == 2 {
		(p,r) = (r,p)
		(a,c) = (c,a)
	} else {
		return nil
	}
	
	//	If there's a '3', move it to the second position.
	//	Otherwise return nil.
	if q == 3 {
		//	no change needed
	} else if r == 3 {
		(q,r) = (r,q)
		(b,c) = (c,b)
	} else {
		return nil
	}
	
	//	For computational efficiency, quit if the tiling
	//	isn't one of the ones that we have a name for.
	guard r == 3 || r == 4 || r == 5 else {
		return nil
	}
	
	//	Is the TriplePoint at an ArchmedeanPoint?
	//
	//		We're testing whether the TriplePoint has already
	//		been snapped to an ArchmedeanPoint, so we can
	//		use a pretty tight tolerance here.
	//
	let theTightTolerance = 0.001
	guard let theArchimedeanPoint = nearbyArchimedeanPoint(
										TriplePoint(a,b,c),
										geometry: modelData.itsBaseTriangle.geometry,
										barycentricBasis: modelData.itsBaseTriangle.barycentricBasis,
										scale: modelData.itsBaseTriangle.ndcPlacement.scale,
										tolerance: theTightTolerance)
	else {
		return nil
	}
	
	//	Return a name for the tiling.
	switch r {
	case 3:  return theArchimedeanPoint.name233
	case 4:  return theArchimedeanPoint.name234
	case 5:  return theArchimedeanPoint.name235
	default:
		assertionFailure("Impossible value of r in archimedeanName()")
		return nil
	}
}


// MARK: -
// MARK: Orthogonal projection

func mapOrthogonallyOntoSurface(
	x: Double,	//	x and y coordinates of the touch point
	y: Double,	//		in the tiling's ambient space
	geometry: GeometryType,
	mapToNorthernHemisphere: Bool = false	//	The triple-point view needs a point
											//		in the northern (far) hemisphere,
											//		unlike the main tiling view, which needs
											//		a point in southern (near) hemisphere.
) -> SIMD3<Double> {
	
	//	Map (x,y) onto the sphere, the Euclidean plane, or the hyperbolic plane
	//	via an orthogonal projection.
	//
	//	For the tiling view:
	//
	//		Spherical geometry
	//			An orthogonal projection is simpler than
	//			the perspective projection that the KaleidoTileRenderer
	//			uses to render the sphere in the main tiling view,
	//			yet feels just as natural.
	//
	//		Euclidean geometry
	//			The KaleidoTileRenderer uses an orthogonal projection
	//			for Euclidean tilings.
	//
	//		Hyperbolic geometry
	//			If we needed to drag hyperbolic tilings with pinpoint accuracy,
	//			we could perspectively project the touch point onto the hyperboloid.
	//			The cost of this precision, though, would be twitchy behavior
	//			as the touch point nears the circle-at-infinity (and of course
	//			the touch point would first need to be clamped to a finite disk
	//			to avoid actually reaching the circle-at-infinity).
	//			But KaleidoTile doesn't need such accuracy, so instead let's
	//			project the touch point orthogonally onto the hyperboloid.
	//			The resulting scrolling feels smooth and natural.
	//
	//	For the triple-point view:
	//
	//		The KaleidoTileRenderer uses an orthogonal projection
	//		for all three geometries in the triple-point view,
	//		so the following computation is exact.
	//
	
	let r = sqrt(x*x + y*y)
	
	let p: SIMD3<Double>
	switch geometry {
	
	case .spherical:
		p = ( r < 1.0 ?
			SIMD3<Double>(x, y, mapToNorthernHemisphere ?
					+sqrt(1.0 - r*r) :	//	in northern hemisphere, for triple-point view
					-sqrt(1.0 - r*r)	//	in southern hemisphere, for main tiling view
			) :
			SIMD3<Double>(x/r, y/r, 0.0) )			//	on equator

	case .euclidean:
		p = SIMD3<Double>(x, y, 1.0)
		
	case .hyperbolic:
		p = SIMD3<Double>(x, y, sqrt(1.0 + r*r))
	}
		
	return p
}

