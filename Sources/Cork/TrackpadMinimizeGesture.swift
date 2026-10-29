import Foundation
import CorkCore
import CorkInput
import os

private struct ContactFrame: Sendable {
    let generation: UInt64
    let device: UInt64
    let contacts: [TrackpadContact]
    let time: Double
}

// Each monitoring session gets its own bounded stream. Cancelling a stream terminates
// it permanently, so sleep/wake and disabling/re-enabling must not reuse one.
private let contactDelivery = OSAllocatedUnfairLock<AsyncStream<ContactFrame>.Continuation?>(initialState: nil)

private func receiveContacts(_ generation: UInt64, _ device: UInt64, _ contacts: UnsafePointer<CorkContact>?, _ count: UInt32, _ time: Double) {
    guard count <= 16 else { return }
    let values = contacts.map { buffer in
        UnsafeBufferPointer(start: buffer, count: Int(count)).map { TrackpadContact(id: $0.identifier, x: $0.x, y: $0.y) }
    } ?? []
    let frame = ContactFrame(generation: generation, device: device, contacts: values, time: time)
    contactDelivery.withLock { _ = $0?.yield(frame) }
}

@MainActor final class TrackpadMinimizeGesture {
    private var task: Task<Void, Never>?
    private var detector = AnchoredSwipeDetector()
    private(set) var trackpads: Int32 = 0
    private(set) var monitoring = false
    private(set) var available = true
    private(set) var framesReceived = 0
    private(set) var gesturesRecognized = 0
    var onGesture: (() -> Void)?

    func probe() {
        let result = cork_trackpad_probe()
        available = result >= 0; trackpads = max(0, result)
    }
    func apply(enabled: Bool) {
        if !enabled { stop(); return }
        guard !monitoring else { return }
        let channel = AsyncStream<ContactFrame>.makeStream(bufferingPolicy: .bufferingNewest(4))
        contactDelivery.withLock { $0 = channel.continuation }
        let result = cork_trackpad_start(receiveContacts)
        available = result >= 0; trackpads = max(0, result)
        guard result > 0 else {
            cork_trackpad_stop(); contactDelivery.withLock { $0?.finish(); $0 = nil }; return
        }
        let generation = cork_trackpad_generation()
        monitoring = true; detector.reset()
        task = Task { [weak self] in
            for await frame in channel.stream {
                guard !Task.isCancelled, let self else { return }
                guard frame.generation == generation else { continue }
                framesReceived += 1
                if detector.process(device: frame.device, contacts: frame.contacts, time: frame.time) {
                    gesturesRecognized += 1; onGesture?()
                }
            }
        }
    }
    func stop() {
        contactDelivery.withLock { $0?.finish(); $0 = nil }
        task?.cancel(); task = nil
        if monitoring { cork_trackpad_stop() }
        monitoring = false; detector.reset()
    }
}
