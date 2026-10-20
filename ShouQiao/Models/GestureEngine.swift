import Foundation
import CoreGraphics

enum GestureID: String {
    case bothOpen = "BOTH_OPEN"
    case bothFist = "BOTH_FIST"
    case thumbsUp = "THUMBS_UP"
    case sos = "SOS"
}

struct GestureCandidate {
    let id: GestureID?
    let confidence: Float

    static let none = GestureCandidate(id: nil, confidence: 0)

    var isEmpty: Bool { id == nil }
}

/// One MediaPipe hand. Coordinates are normalized x/y from 0...1.
struct Hand {
    static let wrist = 0
    static let thumbMcp = 2
    static let thumbTip = 4
    static let indexMcp = 5
    static let indexPip = 6
    static let indexTip = 8
    static let middleMcp = 9
    static let middlePip = 10
    static let middleTip = 12
    static let ringMcp = 13
    static let ringPip = 14
    static let ringTip = 16
    static let pinkyMcp = 17
    static let pinkyPip = 18
    static let pinkyTip = 20

    private static let tips = [indexTip, middleTip, ringTip, pinkyTip]
    private static let pips = [indexPip, middlePip, ringPip, pinkyPip]

    let points: [CGPoint]

    init?(points: [CGPoint]) {
        guard points.count >= 21 else { return nil }
        self.points = points
    }

    func x(_ index: Int) -> CGFloat { points[index].x }
    func y(_ index: Int) -> CGFloat { points[index].y }

    func distance(_ a: Int, _ b: Int) -> CGFloat {
        let dx = x(a) - x(b)
        let dy = y(a) - y(b)
        return sqrt(dx * dx + dy * dy)
    }

    var palmScale: CGFloat {
        max(distance(Self.wrist, Self.middleMcp), 0.04)
    }

    var extendedMask: Int {
        var mask = 0
        for i in 0..<4 where fingerRatio(i) > 1.60 {
            mask |= 1 << i
        }
        return mask
    }

    var openConfidence: Float {
        var sum: Float = 0
        for i in 0..<4 {
            sum += clamp((fingerRatio(i) - 1.35) / 0.35)
        }
        return sum / 4
    }

    var fingerFoldConfidence: Float {
        var sum: Float = 0
        for i in 0..<4 {
            sum += 1 - clamp((fingerRatio(i) - 1.10) / 0.55)
        }
        return sum / 4
    }

    var fistConfidence: Float {
        // A clearly raised or lowered thumb is a different gesture.
        if thumbUpConfidence >= 0.65 || thumbDownConfidence >= 0.65 {
            return 0
        }
        return fingerFoldConfidence
    }

    var thumbUpConfidence: Float {
        let ratio = distance(Self.thumbTip, Self.thumbMcp) / palmScale
        let distanceScore = clamp((1.45 - ratio) / 0.55)
        let lift = (y(Self.thumbMcp) - y(Self.thumbTip)) / palmScale
        let liftScore = clamp((lift - 0.05) / 0.25)
        return min(distanceScore, liftScore)
    }

    var thumbDownConfidence: Float {
        let ratio = distance(Self.thumbTip, Self.thumbMcp) / palmScale
        let distanceScore = clamp((1.45 - ratio) / 0.55)
        let drop = (y(Self.thumbTip) - y(Self.thumbMcp)) / palmScale
        let dropScore = clamp((drop - 0.10) / 0.30)
        return min(distanceScore, dropScore)
    }

    var isPlausible: Bool {
        for point in points {
            guard point.x.isFinite, point.y.isFinite,
                  point.x >= -0.20, point.x <= 1.20,
                  point.y >= -0.20, point.y <= 1.20 else {
                return false
            }
        }

        let scale = palmScale
        guard scale >= 0.045, scale <= 0.55 else { return false }

        let palmArea = abs(
            (x(Self.indexMcp) - x(Self.wrist)) * (y(Self.pinkyMcp) - y(Self.wrist))
                - (y(Self.indexMcp) - y(Self.wrist)) * (x(Self.pinkyMcp) - x(Self.wrist))
        ) * 0.5
        guard palmArea >= 0.0008 else { return false }

        for i in 0..<4 where distance(Self.tips[i], Self.pips[i]) < 0.010 {
            return false
        }
        return true
    }

