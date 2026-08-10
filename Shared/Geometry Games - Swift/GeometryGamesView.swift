//	GeometryGamesView.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

import SwiftUI

//	Note:  If you go to
//
//		Target > Build Settings > Swift Compiler - Custom Flags > Other Swift Flags > Debug
//
//	and add the lines
//
//		-Xfrontend
//		-warn-long-function-bodies=100
//		-Xfrontend
//		-warn-long-expression-type-checking=5
//				(or =20 for a less thorough check)
//
//	the compiler will measure the time required for type-checking individual lines of code
//	and for compiling individual functions, and will issue warnings for slow ones.
//	Unfortunately there are many lines of code that are slow to type-check.
//
//	Note: Accessing a component of a vector v as v.x is faster to type check
//	than accessing it as v[0].

protocol GeometryGamesUpdatable {

	//	updateModel() updates the model as desired and returns
	//	the model's change count. animationTimerFired() will
	//	redraw the view if the model's change count has changed
	//	since the previous frame (and possibly for other reasons
	//	as well).
	//
	//		Note:  There's little risk that the model's change count
	//		could overflow.  Even if the app increments its change count
	//		1000 times for every frame and renders 100 frames per second,
	//		it would take roughly a million years for its change count
	//		to overflow.
	//
	var changeCount: UInt64 { get set }
	func updateModel() -> UInt64
}

//	A DisplayPoint is convenient for reporting gesture locations
//	in a simple format.
struct DisplayPoint {

	//	Measurements may be in pixels or points;
	//	either is fine just so they're consistent.

	var x: Double	//	left-to-right, from 0 to viewWidth
	var y: Double	//	bottom-to-top, from 0 to viewHeight
	var viewWidth: Double
	var viewHeight: Double
}

//	A DisplayPointMotion is just like a DisplayPoint, except that
//	it stores a relative motion instead of an absolute position.
struct DisplayPointMotion {

	//	Measurements may be in pixels or points;
	//	either is fine just so they're consistent.

	var Δx: Double	//	left-to-right motion is positive
	var Δy: Double	//	bottom-to-top motion is positive
	var viewWidth: Double
	var viewHeight: Double
}


#if os(iOS)
	typealias GeometryGamesViewRepresentable = UIViewRepresentable
	typealias GeometryGamesViewSuperclass = UIView
	typealias GeometryGamesPlatformDependentGestureRecognizer = UIGestureRecognizer
	typealias GeometryGamesPlatformDependentPanGestureRecognizer = UIPanGestureRecognizer
	typealias GeometryGamesPlatformDependentRotationGestureRecognizer = UIRotationGestureRecognizer
	typealias GeometryGamesPlatformDependentPinchGestureRecognizer = UIPinchGestureRecognizer
	typealias GeometryGamesPlatformDependentTapGestureRecognizer = UITapGestureRecognizer
	typealias GeometryGamesPlatformDependentGestureRecognizerDelegate = UIGestureRecognizerDelegate
#endif
#if os(macOS)
	typealias GeometryGamesViewRepresentable = NSViewRepresentable
	typealias GeometryGamesViewSuperclass = NSView
	typealias GeometryGamesPlatformDependentGestureRecognizer = NSGestureRecognizer
	typealias GeometryGamesPlatformDependentPanGestureRecognizer = NSPanGestureRecognizer
	typealias GeometryGamesPlatformDependentRotationGestureRecognizer = NSRotationGestureRecognizer
	typealias GeometryGamesPlatformDependentPinchGestureRecognizer = NSMagnificationGestureRecognizer
	typealias GeometryGamesPlatformDependentTapGestureRecognizer = NSClickGestureRecognizer
	typealias GeometryGamesPlatformDependentGestureRecognizerDelegate = NSGestureRecognizerDelegate
#endif

