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

            HelpView(model: model)
                .tabItem {
                    Label("求助", systemImage: "sos.circle.fill")
                }

            SettingsView()
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
    var body: some View {
        NavigationStack {
            List {
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
