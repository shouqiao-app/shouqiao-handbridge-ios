import Combine
import CoreMedia
import Foundation
import MediaPipeTasksVision
import UIKit

/// Wraps MediaPipe HandLandmarker in live-stream mode.
final class HandLandmarkerService: NSObject, ObservableObject {
    @Published private(set) var lastError: String?

    var onHands: (([[CGPoint]], Int) -> Void)?

    private var handLandmarker: HandLandmarker?
    private var lastTimestampMs = 0
    private let processingQueue = DispatchQueue(
        label: "org.signbridge.hand-landmarker",
        qos: .userInitiated
    )

    override init() {
        super.init()
        configure()
    }

    func process(_ sampleBuffer: CMSampleBuffer, timestampMs: Int) {
        guard let handLandmarker else { return }
        let timestamp = max(timestampMs, lastTimestampMs + 1)
        lastTimestampMs = timestamp

        do {
            // Build MPImage while the camera sample buffer is still valid.
            let mpImage = try MPImage(sampleBuffer: sampleBuffer)
            processingQueue.async {
                autoreleasepool {
                    do {
                        try handLandmarker.detectAsync(
                            image: mpImage,
                            timestampInMilliseconds: timestamp
                        )
                    } catch {
                        DispatchQueue.main.async {
                            self.lastError = error.localizedDescription
                        }
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.lastError = error.localizedDescription
            }
        }
    }

    private func configure() {
        guard let modelPath = Bundle.main.path(
            forResource: "hand_landmarker",
            ofType: "task"
        ) else {
            lastError = "hand_landmarker.task 未加入 App Bundle"
            return
        }

        let options = HandLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.runningMode = .liveStream
        options.numHands = 2
        options.minHandDetectionConfidence = 0.6
        options.minHandPresenceConfidence = 0.6
        options.minTrackingConfidence = 0.6
        options.handLandmarkerLiveStreamDelegate = self

        do {
            handLandmarker = try HandLandmarker(options: options)
        } catch {
            lastError = error.localizedDescription
        }
    }
}

extension HandLandmarkerService: HandLandmarkerLiveStreamDelegate {
    func handLandmarker(
        _ handLandmarker: HandLandmarker,
        didFinishDetection result: HandLandmarkerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        if let error {
            DispatchQueue.main.async {
                self.lastError = error.localizedDescription
            }
            return
        }
        guard let result else { return }

        let hands: [[CGPoint]] = result.landmarks.map { hand in
            hand.map { landmark in
                CGPoint(x: CGFloat(landmark.x), y: CGFloat(landmark.y))
            }
        }
        DispatchQueue.main.async {
            self.onHands?(hands, timestampInMilliseconds)
        }
    }
}
