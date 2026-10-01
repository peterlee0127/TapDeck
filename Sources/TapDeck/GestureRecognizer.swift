import Foundation

struct GestureDetection: Equatable, Sendable {
    var gesture: GestureKind
    var timestamp: Double
}

/// Pure state machine. Hardware callbacks feed frames into it; tests can feed synthetic frames.
struct GestureRecognizer: Sendable {
    var tapDuration = 0.36
    var movementTolerance: Float = 0.045

    private var tapStartedAt: Double?
    private var maximumFingerCount = 0
    private var startPositions: [Int32: (x: Float, y: Float)] = [:]
    private var startCentroid: (x: Float, y: Float)?
    private var maximumCentroidMovement: Float = 0
    private var maximumMeanFingerMovement: Float = 0
    private var physicalClickOccurred = false
    private var isSequenceValid = true
    private var incompleteFrameCount = 0
    private var firstIncompleteAt: Double?
    private var ignoringUntilRelease = false

    mutating func process(frame: TouchFrame) -> [GestureDetection] {
        let count = frame.touches.count

        // After recognizing or rejecting a gesture while fingers are still lifting,
        // do not let those remaining contacts start a second gesture.
        if ignoringUntilRelease {
            if count == 0 {
                ignoringUntilRelease = false
                resetSequence()
            }
            return []
        }

        let previousMaximumFingerCount = maximumFingerCount
        maximumFingerCount = max(maximumFingerCount, count)
        if maximumFingerCount != previousMaximumFingerCount,
           (2...4).contains(maximumFingerCount) {
            // Start the tap window only after every required finger has landed.
            // Counting from the first finger unfairly penalizes natural staggered contact.
            tapStartedAt = frame.timestamp
            startPositions = Dictionary(uniqueKeysWithValues: frame.touches.map {
                ($0.id, (x: $0.x, y: $0.y))
            })
            startCentroid = centroid(of: frame.touches)
            maximumCentroidMovement = 0
            maximumMeanFingerMovement = 0
            incompleteFrameCount = 0
            firstIncompleteAt = nil
        }
        if maximumFingerCount > 4 { isSequenceValid = false }

        // A contact can disappear for a single raw frame while its state changes. Require
        // two consecutive frames below the peak even when the first one is completely
        // empty. This mirrors MiddleDrag's stable-frame debounce and avoids turning a
        // momentary dropout into a click.
        if (2...4).contains(maximumFingerCount),
           count < maximumFingerCount {
            if firstIncompleteAt == nil { firstIncompleteAt = frame.timestamp }
            incompleteFrameCount += 1
            if incompleteFrameCount >= 2 {
                return finishSequence(
                    completedAt: firstIncompleteAt ?? frame.timestamp,
                    detectionTimestamp: frame.timestamp,
                    remainingFingerCount: count
                )
            }
        } else {
            incompleteFrameCount = 0
            firstIncompleteAt = nil
        }

        if count == 0 {
            // There was no tap candidate, so an empty frame merely clears landing noise.
            if maximumFingerCount < 2 {
                resetSequence()
            }
            return []
        }

        // MiddleDrag measures tap travel using the centroid. It is less sensitive than
        // rejecting on the noisiest single contact, but centroid alone could mistake a
        // quick pinch for a tap. Use centroid travel as the primary threshold and retain
        // a generous mean per-finger guard for shape-changing gestures.
        if tapStartedAt != nil,
           count == maximumFingerCount,
           let currentCentroid = centroid(of: frame.touches),
           let startCentroid {
            let centroidDX = currentCentroid.x - startCentroid.x
            let centroidDY = currentCentroid.y - startCentroid.y
            maximumCentroidMovement = max(
                maximumCentroidMovement,
                sqrt(centroidDX * centroidDX + centroidDY * centroidDY)
            )

            var totalMovement: Float = 0
            var matchedTouchCount: Float = 0
            for touch in frame.touches {
                guard let start = startPositions[touch.id] else { continue }
                let dx = touch.x - start.x
                let dy = touch.y - start.y
                totalMovement += sqrt(dx * dx + dy * dy)
                matchedTouchCount += 1
            }
            if matchedTouchCount > 0 {
                maximumMeanFingerMovement = max(
                    maximumMeanFingerMovement,
                    totalMovement / matchedTouchCount
                )
            }
        }

        return []
    }

