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
    @Published var debugText = "手 0 · — 0.00"
    @Published var wordCandidates: [WordCandidate] = []
    @Published var wordStatus = "词语识别未开始"
    @Published var showWordCandidates = false
    @Published var latestHands: [[CGPoint]] = []

    let camera = CameraManager()
    let handService = HandLandmarkerService()
    let poseService = PoseLandmarkerService()
    let location = SosLocationController()
    let speechRecognizer = SpeechRecognizer()

    var wordCount: Int { wordEngine.labels.count }
    var wordLoadError: String? { wordEngine.loadError }

    private let engine = GestureEngine()
    private let wordEngine = WordTemplateEngine()
    private let speech = SpeechController()
    private let ocr = SceneTextRecognizer()
    private var cancellables = Set<AnyCancellable>()
    private var analysisFrames = 0
    private var lastMetricAt = CFAbsoluteTimeGetCurrent()
    private var lastProcessingMs = 0.0
    private let recordingLock = NSLock()
    private var recordingActive = false
    private var recordedFeatures: [[Float]] = []
    private var wordTimer: DispatchWorkItem?

    init() {
        handService.onHands = { [weak self] hands, capturedAt in
            DispatchQueue.main.async {
                self?.handle(hands, capturedAt: capturedAt)
            }
        }

        let service = handService
        let poseService = poseService
        let recordingLock = recordingLock
        camera.onSampleBuffer = { [weak self] sampleBuffer in
            guard let self else { return }
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            service.process(
                sampleBuffer,
                timestampMs: timestamp
            )
            recordingLock.lock()
            let recording = self.recordingActive
            recordingLock.unlock()
            if recording {
                poseService.process(sampleBuffer, timestampMs: timestamp)
            }
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

        poseService.$lastError
            .receive(on: RunLoop.main)
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.wordStatus = "姿态模型：\(error)"
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
        cancelWordRecording()
    }

    func resetGesture() {
        engine.reset()
        posture = "等待手势"
        phrase = ""
    }

    func startSosLocation() {
        location.start()
    }

    func speakText(_ text: String) {
        speech.speak(text)
    }

    func startWordRecording() {
        guard wordEngine.loadError == nil else {
            wordStatus = wordEngine.loadError ?? "词库不可用"
            showWordCandidates = true
            return
        }
        recordingLock.lock()
        recordingActive = true
        recordingLock.unlock()
        recordedFeatures.removeAll()
        wordCandidates = []
        wordStatus = "请做完整词语动作，约 3 秒（需要双手和上半身入镜）"
        showWordCandidates = true
        wordTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.finishWordRecording()
        }
        wordTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }

    func cancelWordRecording() {
        recordingLock.lock()
        recordingActive = false
        recordingLock.unlock()
        wordTimer?.cancel()
        wordTimer = nil
        recordedFeatures.removeAll()
    }

    func chooseWord(_ candidate: WordCandidate) {
        phrase = candidate.label
        speech.speak(candidate.label)
        showWordCandidates = false
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
        latestHands = hands
        let candidate = engine.candidate(hands)
        debugText = String(
            format: "手 %d · %@ %.2f",
            hands.count,
            candidate.id?.rawValue ?? "—",
            candidate.confidence
        )
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

        recordingLock.lock()
        let recording = recordingActive
        recordingLock.unlock()
        if recording, !hands.isEmpty, let pose = poseService.latestLandmarks,
           let feature = WordFeatureEncoder.encode(hands: hands, pose: pose) {
            recordedFeatures.append(feature)
            wordStatus = "正在采集动作… \(recordedFeatures.count) 帧"
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

    private func finishWordRecording() {
        recordingLock.lock()
        recordingActive = false
        recordingLock.unlock()
        wordTimer = nil
        let frames = recordedFeatures
        recordedFeatures.removeAll()
        guard frames.count >= 3 else {
            wordStatus = "没有采集到足够的双手/上半身动作，请靠近摄像头重试"
            return
        }
        wordStatus = "正在匹配词库…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let matches = self?.wordEngine.match(frames) ?? []
            DispatchQueue.main.async {
                guard let self else { return }
                self.wordCandidates = matches
                self.wordStatus = matches.isEmpty
                    ? "没有找到匹配词，请重试"
                    : "请从候选词中选择实际表达"
            }
        }
    }
}
