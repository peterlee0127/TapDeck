import Darwin
import Foundation
import os.lock

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTContactCallback = @convention(c) (
    MTDeviceRef?, UnsafeMutableRawPointer?, Int32, Double, Int32
) -> Int32

private struct MTPointRaw {
    var x: Float
    var y: Float
}

private struct MTVectorRaw {
    var position: MTPointRaw
    var velocity: MTPointRaw
}

private struct MTTouchRaw {
    var frame: Int32
    var timestamp: Double
    var pathIndex: Int32
    var state: UInt32
    var fingerID: Int32
    var handID: Int32
    var normalizedVector: MTVectorRaw
    var zTotal: Float
    var field9: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absoluteVector: MTVectorRaw
    var field14: Int32
    var field15: Int32
    var zDensity: Float
}

private typealias CreateListFunction = @convention(c) () -> Unmanaged<CFArray>?
private typealias RegisterFunction = @convention(c) (MTDeviceRef, MTContactCallback) -> Void
private typealias UnregisterFunction = @convention(c) (MTDeviceRef, MTContactCallback) -> Void
private typealias StartFunction = @convention(c) (MTDeviceRef, Int32) -> Void
private typealias StopFunction = @convention(c) (MTDeviceRef) -> Void
private typealias SensorDimensionsFunction = @convention(c) (
    MTDeviceRef, UnsafeMutablePointer<Int32>, UnsafeMutablePointer<Int32>
) -> Int32

protocol MultitouchBridgeDelegate: AnyObject {
    func multitouchBridge(_ bridge: MultitouchBridge, received frame: TouchFrame)
}

private nonisolated(unsafe) weak var activeBridge: MultitouchBridge?
private nonisolated(unsafe) var callbackLock = os_unfair_lock()

private let contactCallback: MTContactCallback = { _, pointer, count, timestamp, _ in
    guard count >= 0 else { return 0 }
    os_unfair_lock_lock(&callbackLock)
    defer { os_unfair_lock_unlock(&callbackLock) }
    activeBridge?.receive(pointer: pointer, count: Int(count), timestamp: timestamp)
    return 0
}

final class MultitouchBridge: @unchecked Sendable {
    weak var delegate: MultitouchBridgeDelegate?

    private var handle: UnsafeMutableRawPointer?
    private var devices: [MTDeviceRef] = []
    // Keep the array owning the raw device pointers alive until devices stop.
    private var deviceList: CFArray?
    private(set) var sessionID = UUID()
    private var createList: CreateListFunction?
    private var register: RegisterFunction?
    private var unregister: UnregisterFunction?
    private var startDevice: StartFunction?
    private var stopDevice: StopFunction?
    private var sensorDimensions: SensorDimensionsFunction?
    private var touchStateLock = os_unfair_lock()
    private var latestFingerCountStorage = 0
    private var lastCallbackAt = ProcessInfo.processInfo.systemUptime

    var secondsSinceLastCallback: Double {
        os_unfair_lock_lock(&touchStateLock)
        defer { os_unfair_lock_unlock(&touchStateLock) }
        return ProcessInfo.processInfo.systemUptime - lastCallbackAt
    }
    private var deliveryGate = TouchFrameDeliveryGate()

    private(set) var isRunning = false

    init() {
        loadFramework()
    }

    deinit {
        stop()
        if let handle { dlclose(handle) }
    }

    var isAvailable: Bool {
        handle != nil && createList != nil && register != nil && startDevice != nil
    }

    var latestFingerCount: Int {
        os_unfair_lock_lock(&touchStateLock)
        defer { os_unfair_lock_unlock(&touchStateLock) }
        return latestFingerCountStorage
    }