    private mutating func finishSequence(
        completedAt: Double,
        detectionTimestamp: Double,
        remainingFingerCount: Int
    ) -> [GestureDetection] {
        var detections: [GestureDetection] = []
        if let tapStartedAt,
           (2...4).contains(maximumFingerCount),
           isSequenceValid,
           !physicalClickOccurred,
           completedAt - tapStartedAt <= tapDuration,
           maximumCentroidMovement <= movementTolerance,
           maximumMeanFingerMovement <= movementTolerance * 2 {
            let gesture: GestureKind = switch maximumFingerCount {
            case 2: .twoFingerTap
            case 3: .threeFingerTap
            default: .fourFingerTap
            }
            detections.append(.init(gesture: gesture, timestamp: detectionTimestamp))
        }
        resetSequence()
        ignoringUntilRelease = remainingFingerCount > 0
        return detections
    }

    mutating func physicalClick(fingerCount: Int, timestamp: Double) -> GestureDetection? {
        guard (2...4).contains(fingerCount), !physicalClickOccurred else { return nil }
        physicalClickOccurred = true
        let gesture: GestureKind = switch fingerCount {
        case 2: .twoFingerClick
        case 3: .threeFingerClick
        default: .fourFingerClick
        }
        return .init(gesture: gesture, timestamp: timestamp)
    }

    mutating func reset() {
        ignoringUntilRelease = false
        resetSequence()
    }

    private mutating func resetSequence() {
        tapStartedAt = nil
        maximumFingerCount = 0
        startPositions.removeAll(keepingCapacity: true)
        startCentroid = nil
        maximumCentroidMovement = 0
        maximumMeanFingerMovement = 0
        physicalClickOccurred = false
        isSequenceValid = true
        incompleteFrameCount = 0
        firstIncompleteAt = nil
    }

    private func centroid(of touches: [TouchPoint]) -> (x: Float, y: Float)? {
        guard !touches.isEmpty else { return nil }
        let totals = touches.reduce(into: (x: Float(0), y: Float(0))) {
            $0.x += $1.x
            $0.y += $1.y
        }
        let count = Float(touches.count)
        return (totals.x / count, totals.y / count)
    }
}

/// Recognizes the documented Force Touch second pressure stage and emits once per press.
struct PressureStageRecognizer: Sendable {
    private var isLatched = false

    mutating func process(stage: Int, fingerCount: Int, timestamp: Double) -> GestureDetection? {
        if stage == 0 || fingerCount == 0 {
            isLatched = false
            return nil
        }
        guard fingerCount == 1, stage >= 2, !isLatched else { return nil }
        isLatched = true
        return .init(gesture: .oneFingerForceTouch, timestamp: timestamp)
    }

    mutating func reset() {
        isLatched = false
    }
}

/// Tracks the first pressure stage separately from tap-to-click mouse events.
/// A physical multi-finger click is consumed only once per press.
struct PhysicalClickPressureRecognizer: Sendable {
    private var confirmedFingerCount: Int?
    private var wasConsumed = false

    mutating func process(stage: Int, fingerCount: Int) {
        if stage == 0 || fingerCount == 0 {
            reset()
            return
        }
        guard stage >= 1, (2...4).contains(fingerCount) else { return }
        confirmedFingerCount = fingerCount
    }

    mutating func consume(fingerCount: Int) -> Bool {
        guard confirmedFingerCount == fingerCount, !wasConsumed else { return false }
        wasConsumed = true
        return true
    }

    mutating func reset() {
        confirmedFingerCount = nil
        wasConsumed = false
    }
}