#if os(macOS)
//	In GeometryGamesView's layout() function, the testing code
//
//		if let theWindowView = window?.contentView {
//
//			let theSizePt = theWindowView.bounds.size
//			let theSizePx = theWindowView.convertToBacking(theSizePt)
//
//			print("scale factor H: \(theSizePx.width  / theSizePt.width )")
//			print("scale factor V: \(theSizePx.height / theSizePt.height)")
//			print("---------------")
//		}
//
//	always reports a scale factor of exactly 2.0, even when I go to
//
//		Settings > Displays > Use as
//
//	and change my MacBook's display's perceived size
//	(that is, when I change the display's dimensions in points).
//
//	This makes me suspect that macOS always renders the window
//	into a buffer at exactly 2x resolution (2 pixels per point)
//	and then rescales the result to match the display's physical
//	dimensions. On certain iPhone models, iOS does something similar:
//	it renders at 3x and then downsamples to match the phone's
//	physical display. On iOS we can use the view's nativeBounds
//	to set our CAMetalLayer's drawableSize to exactly match
//	the physical display, in which case iOS omits the rescaling step.
//	But as far as I know that option isn't available on macOS.
//
//	Conclusion: We should always set pixelsPerPoint to 2.0
//	to match the presumed buffer that macOS is rendering into.
//
//	Note #1: In the rare case that we're rendering to a non-retina display,
//	our CAMetalLayer will be larger than necessary, but should
//	still work correctly.
//
//	Note #2: If my hypothesis about macOS rendering to a buffer
//	at exactly 2 pixels per point ever proves incorrect, the app
//	should nevertheless still work correctly, but perhaps with
//	an extra rescaling required.
//
let gPixelsPerPoint = 2.0
#endif // os(macOS)