    @discardableResult
    func start() -> Bool {
        guard !isRunning,
              let createList,
              let register,
              let startDevice,
              let list = createList()?.takeRetainedValue()
        else { return false }

        deviceList = list
        sessionID = UUID()
        resetTouchState()
        os_unfair_lock_lock(&callbackLock)
        activeBridge = self
        os_unfair_lock_unlock(&callbackLock)

        let count = CFArrayGetCount(list)
        for index in 0..<count {
            guard let value = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: value)
            if let sensorDimensions {
                var rows: Int32 = 0
                var columns: Int32 = 0
                guard sensorDimensions(device, &rows, &columns) == 0, rows >= 10 else {
                    continue
                }
            }
            register(device, contactCallback)
            startDevice(device, 0)
            devices.append(device)
        }
        isRunning = !devices.isEmpty
        if !isRunning {
            clearActiveBridge()
            deviceList = nil
        }
        return isRunning
    }

    func stop() {
        clearActiveBridge()
        sessionID = UUID()
        resetTouchState()
        guard isRunning else { return }
        for device in devices {
            unregister?(device, contactCallback)
            stopDevice?(device)
        }
        devices.removeAll()
        deviceList = nil
        isRunning = false
    }

    fileprivate func receive(pointer: UnsafeMutableRawPointer?, count: Int, timestamp: Double) {
        guard count > 0 else {
            let frame = TouchFrame(timestamp: timestamp, touches: [])
            guard prepareForDelivery(frame) else { return }
            delegate?.multitouchBridge(self, received: frame)
            return
        }
        guard let pointer else { return }

        let raw = pointer.bindMemory(to: MTTouchRaw.self, capacity: count)
        var touches: [TouchPoint] = []
        touches.reserveCapacity(count)
        for index in 0..<count {
            let touch = raw[index]
            guard touch.state == 3 || touch.state == 4 else { continue }
            touches.append(.init(
                // pathIndex is the persistent identifier for the lifetime of a
                // contact. fingerID is hardware-dependent and can be reused by
                // multiple contacts, which made stationary taps look like motion.
                id: touch.pathIndex,
                x: touch.normalizedVector.position.x,
                y: touch.normalizedVector.position.y,
                pressure: touch.zTotal
            ))
        }
        let frame = TouchFrame(timestamp: timestamp, touches: touches)
        guard prepareForDelivery(frame) else { return }
        delegate?.multitouchBridge(self, received: frame)
    }

    private func prepareForDelivery(_ frame: TouchFrame) -> Bool {
        os_unfair_lock_lock(&touchStateLock)
        defer { os_unfair_lock_unlock(&touchStateLock) }
        lastCallbackAt = ProcessInfo.processInfo.systemUptime
        latestFingerCountStorage = frame.touches.count
        return deliveryGate.shouldDeliver(frame)
    }

    private func resetTouchState() {
        os_unfair_lock_lock(&touchStateLock)
        latestFingerCountStorage = 0
        lastCallbackAt = ProcessInfo.processInfo.systemUptime
        deliveryGate.reset()
        os_unfair_lock_unlock(&touchStateLock)
    }

    private func clearActiveBridge() {
        os_unfair_lock_lock(&callbackLock)
        if activeBridge === self { activeBridge = nil }
        os_unfair_lock_unlock(&callbackLock)
    }

    private func loadFramework() {
        let path = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else { return }
        self.handle = handle
        createList = loadSymbol("MTDeviceCreateList", from: handle)
        register = loadSymbol("MTRegisterContactFrameCallback", from: handle)
        unregister = loadSymbol("MTUnregisterContactFrameCallback", from: handle)
        startDevice = loadSymbol("MTDeviceStart", from: handle)
        stopDevice = loadSymbol("MTDeviceStop", from: handle)
        sensorDimensions = loadSymbol("MTDeviceGetSensorDimensions", from: handle)
    }

    private func loadSymbol<T>(_ name: String, from handle: UnsafeMutableRawPointer) -> T? {
        guard let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: T.self)
    }
}

/// Raw trackpad frames commonly arrive around 125 Hz. Contact boundaries are
/// delivered immediately while stationary frames are capped at 60 Hz, reducing
/// main-actor work without adding lift or landing latency.
struct TouchFrameDeliveryGate: Sendable {
    var minimumInterval: Double
    private var lastDeliveredAt = -Double.infinity
    private var lastContactIDs: [Int32] = []

    init(minimumInterval: Double = 1.0 / 60.0) {
        self.minimumInterval = minimumInterval
    }

    mutating func shouldDeliver(_ frame: TouchFrame) -> Bool {
        // A device clock can restart after reconnecting. Keep small out-of-order
        // frames throttled, but do not freeze delivery behind the old clock.
        if frame.timestamp < lastDeliveredAt - 1 { reset() }
        let contactIDs = frame.touches.map(\.id).sorted()
        let isBoundary = contactIDs != lastContactIDs
        guard isBoundary || frame.timestamp - lastDeliveredAt >= minimumInterval else {
            return false
        }
        lastContactIDs = contactIDs
        lastDeliveredAt = frame.timestamp
        return true
    }

    mutating func reset() {
        lastDeliveredAt = -Double.infinity
        lastContactIDs.removeAll(keepingCapacity: true)
    }
}