    private func fingerRatio(_ index: Int) -> CGFloat {
        let tipToWrist = distance(Self.tips[index], Self.wrist)
        let pipToWrist = max(distance(Self.pips[index], Self.wrist), 0.03)
        return tipToWrist / pipToWrist
    }

    private func clamp(_ value: CGFloat) -> Float {
        Float(max(0, min(1, value)))
    }
}

struct HandFrame {
    let hands: [Hand]

    init(_ rawHands: [[CGPoint]]) {
        hands = rawHands.compactMap { Hand(points: $0) }
    }

    var isPlausible: Bool {
        !hands.isEmpty && hands.count <= 2 && hands.allSatisfy(\.isPlausible)
    }
}

/// Single-frame classifier for the core vocabulary.
final class PostureClassifier {
    static let staticThreshold: Float = 0.68
    static let mutexMargin: Float = 0.08

    func classify(_ frame: HandFrame) -> GestureCandidate {
        guard frame.isPlausible else { return .none }
        if frame.hands.count == 1 {
            return classifySingle(frame.hands[0])
        }
        if frame.hands.count == 2 {
            return classifyTwo(frame.hands[0], frame.hands[1])
        }
        return .none
    }

    func postureLabel(_ frame: HandFrame) -> String {
        guard let id = classify(frame).id else { return "" }
        switch id {
        case .bothOpen: return "双掌张开"
        case .bothFist: return "双拳"
        case .thumbsUp: return "竖拇指"
        case .sos: return "紧急求助"
        }
    }

    private func classifySingle(_ hand: Hand) -> GestureCandidate {
        let confidence = min(hand.fingerFoldConfidence, hand.thumbUpConfidence)
        guard confidence >= Self.staticThreshold else { return .none }
        return GestureCandidate(id: .thumbsUp, confidence: confidence)
    }

    private func classifyTwo(_ first: Hand, _ second: Hand) -> GestureCandidate {
        let open = min(first.openConfidence, second.openConfidence)
        let fist = min(first.fistConfidence, second.fistConfidence)

        let id: GestureID
        let best: Float
        let secondBest: Float
        if open >= fist {
            id = .bothOpen
            best = open
            secondBest = fist
        } else {
            id = .bothFist
            best = fist
            secondBest = open
        }

        guard best >= Self.staticThreshold,
              best - secondBest >= Self.mutexMargin else {
            return .none
        }
        return GestureCandidate(id: id, confidence: best)
    }
}

/// Confidence + several consecutive frames + duration + mutual exclusion.
final class GestureStateMachine {
    static let sosConfidenceThreshold: Float = 0.86
    static let sosHoldMs: Int64 = 5_000
    static let sosMinFrames = 20
    static let sosArmWindowMs: Int64 = 15_000
    static let noneResetMs: Int64 = 2_000

    private let staticMinFrames = 4
    private let staticStableMs: Int64 = 500

    private var candidateID: GestureID?
    private var candidateSince: Int64 = 0
    private var candidateFrames = 0
    private var emittedFor: GestureID?
    private var lastPhrase = ""
    private var lastEmissionAt: Int64 = 0

    private var sosArmed = false
    private var sosArmedAt: Int64 = 0
    private var noneSince: Int64 = 0
    private var fistHoldSince: Int64 = 0
    private var fistHoldFrames = 0
    private var sosEmitted = false