struct GeometryGamesViewRep<ModelDataType: GeometryGamesUpdatable>:
		GeometryGamesViewRepresentable
{

	//	Someday SwiftUI might offer direct access to a CAMetalLayer
	//	or equivalent. Until then, we define a GeometryGamesView
	//	to be a subclass of a GeometryGamesViewSuperclass = UIView or NSView,
	//	and wrap an instance of one in this GeometryGamesViewRep,
	//	which implements the GeometryGamesViewRepresentable protocol
	//	= UIViewRepresentable or NSViewRepresentable that SwiftUI
	//	requires for including a UIView or NSView in the view heirarchy.

	//	How iOS (and, I'm guessing, also macOS) uses this struct
	//	at runtime is a bit surprising. When the user first launches
	//	the app, we get calls to
	//
	//		init()
	//		makeUIView()
	//		updateUIView()
	//
	//	as expected.  But thereafter, whenever the app's
	//	ContentView body() gets called, here we get only a call
	//	to init(), with no call to makeUIView() nor updateUIView().
	//	That is, iOS knows that it can keep using the same
	//	GeometryGamesView that it's already got, so it doesn't ask
	//	for a new one, even though it's created a new GeometryGamesViewRep
	//	"just in case".  In effect, the GeometryGamesViewRep is
	//	a factory that can be used to create a new GeometryGamesView,
	//	but in most situations it's not needed.

	var modelData: ModelDataType
	let renderer: GeometryGamesRenderer<ModelDataType>

	//	Most of the Geometry Games apps use SwiftUI gesture recognizers and
	//	have no need for any GeometryGamesPlatformDependentGestureRecognizers
	//	at all. The GeometryGamesPlatformDependentGestureRecognizers
	//	are used only for apps that need 2-finger drags, which SwiftUI
	//	doesn't support (presumably because 2-finger drags would be awkward
	//	to implement on visionOS and watchOS). For 2-finger drags on iOS
	//	we use a native UIPanGestureRecognizer. The macOS AppKit doesn't
	//	support multi-touch gestures, but fortunately we can instead use
	//	scrollWheel to implement 2-finger drags.
	//
	//		Note: A seemingly natural organization would be to attach gestures
	//		at the SwiftUI level using SwiftUI's UIGestureRecognizerRepresentable.
	//		Alas its documentation at
	//
	//			https://developer.apple.com/documentation/swiftui/uigesturerecognizerrepresentable
	//		says
	//			The gesture recognizer you create may not be attached to a UIView
	//			in the hierarchy, or it may return a view with different geometry
	//			than your SwiftUI view.
	//
	//		and indeed in practice it fails to provide the correct view, which
	//		means that the reported 'locations' and 'translations' are in the
	//		wrong coordinate system. So let's not use UIGestureRecognizerRepresentable.
	//
	//	The most robust solution is to attach GeometryGamesPlatformDependentGestureRecognizers
	//	directly to the GeometryGamesView, which is a subclass of UIView or NSView.
	//
	let gestureRecognizers: [GeometryGamesPlatformDependentGestureRecognizer]
	
	//	Only KaleidoTile uses the extraRenderFlag,
	//	which tells the renderer whether it's rendering
	//	the full tiling or the only the base triagle.
	let extraRenderFlag: Bool?
	
	let isOpaque: Bool
	let isMainView: Bool
	
	init(
		modelData: ModelDataType,
		renderer: GeometryGamesRenderer<ModelDataType>,
		gestureRecognizers: [GeometryGamesPlatformDependentGestureRecognizer] = [],
		extraRenderFlag: Bool? = nil,
		isOpaque: Bool = true,
		isMainView: Bool = true	//	only non-main view is KaleidoPaint's TriplePointView
	) {
		self.modelData = modelData
		self.renderer = renderer
		self.gestureRecognizers = gestureRecognizers
		self.extraRenderFlag = extraRenderFlag
		self.isOpaque = isOpaque
		self.isMainView = isMainView
	}

#if os(iOS)

	func makeUIView(
		context: UIViewRepresentableContext<GeometryGamesViewRep>
	) -> GeometryGamesView<ModelDataType> {

		let theGeometryGamesView = GeometryGamesView<ModelDataType>(
			modelData: modelData,
			renderer: renderer,
			extraRenderFlag: extraRenderFlag,
			isMainView: isMainView)

		//	Ignore all buttons while user is drawing in the main view.
		//
		//		isExclusiveTouch seems like a good idea for all
		//		the Geometry Games apps. But if I ever want
		//		to disable it for a particular app, I could
		//		introduce an optional parameter (here in this init())
		//		similar to the isOpaque parameter above.
		//
		theGeometryGamesView.isExclusiveTouch = true
		
		//	Let UIKit know whether this view may be partially transparent
		//	and may need to be blended onto whatever other view
		//	lies underneath it.  KaleidoTile uses this option
		//	to let the Triple Point view be composited correctly;
		//	none of the other Geometry Games apps need it.
		theGeometryGamesView.isOpaque = isOpaque

		for theGestureRecognizer in gestureRecognizers {
			theGeometryGamesView.addGestureRecognizer(theGestureRecognizer)
		}

		return theGeometryGamesView
	}
	
	func updateUIView(
		_ uiView: GeometryGamesView<ModelDataType>,
		context: UIViewRepresentableContext<GeometryGamesViewRep>
	) {
	}

#endif	//	os(iOS)

#if os(macOS)

	func makeNSView(
		context: NSViewRepresentableContext<GeometryGamesViewRep>
	) -> GeometryGamesView<ModelDataType> {

		let theGeometryGamesView = GeometryGamesView<ModelDataType>(
			modelData: modelData,
			renderer: renderer,
			extraRenderFlag: extraRenderFlag,
			isMainView: isMainView)

		for theGestureRecognizer in gestureRecognizers {
			theGeometryGamesView.addGestureRecognizer(theGestureRecognizer)
		}

		return theGeometryGamesView
	}

	func updateNSView(
		_ nsView: GeometryGamesView<ModelDataType>,
		context: NSViewRepresentableContext<GeometryGamesViewRep>
	) {
	}

#endif	//	os(macOS)

}


