import AVFoundation
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        TabView {
            GestureView(model: model)
                .tabItem {
                    Label("手势", systemImage: "hand.raised.fill")
                }

            VoiceView(
                speech: model.speechRecognizer,
                speak: { model.speakText($0) }
            )
            .tabItem {
                Label("对话", systemImage: "waveform.circle.fill")
            }

            HelpView(model: model)
                .tabItem {
                    Label("求助", systemImage: "sos.circle.fill")
                }

            SettingsView(model: model)
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle")
                }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

private struct GestureView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            ZStack {
                CameraPreview(session: model.camera.session)
                    .ignoresSafeArea()

                HandOverlay(hands: model.latestHands)
                    .ignoresSafeArea()

                LinearGradient(
                    colors: [.black.opacity(0.55), .clear, .black.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 12) {
                    HStack {
                        Text("手桥")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Spacer()
                        Label(model.posture, systemImage: "viewfinder")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.5), in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                    Spacer()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("当前表达")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(model.phrase.isEmpty ? "等待核心手势…" : model.phrase)
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if !model.cameraMessage.isEmpty {
                            Text(model.cameraMessage)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        Text(model.performanceText)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.7))

                        Text(model.debugText)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.yellow.opacity(0.9))

                        HStack(spacing: 10) {
                            Button {
                                model.resetGesture()
                            } label: {
                                Label("重置", systemImage: "arrow.counterclockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)

                            Button {
                                model.showHelp = true
                            } label: {
                                Label("求助卡片", systemImage: "doc.text.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }

                        Button {
                            model.startWordRecording()
                        } label: {
                            Label("识别词语（22 词）", systemImage: "text.bubble.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                    }
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $model.showHelp) {
                NavigationStack {
                    HelpView(model: model)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("完成") { model.showHelp = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $model.showWordCandidates) {
                NavigationStack {
                    WordCandidateView(model: model)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("关闭") {
                                    model.cancelWordRecording()
                                    model.showWordCandidates = false
                                }
                            }
                        }
                }
            }
        }
    }
}

private struct WordCandidateView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        List {
            Section {
                Text(model.wordStatus)
                    .foregroundStyle(.secondary)
            }

            if !model.wordCandidates.isEmpty {
                Section("候选词") {
                    ForEach(model.wordCandidates) { candidate in
                        Button {
                            model.chooseWord(candidate)
                        } label: {
                            HStack {
                                Text(candidate.label)
                                    .font(.title3.bold())
                                Spacer()
                                Text(String(format: "%.3f", candidate.distance))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Section {
                    Button {
                        model.startWordRecording()
                    } label: {
                        Label("重新采集 3 秒", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .navigationTitle("词语识别")
    }
}

private struct VoiceView: View {
    @ObservedObject var speech: SpeechRecognizer
    let speak: (String) -> Void

    @State private var editableText = ""
    @State private var showPresentation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("让对方说，屏幕替他说")
                        .font(.title3.bold())

                    Text(speech.status)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $editableText)
                        .font(.system(size: 28, weight: .semibold))
                        .frame(minHeight: 220)
                        .padding(12)
                        .background(Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 16))

                    HStack {
                        Button {
                            speech.toggle()
                        } label: {
                            Label(
                                speech.isListening ? "停止听" : "开始听",
                                systemImage: speech.isListening ? "stop.circle.fill" : "mic.circle.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(speech.isListening ? .red : .teal)

                        Button {
                            speak(editableText)
                        } label: {
                            Label("朗读给对方", systemImage: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            speech.clear()
                            editableText = ""
                        } label: {
                            Label("清空", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        showPresentation = true
                    } label: {
                        Label("全屏大字", systemImage: "rectangle.expand.vertical")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                }
                .padding(18)
            }
            .navigationTitle("双向对话")
            .onChange(of: speech.transcript) { value in
                editableText = value
            }
            .fullScreenCover(isPresented: $showPresentation) {
                PresentationView(text: editableText)
            }
        }
    }
}

private struct PresentationView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Text(text.isEmpty ? "等待字幕…" : text)
                .font(.system(size: 52, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(20)
            }
        }
    }
}

private struct HelpView: View {
    @ObservedObject var model: AppModel
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("求助信息")
                        .font(.title2.bold())

                    Text(model.locationStatus)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $model.helpText)
                        .frame(minHeight: 260)
                        .padding(8)
                        .background(Color(.secondarySystemBackground),
                                    in: RoundedRectangle(cornerRadius: 14))

                    HStack {
                        Button {
                            UIPasteboard.general.string = model.helpText
                            copied = true
                        } label: {
                            Label(copied ? "已复制" : "复制", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)

                        ShareLink(item: model.helpText) {
                            Label("分享 / 发送", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            model.startSosLocation()
                        } label: {
                            Label("重新定位", systemImage: "location.fill")
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("提示：如果 8 秒内没有定位结果，仍然可以直接分享上面的求助文字。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(18)
            }
            .navigationTitle("紧急求助")
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section("设备状态") {
                    Text("词库：\(model.wordCount) 个词")
                    if !model.cameraMessage.isEmpty {
                        Text(model.cameraMessage).foregroundStyle(.orange)
                    }
                }

                Section("核心手势") {
                    Label("双掌张开 → 交流", systemImage: "hands.and.sparkles.fill")
                    Label("双拳 → 稍等", systemImage: "hand.raised.fill")
                    Label("竖拇指 → 明白", systemImage: "hand.thumbsup.fill")
                    Label("双掌张开后双拳保持 5 秒 → 紧急求助",
                          systemImage: "exclamationmark.triangle.fill")
                }

                Section("稳定性策略") {
                    Text("普通手势：置信度 ≥ 0.80，连续 5 帧且持续 700ms。")
                    Text("SOS：置信度 ≥ 0.92，双拳连续保持 5 秒，中途断帧会重新计时。")
                    Text("互斥：最高候选必须领先第二名至少 0.12。")
                }

                Section("iOS 说明") {
                    Text("iOS 不提供公开的 GPS/网络 Provider 切换接口。定位先使用最高精度，2.5 秒后降低精度让系统使用 Wi-Fi/基站，8 秒总超时。")
                    Text("当前原生版先实现核心手势、SOS、定位、语音播报、分享和画面文字识别。")
                }
            }
            .navigationTitle("关于手桥")
        }
    }
}

private struct HandOverlay: View {
    let hands: [[CGPoint]]

    private let connections: [(Int, Int)] = [
        (0, 1), (1, 2), (2, 3), (3, 4),
        (0, 5), (5, 6), (6, 7), (7, 8),
        (0, 9), (9, 10), (10, 11), (11, 12),
        (0, 13), (13, 14), (14, 15), (15, 16),
        (0, 17), (17, 18), (18, 19), (19, 20),
        (5, 9), (9, 13), (13, 17)
    ]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(Array(hands.enumerated()), id: \.offset) { item in
                    let hand = item.element
                    Path { path in
                        for (a, b) in connections
                            where a < hand.count && b < hand.count {
                            path.move(to: map(hand[a], size: geometry.size))
                            path.addLine(to: map(hand[b], size: geometry.size))
                        }
                    }
                    .stroke(
                        Color.green.opacity(0.9),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round)
                    )

                    ForEach(0..<hand.count, id: \.self) { index in
                        Circle()
                            .fill(index == 0 ? Color.orange : Color.green)
                            .frame(width: 5, height: 5)
                            .position(map(hand[index], size: geometry.size))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func map(_ point: CGPoint, size: CGSize) -> CGPoint {
        // The front camera preview is mirrored.
        CGPoint(
            x: (1 - point.x) * size.width,
            y: point.y * size.height
        )
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.previewLayer.session = session
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}