    func update(_ candidate: GestureCandidate, at now: Int64) -> String {
        guard let id = candidate.id else {
            resetStreak()
            fistHoldSince = 0
            fistHoldFrames = 0
            if noneSince == 0 { noneSince = now }
            if sosArmed && (now - sosArmedAt > Self.sosArmWindowMs
                || now - noneSince > Self.noneResetMs) {
                sosArmed = false
            }
            return ""
        }

        noneSince = 0
        if id != candidateID {
            candidateID = id
            candidateSince = now
            candidateFrames = 0
            emittedFor = nil
            fistHoldSince = 0
            fistHoldFrames = 0
        }

        candidateFrames += 1
        let stable = candidateFrames >= staticMinFrames
            && now - candidateSince >= staticStableMs

        switch id {
        case .bothOpen:
            if stable {
                sosArmed = true
                sosArmedAt = now
                sosEmitted = false
                if emittedFor != id {
                    emittedFor = id
                    return emit(GestureEngine.hello, cooldown: 2_500, now: now)
                }
            }
            return ""

        case .thumbsUp:
            sosArmed = false
            if stable && emittedFor != id {
                emittedFor = id
                return emit(GestureEngine.understood, cooldown: 2_500, now: now)
            }
            return ""

        case .bothFist:
            let armed = sosArmed && now - sosArmedAt <= Self.sosArmWindowMs
            if armed {
                if candidate.confidence >= Self.sosConfidenceThreshold {
                    if fistHoldSince == 0 { fistHoldSince = now }
                    fistHoldFrames += 1
                } else {
                    fistHoldSince = 0
                    fistHoldFrames = 0
                }

                if !sosEmitted && fistHoldSince > 0
                    && fistHoldFrames >= Self.sosMinFrames
                    && now - fistHoldSince >= Self.sosHoldMs {
                    sosEmitted = true
                    sosArmed = false
                    fistHoldSince = 0
                    fistHoldFrames = 0
                    emittedFor = id
                    return emit(GestureEngine.sos, cooldown: 700, now: now)
                }
                // While armed, a fist is an SOS attempt, not the normal WAIT
                // phrase. Releasing before 5 seconds produces no message.
                return ""
            }

            if stable && emittedFor != id {
                emittedFor = id
                return emit(GestureEngine.wait, cooldown: 700, now: now)
            }
            return ""

        case .sos:
            return ""
        }
    }

    func reset() {
        resetStreak()
        lastPhrase = ""
        lastEmissionAt = 0
        sosArmed = false
        sosArmedAt = 0
        noneSince = 0
        fistHoldSince = 0
        fistHoldFrames = 0
        sosEmitted = false
    }

    private func emit(_ phrase: String, cooldown: Int64, now: Int64) -> String {
        if phrase == lastPhrase && now - lastEmissionAt < cooldown {
            return ""
        }
        lastPhrase = phrase
        lastEmissionAt = now
        return phrase
    }

    private func resetStreak() {
        candidateID = nil
        candidateSince = 0
        candidateFrames = 0
        emittedFor = nil
    }
}

/// Facade used by the SwiftUI view model.
final class GestureEngine {
    static let none = ""
    static let sos = "SOS"
    static let hello = "你好，我想和你交流。"
    static let wait = "好的，请稍等。"
    static let understood = "我明白了，谢谢。"

    private let classifier = PostureClassifier()
    private let state = GestureStateMachine()

    func posture(_ hands: [[CGPoint]]) -> String {
        classifier.postureLabel(HandFrame(hands))
    }

    func update(_ hands: [[CGPoint]], at nowMs: Int64) -> String {
        let frame = HandFrame(hands)
        let candidate = frame.isPlausible ? classifier.classify(frame) : GestureCandidate.none
        return state.update(candidate, at: nowMs)
    }

    func candidate(_ hands: [[CGPoint]]) -> GestureCandidate {
        let frame = HandFrame(hands)
        return frame.isPlausible ? classifier.classify(frame) : GestureCandidate.none
    }

    func reset() {
        state.reset()
    }
}
