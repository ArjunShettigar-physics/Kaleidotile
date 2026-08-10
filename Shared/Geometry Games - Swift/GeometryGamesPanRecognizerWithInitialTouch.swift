//	GeometryGamesPanRecognizerWithInitialTouch.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt


#if os(iOS)
import UIKit.UIGestureRecognizerSubclass
#endif
#if os(macOS)
import AppKit
#endif

class GeometryGamesPanRecognizerWithInitialTouch: GeometryGamesPlatformDependentPanGestureRecognizer {

	//	When UIPanGestureRecognizer reports state = .began,
	//	its location is already the slightly translated location.
	//	But we want to know the location of the initial touch,
	//	for more reliable hit testing.
	
	var initialTouchLocation: CGPoint?	//	Caution: Old values will linger.

#if os(iOS)
	override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
		initialTouchLocation = touches.first?.location(in: view)	//	Should never fail
		super.touchesBegan(touches, with: event)
	}
#endif

#if os(macOS)
	override func mouseDown(with event: NSEvent) {
		initialTouchLocation = event.locationInWindow
		super.mouseDown(with: event)
	}
#endif
}