class GeometryGamesView<ModelDataType: GeometryGamesUpdatable>:
		GeometryGamesViewSuperclass {

	let itsModelData: ModelDataType
	let itsRenderer: GeometryGamesRenderer<ModelDataType>
	let itsExtraRenderFlag: Bool?
	let itIsMainView: Bool
		
	//	When the view size changes, we manually adjust
	//	the drawable size accordingly, and then need
	//	to request a redraw.
	var itsDrawableSizeHasChanged: Bool = false
	
	//	
	//	What was the value of the ModelData's change count
	//	the last time we refreshed our view(s)?
	//
	//		Note:  itsModelData initializes its change count to 0,
	//		so we should initialize itsPreviousModelChangeCount
	//		to a different value to ensure an initial update.
	//
	var itsPreviousModelChangeCount: UInt64 = 0xFFFFFFFFFFFFFFFF

	var itsAnimationTimer: GeometryGamesDisplayLink<ModelDataType>? = nil

#if os(iOS)
	override class var layerClass: AnyClass {
		return CAMetalLayer.self}
#endif

#if os(macOS)
	//	In all the Geometry Games apps, the only view that
	//	has a transparent background on iOS is KaleidoTile's
	//	TriplePointView. I couldn't get that transparency
	//	to work on macOS, but that's OK. It's needed on iOS
	//	only because the TriplePointView covers much of the display
	//	on a small phone. As users move the triple point
	//	in the TriplePointView, we want them to see its effect
	//	on the tiling in the main view underneath.
	//	By contrast, on macOS the TriplePointView covers only
	//	a small part of the window, so even when the TriplePointView
	//	has an opaque background, the user can still see how
	//	moving the triple point affects the tiling as a whole.
	//
	override var isOpaque: Bool { return true }
#endif


	init(
		modelData: ModelDataType,
		renderer: GeometryGamesRenderer<ModelDataType>,
		extraRenderFlag: Bool?,
		isMainView: Bool	//	only non-main view is KaleidoPaint's TriplePointView
	) {

		itsModelData = modelData
		itsRenderer = renderer
		itsExtraRenderFlag = extraRenderFlag
		itIsMainView = isMainView
				
		super.init(frame: .zero)

#if os(iOS)
		//	On iOS, super.init() creates the CAMetalLayer.
#endif
#if os(macOS)
		//	On macOS we must explicitly create a CAMetalLayer.
		let theMetalLayer = CAMetalLayer()

		//	On macOS, Metal has no default working color space.
		//	So let's ask theMetalLayer to use
		//	extended-range sRGB (gamma-encoded -- not linear),
		//	to match iOS's standard color space.
		if let theColorSpace = CGColorSpace(name: CGColorSpace.extendedSRGB) {
			theMetalLayer.colorspace = theColorSpace
		}
		
		self.layer = theMetalLayer
		self.wantsLayer = true
#endif

		//	theCAMetalLayer's device and pixel format
		//	must agree with the renderer's.
		if let theCAMetalLayer = layer as? CAMetalLayer {
			theCAMetalLayer.device = renderer.itsDevice
			theCAMetalLayer.pixelFormat = renderer.itsColorPixelFormat
		}

		//	We'll draw all Metal graphics at the display's native scale.
		//	Please see the comments in layoutSubviews() for further details.
		//	See also Apple's Technical Q&A QA1909
		//
		//			https://developer.apple.com/library/content/qa/qa1909/_index.html
		//
#if os(iOS)
		contentScaleFactor = UIScreen.main.nativeScale
#endif

		itsAnimationTimer = GeometryGamesDisplayLink(target: self)
	}
	isolated deinit {
		if let theAnimationTimer = itsAnimationTimer {
			theAnimationTimer.invalidate()
		}
	}

	required init(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
#if os(iOS)
	//	layoutSubviews() is really a "viewSizeDidChange()" message.
	override func layoutSubviews() {
	
		//	The view size has changed, so we must manually
		//	adjust the CAMetalLayer's drawableSize accordingly.

		//	The tricky part is that iOS might be drawing
		//	the user interface elements at some integer scale
		//	(either 2x or 3x) and then resampling the result
		//	at some non-integer scale to fit the device's display.
		//	For example, the iPhone 6+, 6s+, 7+ and 8+ all normally
		//	draw at 3x and then downsample to ~2.6x (1080/414).
		//	Some of the other iPhones, such as my iPhone SE 2020,
		//	normally render at 2x, but also offer a Display Zoom mode
		//	in which a 2x image gets upsampled to ~2.3x (750/320).
		//
		//	Happily, iOS let's us bypass that resampling,
		//	and instead render our Metal image at the device's
		//	native pixel resolution.  To do so, we need to set
		//	theDrawableSize to exactly the size of the area that's
		//	been assigned to our view (measured in native pixels).
		//
		//	Unhappily, iOS doesn't tell us what that required
		//	size (measured in native pixels) is.  Instead, we must
		//	figure it out for ourselves, by computing
		//
		//		theDrawableSize (in pixels)
		//		   = the view size (in points)
		//		   * the content scale factor (in pixels/point)
		//
		//	So far so good.
		//	The only catch is that the computed value of theDrawableSize
		//	typically comes out to a non-integer, and if we round it
		//	in the wrong direction to get an integer, our value
		//	for theDrawableSize might be 1 pixel wider or narrower
		//	(and taller or shorter) than the area iOS has assigned
		//	to our view, in which case iOS might end up re-sampling
		//	our image after all -- which is something we were hoping
		//	to avoid.
		//
		//	In practice, we can pass our computed non-integer value
		//	of theDrawableSize and let iOS do the rounding
		//	(which it does immediately, apparently in the "setter"
		//	for theCAMetalLayer.drawableSize).  Moreover, testing shows
		//	that iOS always rounds down, so for example if we request
		//	a width of 636.87, we'll get 636, not 637.
		//
		//	In most cases, passing the un-rounded value should
		//	let us match the size of the assigned area (in native pixels)
		//	exactly.  The only remaining risk is that, when the computed area
		//	happens to have integer dimensions, the inherent error
		//	in the floating-point value of contentScaleFactor might
		//	cause us to compute, say, a width of 636.999999999 instead
		//	of the required 637, which might force iOS to re-sample our image
		//	because 636.99999999 rounds down to 636, which is 1 less than
		//	the required 637.  To avoid that, we can ignore the floating-point
		//	value contentScaleFactor and instead take the content scale factor
		//	to be the ratio of two integers, namely the main screen's
		//
		//			width in native pixels
		//			----------------------
		//			   width in points
		//
		//	to ensure that integer results always come out exact.

		//	2020-12-11  My iPhone SE 2020 normally renders a 375×667 pt layout
		//	on its native 750×1334 px display, for an exact 2x scale factor.
		//	But it also offers a Display Zoom option, which treats
		//	that same native 750×1334 px display as 320×568 pt layout.
		//	The problem is that the scale factor is anisotropic:
		//
		//		the horizontal scale factor is  750/320 = 2.34375
		//		the  vertical  scale factor is 1334/568 = 2.3485915…
		//
		//	So some extra fussing around is required.

		//	The screen bounds (in points) are given
		//	relative to the current interface orientation.
		let theScreenSizeInPoints = UIScreen.main.bounds.size

		//	By contrast, the nativeBounds (in pixels) are always given
		//	in portrait orientation when running on an iOS device,
		//	but are given in the natural landscape orientation
		//	when running on a Mac.  So in effect at runtime
		//	we don't know whether the nativeBounds are using
		//	the same orientation as the regular "bounds",
		//	or the opposite.  So for simplicity let's just
		//	match long with long and short with short.
		let theScreenSizeInPixels: CGSize
		if ((UIScreen.main.nativeBounds.size.height >= UIScreen.main.nativeBounds.size.width)
		 == (theScreenSizeInPoints.height >= theScreenSizeInPoints.width)
		) {
			theScreenSizeInPixels = UIScreen.main.nativeBounds.size
		} else {
			//	Swap width and height.
			theScreenSizeInPixels = CGSize(
				width:  UIScreen.main.nativeBounds.size.height,
				height: UIScreen.main.nativeBounds.size.width)
		}
		
		//	By doing the multiplication before the division,
		//	we ensure that whenever the result should be an integer,
		//	it will get computed exactly.
		let theDrawableSize = CGSize(
			width:  (bounds.size.width  * theScreenSizeInPixels.width ) / theScreenSizeInPoints.width,
			height: (bounds.size.height * theScreenSizeInPixels.height) / theScreenSizeInPoints.height)

		if let theCAMetalLayer = layer as? CAMetalLayer {
			theCAMetalLayer.drawableSize = theDrawableSize
		}

		//	Request a redraw.
		itsDrawableSizeHasChanged = true
	}
#endif // os(iOS)
#if os(macOS)
	//	layout() is really a "viewSizeDidChange()" message.
	override func layout() {

		//	The view size has changed, so we must manually
		//	adjust the CAMetalLayer's drawableSize accordingly.

		let theDrawableSize = CGSize(
			width:  gPixelsPerPoint * bounds.size.width,
			height: gPixelsPerPoint * bounds.size.height)

		if let theCAMetalLayer = layer as? CAMetalLayer {
			theCAMetalLayer.drawableSize = theDrawableSize
		}

		itsDrawableSizeHasChanged = true	//	Request a redraw
	}
#endif // os(macOS)


// MARK: -
// MARK: Animation

	func animationTimerFired() {

		//	Note: The CADisplayLink calls this animationTimerFired()
		//	on the main thread.

		//	Update the model, noting the possibly new change count.
		let theModelChangeCount = itIsMainView ?
				itsModelData.updateModel() :
				itsModelData.changeCount	//	KaleidoTile's TriplePointView
											//	doesn't update the model,
											//	because it knows the main view does.

		//	Has the model changed?
		let theModelHasChanged = (theModelChangeCount != itsPreviousModelChangeCount)
		itsPreviousModelChangeCount = theModelChangeCount
		
		//	Has the drawable size changed?
		let theDrawableSizeHasChanged = itsDrawableSizeHasChanged
		itsDrawableSizeHasChanged = false
		
		//	Redraw the view iff something has changed.
		if (theModelHasChanged || theDrawableSizeHasChanged) {

			//	Wrap the render() call in an autorelease pool
			//	so that the drawable gets released as soon as
			//	the render() function returns.
			//
			autoreleasepool {

				if let theCAMetalLayer = layer as? CAMetalLayer {
				
					//	Ask the CAMetalLayer for the next available color buffer.
					//	nextDrawable() blocks until a drawable becomes available.
					//	It returns nil only if
					//		- theCAMetalLayer has an invalid combination of drawable properties,
					//		- all drawables are in use and the 1-second timeout has elapsed, or
					//		- the process is out of memory.
					//
					if let theDrawable = theCAMetalLayer.nextDrawable() {

						itsRenderer.render(
							modelData: itsModelData,
							drawable: theDrawable,
							extraRenderFlag: itsExtraRenderFlag)
					}
				}
			}
		}

		//	Play any pending sound.
		playPendingSound()
	}
}

class GeometryGamesDisplayLink<ModelDataType: GeometryGamesUpdatable> {

	//	This GeometryGamesDisplayLink is a wrapper around
	//	a CADisplayLink. It encapsulates the code needed
	//	to pause the animation when the view isn't visible
	//	and resume it later.

	//	To avoid potential strong reference cycles,
	//	keep only a weak reference to the target view.
	//
	private weak var targetView: GeometryGamesView<ModelDataType>? = nil

	//	Keep only a weak reference to the CADisplayLink,
	//	so the run loop is the only thing that will be keeping
	//	the CADisplayLink alive. When our invalidate() function
	//	eventually invalidates the CADisplayLink, it will get
	//	deinitialized and deallocated.
	//
	private weak var caDisplayLink: CADisplayLink? = nil
	
	init(
		target: GeometryGamesView<ModelDataType>
	) {
	
#if os(iOS)
		let theDisplayLink = CADisplayLink(
								target: self,
								selector: #selector(animationTimerFired))

		//	iOS doesn't automatically pause the CADisplayLink
		//	when the app is inactive. We need to do that ourselves.
		//
		NotificationCenter.default.addObserver(
							self,
							selector: #selector(appWillResignActive),
							name: UIApplication.willResignActiveNotification,
							object: nil)
		NotificationCenter.default.addObserver(
							self,
							selector: #selector(appDidBecomeActive),
							name: UIApplication.didBecomeActiveNotification,
							object: nil)
#endif
#if os(macOS)
		//	The release notes at
		//		https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-14#Display-Link
		//	say
		//		A CADisplayLink can be created via
		//
		//			NSView.displayLink(target:selector:).
		//
		//		The CADisplayLink will automatically track the display
		//		the view is on, and will be automatically suspended
		//		if it isn’t on a display.
		//
		//	Unfortunately if the player makes the window full-screen
		//	and slides its "Space" off the display, the CADisplayLink
		//	will keep running even though the window isn't visible.
		//	To pause the animation in such circumstances, I wrote
		//	some code to listen for didMoveNotifications and check
		//	theWindow.isOnActiveSpace, but alas isOnActiveSpace
		//	doesn't give a reliable result (it fails on the main display
		//	and fails in a different way on an external display).
		//	So for now we just live with the fact that the animation
		//	keeps running when a full-screen window gets slid offscreen
		//	in its own "Space". The workaround is to click the little yellow
		//	button (next to the window's yellow close button) to send
		//	the window to the Dock, or alternatively to use ⌘H to send
		//	the whole app to the Dock. Either way, the animation pauses
		//	until we restore the window.
		//
		let theDisplayLink = target.displayLink(
								target: self,
								selector: #selector(animationTimerFired))
#endif

		//	Set RunLoop.Mode = .common (not .default).
		//	With .default, the animation would pause while
		//	the user scrolls a Help view or slides a slider.
		//
		theDisplayLink.add(to: .current, forMode: .common)
		
		caDisplayLink = theDisplayLink
		targetView = target
	}
	deinit {
#if os(iOS)
		NotificationCenter.default.removeObserver(
							self,
							name: UIApplication.willResignActiveNotification,
							object: nil)
		NotificationCenter.default.removeObserver(
							self,
							name: UIApplication.didBecomeActiveNotification,
							object: nil)
#endif
	}

	func invalidate() {

		//	The RunLoop keeps a strong reference to the CADisplayLink,
		//	which in turn keeps a strong reference to its target,
		//	which is this GeometryGamesDisplayLink. That is,
		//	the strong (---) and weak (···) references look like this
		//
		//	  RunLoop ---> CADisplayLink ---> GeometryGamesDisplayLink ···> GeometryGamesView
		//	                            <····
		//
		//	As soon as we invalidate the CADisplayLink, the RunLoop
		//	releases its strong reference to the CADisplayLink,
		//	which in turn gets deinitialized and releases its target,
		//	which is this GeometryGamesDisplayLink. If no other object
		//	holds a strong reference to this GeometryGamesDisplayLink,
		//	it gets deallocated.
		//
		caDisplayLink?.invalidate()
	}

	@objc func animationTimerFired(displayLink: CADisplayLink) {
		targetView?.animationTimerFired()
	}
	
#if os(iOS)
	@objc func appWillResignActive() {
		caDisplayLink?.isPaused = true
	}
	@objc func appDidBecomeActive() {
		caDisplayLink?.isPaused = false
	}
#endif
}


// MARK: -
// MARK: Gesture handling
	
func getGestureLocation(
	gestureRecognizer: GeometryGamesPlatformDependentGestureRecognizer,
	alternateLocation: CGPoint? = nil	//	used only for initial pan location, otherwise nil
) -> DisplayPoint? {

	guard let theView = gestureRecognizer.view else {
		assertionFailure("getTouchLocation() received a gestureRecognizer with no UIView/NSView")
		return nil
	}
	let theViewSize = theView.frame.size

	let theLocationInPoints = alternateLocation ??	//	used only for initial pan location
								gestureRecognizer.location(in: theView)	//	typical case

	let x = theLocationInPoints.x
#if os(iOS)
	let y = theViewSize.height - theLocationInPoints.y	//	flip y on iOS
#endif
#if os(macOS)
	let y = theLocationInPoints.y						//	don't flip y on macOS
#endif

	let theDisplayPoint = DisplayPoint(
		x: x,
		y: y,
		viewWidth:  theViewSize.width,
		viewHeight: theViewSize.height)

	return theDisplayPoint
}

func getPanGestureTranslation(
	panGestureRecognizer: GeometryGamesPlatformDependentPanGestureRecognizer
) -> DisplayPointMotion? {

	guard let theView = panGestureRecognizer.view else {
		assertionFailure("getPanGestureTranslation() received a panGestureRecognizer with no UIView")
		return nil
	}
	let theViewSize = theView.frame.size
	
	let theTranslationInPoints = panGestureRecognizer.translation(in: theView)

	let Δx =  theTranslationInPoints.x
#if os(iOS)
	let Δy = -theTranslationInPoints.y	//	flip Δy on iOS
#endif
#if os(macOS)
	let Δy = +theTranslationInPoints.y	//	don't flip Δy on macOS
#endif

	let theTranslation = DisplayPointMotion(
							Δx: Δx,
							Δy: Δy,
							viewWidth:  theViewSize.width,
							viewHeight: theViewSize.height)
	
	return theTranslation
}
