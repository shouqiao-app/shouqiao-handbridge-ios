import Combine
import Foundation
import UIKit

final class AppModel: ObservableObject {
    @Published var posture = "等待手势"
    @Published var phrase = ""
    @Published var helpText = ""
    @Published var locationStatus = "位置：紧急手势时临时获取"
    @Published var ocrText = "等待识别"
    @Published var cameraMessage = ""
    @Published var showHelp = false
    @Published var performanceText = "分析 0.0 帧/秒 · 处理 0.0 毫秒"

    let camera = CameraManager()
    let handService = HandLandmarkerService()
    let location = SosLocationController()

    private let engine = GestureEngine()
    private let speech = SpeechController()
    private let ocr = SceneTextRecognizer()
    private var cancellables = Set<AnyCancellable>()
    private var analysisFrames = 0
    private var lastMetricAt = CFAbsoluteTimeGetCurrent()
    private var lastProcessingMs = 0.0

    init() {
        handService.onHands = { [weak self] hands, capturedAt in
            DispatchQueue.main.async {
                self?.handle(hands, capturedAt: capturedAt)
            }
        }

        let service = handService
        camera.onSampleBuffer = { sampleBuffer in
            service.process(
                sampleBuffer,
                timestampMs: Int(Date().timeIntervalSince1970 * 1000)
            )
        }

        location.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.locationStatus = value
            }
            .store(in: &cancellables)

        location.$message
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                if !value.isEmpty {
                    self?.helpText = value
                }
            }
            .store(in: &cancellables)

        camera.$permissionDenied
            .receive(on: RunLoop.main)
            .sink { [weak self] denied in
                if denied {
                    self?.cameraMessage = "未授权摄像头，可在系统设置中开启。"
                }
            }
            .store(in: &cancellables)

        handService.$lastError
            .receive(on: RunLoop.main)
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.cameraMessage = error
            }
            .store(in: &cancellables)
    }

    func start() {
        camera.start()
    }

    func stop() {
        camera.stop()
        location.cancel()
        speech.stop()
    }

    func resetGesture() {
        engine.reset()
        posture = "等待手势"
        phrase = ""
    }

    func startSosLocation() {
        location.start()
    }

    func recognizeSceneText() {
        guard let latestImage = camera.snapshotImage() else {
            ocrText = "还没有可识别的画面"
            return
        }
        ocrText = "正在识别画面文字…"
        ocr.recognize(image: latestImage) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    self?.ocrText = text.isEmpty ? "未识别到文字" : text
                case .failure(let error):
                    self?.ocrText = "识别失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func handle(_ hands: [[CGPoint]], capturedAt: Int) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        let label = engine.posture(hands)
        let nextPosture = label.isEmpty ? "未识别" : label
        if nextPosture != posture {
            posture = nextPosture
        }

        let event = engine.update(hands, at: now)
        if !event.isEmpty {
            if event == GestureEngine.sos {
                phrase = "检测到紧急求助"
                showHelp = true
                helpText = "位置：正在获取，最多等待 8 秒…"
                location.start()
            } else {
                phrase = event
                speech.speak(event)
            }
        }

        lastProcessingMs = max(0, Double(Int(Date().timeIntervalSince1970 * 1000) - capturedAt))
        analysisFrames += 1
        let elapsed = CFAbsoluteTimeGetCurrent() - lastMetricAt
        if elapsed >= 1.0 {
            let fps = Double(analysisFrames) / elapsed
            performanceText = String(
                format: "分析 %.1f 帧/秒 · 端到端 %.1f 毫秒",
                fps,
                lastProcessingMs
            )
            analysisFrames = 0
            lastMetricAt = CFAbsoluteTimeGetCurrent()
        }
    }
}
