//	GeometryGamesBufferPool.swift
//
//	© 2025 by Jeff Weeks
//	See TermsOfUse.txt

@preconcurrency import Metal

//	CAUTION:  NEBBufferPool.swift is essentially just a copy
//	of this file (for reasons explained at the top of NEBBufferPool.swift).
//	So if I make changes to one, I should also make the same changes
//	to the other.  Ugh.  But maybe the best approach if I want
//	to ensure that this code always gets included in zipped
//	source code archives.

//	Apple's Metal Best Practices Guide's section on Persistent Objects,
//	available at
//
//		https://developer.apple.com/library/archive/documentation/3DDrawing/Conceptual/MTLBestPracticesGuide/PersistentObjects.html
//
//	has a subsection on Allocate Resource Storage Up Front,
//	which recommends creating MTLBuffer objects early on,
//	and then re-using those same objects -- with fresh data
//	for each frame of course -- during the animation.
//	[Confession:  I personally don't know why buffer allocation
//	is expensive, but online sources (for Vulkan as well as Metal)
//	all agree that it is.]
//
//	For each "inflight" data buffer, the app keeps
//	a GeometryGamesBufferPool containing several instances
//	of that buffer, so that while the GPU renders a frame
//	using one instance of the buffer, the CPU can already
//	be filling another instance in preparation for the next frame.
//	A GeometryGamesBufferPool creates new buffers as needed,
//	so getBuffer() may fail only in the extremely unlikely situation
//	that a GeometryGamesBufferPool has no more buffers available
//	and has failed in its attempt to create a new one.
//
//	In many cases the required buffer size may vary from frame to frame.
//	In such cases the app may initialize the GeometryGamesBufferPool
//	with some small initial buffer size, and then later
//	call ensureSize() to increase the buffer size as required.
//	ensureSize() never decreases the size of the buffers in the pool,
//	and when it increases their size, it always does so by at least
//	a factor two.  This avoids the risk of having to replace
//	the buffers over and over, each time by only a trivial amount.
//	Instead, by at least doubling the buffer size each time,
//	we limit the total number of replacements to
//
//			      largest buffer size ever needed
//			log₂( ------------------------------- )
//		 	          original buffer size
//

//	Design note:  I tried making the GeometryGamesBufferPool
//	a @MainActor class and got a mysterious run time crash (EXC_BREAKPOINT (SIGTRAP)).
//	I tried making it an actor, but that was even worse.
//	So I've left it as a nonisolated class with a good old-fashioned
//	manual NSLock() to protect its contents, and that works fine.
//	The '@unchecked Sendable' designation tells the compiler that
//	we've taken responsibility for avoiding data races
//	on the GeometryGamesBufferPool's variables (which we do
//	with itsPoolLock).
nonisolated final class GeometryGamesBufferPool: @unchecked Sendable {

	private let itsDevice: MTLDevice
	private var itsBufferSize: Int
	private let itsStorageMode: MTLResourceOptions	//	.storageModePrivate or .storageModeShared
													//		(see Technical Note below)
	private let itsBufferLabel: String
	private var itsPool = [MTLBuffer]()
	private var itsCount = 0

	//	Technical Note:  Even though on iOS devices
	//	the CPU and GPU share system memory, Apple's page
	//
	//			https://developer.apple.com/documentation/metal/setting_resource_storage_modes/choosing_a_resource_storage_mode_in_ios_and_tvos
	//
	//	says that memory used only by the GPU should have storageModePrivate.

	//	Mutable arrays are not thread-safe,
	//	so let's use a lock to serialize access to itsPool.
	let itsPoolLock = NSLock()
	
	init(
		device: MTLDevice,
		initialBufferSize: Int,
		storageMode: MTLResourceOptions,
		bufferLabel: String
	) {
		precondition(
				storageMode == .storageModePrivate
			 || storageMode == .storageModeShared,
		 "Expected .storageModePrivate or .storageModeShared")
		
		itsDevice = device
		itsBufferSize = initialBufferSize
		itsStorageMode = storageMode
		itsBufferLabel = bufferLabel
	}
	
	func get(
		forUseWith commandBuffer: MTLCommandBuffer
	) -> MTLBuffer {
		
		itsPoolLock.lock()
		
			let theBuffer: MTLBuffer
			if itsPool.isEmpty {

				guard let theNewBuffer = itsDevice.makeBuffer(
					length: itsBufferSize,
					options: [itsStorageMode])
				else {
					//	In the unlikely event that itsDevice can't create theNewBuffer,
					//	let's just give up.  On the one hand, this may seem like
					//	a drastic response, but on the other hand, it lets us
					//	return a MTLBuffer instead of a MTLBuffer?, which keep
					//	the caller's code cleaner.  Also, if itsDevice can't
					//	create theNewBuffer, then the app is surely headed
					//	for trouble in any case.
					fatalError("fail to create theNewBuffer")
				}

				theNewBuffer.label = itsBufferLabel + "size:" + String(itsBufferSize) + " #" + String(itsCount)
				itsCount += 1
				
				theBuffer = theNewBuffer
			}
			else {
				theBuffer = itsPool.removeLast()
			}

			//	Put theBuffer back into the pool when the GPU
			//	has finished executing the commandBuffer.
			commandBuffer.addCompletedHandler { cb in

				//	Without the '@preconcurrency' in
				//
				//		@preconcurrency import Metal
				//
				//	we get a compiler warning here:
				//
				//		Capture of 'theBuffer' with non-Sendable type
				//		'any MTLBuffer' in a '@Sendable' closure
				//
				self.put(theBuffer)
			}

		itsPoolLock.unlock()
		
		return theBuffer
	}
	
	func put(_ buffer: MTLBuffer) {

		itsPoolLock.lock()
		
			if buffer.length == itsBufferSize {
				
				//	The buffer's size agrees with itsBufferSize,
				//	and we return the buffer to the pool.
				itsPool.append(buffer)
				
			} else {
				
				//	Atypical case:  The buffer was gotten
				//	from itsPool just before a recent resizing.
				//	Discard this too-small buffer.
				//	Future calls to get() will replace it
				//	with new buffers of the correct size as needed.
				
			}
		
		itsPoolLock.unlock()
	}
	
	func ensureSize(_ minBufferSize: Int) {
		
		itsPoolLock.lock()

			if itsBufferSize >= minBufferSize {

				//	Our buffers are already big enough to meet the caller's needs.
				//	No changes are necessary.

			} else {

				//	Our existing buffers aren't big enough to meet the caller's needs.

				//	Increase itsBufferSize by at least a factor of two.
				//	This limits the total number of buffer replacements to at most
				//
				//			      largest buffer size ever needed
				//			log₂( ------------------------------- )
				//		 	          original buffer size
				//
				//	as explained in the comment near the top of this file.
				//
				itsBufferSize *= 2
				if itsBufferSize < minBufferSize {
					itsBufferSize = minBufferSize
				}

				//	We must discard all buffers currently in itsPool.
				//	Any buffers that are currently in use by the GPU
				//	will get discarded when the caller returns them
				//	via the put() function immediately above.
				itsPool.removeAll()
				itsCount = 0
			}

		itsPoolLock.unlock()
	}
}
