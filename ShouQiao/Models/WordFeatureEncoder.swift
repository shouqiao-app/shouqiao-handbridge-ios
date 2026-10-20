import CoreGraphics
import Foundation

/// Mirrors the Android 2.0 WordFeatureEncoder:
/// 22 pose values + 2×42 hand values + 2 hand-presence flags = 108.
enum WordFeatureEncoder {
    private static let poseKeys = [0, 9, 10, 11, 12, 13, 14, 15, 16, 23, 24]

    static func encode(hands: [[CGPoint]], pose: [CGPoint]) -> [Float]? {
        guard pose.count > 24 else { return nil }

        let centerX = (pose[11].x + pose[12].x) / 2
        let centerY = (pose[11].y + pose[12].y) / 2
        let shoulderX = pose[11].x - pose[12].x
        let shoulderY = pose[11].y - pose[12].y
        let scale = sqrt(shoulderX * shoulderX + shoulderY * shoulderY)
        guard scale >= 0.015 else { return nil }

        var features = [Float](repeating: 0, count: 108)
        var index = 0

        for key in poseKeys {
            features[index] = clamp((pose[key].x - centerX) / scale)
            features[index + 1] = clamp((pose[key].y - centerY) / scale)
            index += 2
        }

        let orderedHands = hands
            .sorted { ($0.first?.x ?? 0) < ($1.first?.x ?? 0) }
            .prefix(2)

        for (handIndex, hand) in orderedHands.enumerated() {
            features[106 + handIndex] = 1
            for point in hand.prefix(21) {
                features[index] = clamp((point.x - centerX) / scale)
                features[index + 1] = clamp((point.y - centerY) / scale)
                index += 2
            }
        }
        return features
    }

    private static func clamp(_ value: CGFloat) -> Float {
        Float(min(5, max(-5, value)))
    }
}
