import Combine
import CoreMedia
import Foundation
import MediaPipeTasksVision

/// Pose is used only for the lightweight word-template feature encoder.
final class PoseLandmarkerService: NSObject, ObservableObject {
    @Published private(set) var lastError: String?
    @Published private(set) var latestLandmarks: [CGPoint]?

    var onPose: (([[CGPoint]], Int) -> Void)?

    private var poseLandmarker: PoseLandmarker?
    private var lastTimestampMs = 0
    private let processingQueue = DispatchQueue(
        label: "org.signbridge.pose-landmarker",
        qos: .userInitiated
    )

    override init() {
        super.init()
        configure()
    }

    func process(_ sampleBuffer: CMSampleBuffer, timestampMs: Int) {
        guard let poseLandmarker else { return }
        let timestamp = max(timestampMs, lastTimestampMs + 1)
        lastTimestampMs = timestamp

        do {
            let mpImage = try MPImage(sampleBuffer: sampleBuffer)
            processingQueue.async {
                autoreleasepool {
                    do {
                        try poseLandmarker.detectAsync(
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
        guard let path = Bundle.main.path(
            forResource: "pose_landmarker_lite",
            ofType: "task"
        ) else {
            lastError = "pose_landmarker_lite.task 未加入 App Bundle"
            return
        }
        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = path
        options.runningMode = .liveStream
        options.numPoses = 1
        options.minPoseDetectionConfidence = 0.3
        options.minPosePresenceConfidence = 0.3
        options.minTrackingConfidence = 0.3
        options.poseLandmarkerLiveStreamDelegate = self

        do {
            poseLandmarker = try PoseLandmarker(options: options)
        } catch {
            lastError = error.localizedDescription
        }
    }
}

extension PoseLandmarkerService: PoseLandmarkerLiveStreamDelegate {
    func poseLandmarker(
        _ poseLandmarker: PoseLandmarker,
        didFinishDetection result: PoseLandmarkerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        if let error {
            DispatchQueue.main.async {
                self.lastError = error.localizedDescription
            }
            return
        }
        guard let result,
              let first = result.landmarks.first else {
            DispatchQueue.main.async {
                self.latestLandmarks = nil
            }
            return
        }
        let points = first.map {
            CGPoint(x: CGFloat($0.x), y: CGFloat($0.y))
        }
        DispatchQueue.main.async {
            self.latestLandmarks = points
            self.onPose?([points], timestampInMilliseconds)
        }
    }
}
