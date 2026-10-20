# 手桥原生 iOS 工程

这是从 Android 版迁移出的 **SwiftUI 原生 iOS 工程骨架**，不是可直接 sideload 的 IPA。iOS 安装必须经过 Xcode 编译和 Apple 签名。

## 已包含

- AVFoundation 前置摄像头预览
- MediaPipe Tasks iOS `HandLandmarker` 手部 21 点
- 核心手势：双掌张开、双拳、竖拇指、SOS
- 置信阈值、互斥判断、连续帧校验、SOS 5 秒持续检测
- CoreLocation 紧急定位：最高精度优先，2.5 秒后降低精度，8 秒总超时
- 经纬度、文字地址、Apple 地图链接
- AVSpeechSynthesizer 中文播报
- Vision 中文画面文字识别
- SwiftUI 求助卡片、复制和系统分享

## 在 Mac 上构建

如果暂时没有 Mac，请先看 [INSTALL_ON_IPHONE.md](INSTALL_ON_IPHONE.md)：工程已附带 GitHub Actions 云构建工作流，可以生成 unsigned IPA，再用 Sideloadly/AltStore 在 Windows 上签名安装。

1. 安装 Xcode 15 或更新版本。
2. 安装 XcodeGen 和 CocoaPods：

   ```bash
   brew install xcodegen cocoapods
   ```

3. 进入本目录并生成工程：

   ```bash
   cd ShouQiao
   xcodegen generate
   pod install
   ```

4. 打开 `ShouQiao.xcworkspace`。
5. 在 Xcode 的 Signing & Capabilities 中选择你的 Team，并把 Bundle Identifier 改成你自己的唯一标识。
6. 连接 iPhone，选择真机运行。

## 首次运行前

- 确认 `ShouQiao/Resources/hand_landmarker.task` 被加入 App Bundle。
- 允许摄像头、定位权限。
- 如果要上线 App Store，还需要 App Store Connect 记录、隐私说明、图标和审核。
- 免费 Apple ID 只能做短期真机调试；TestFlight / 上架需要 Apple Developer Program。

## 平台差异

- iOS 不提供 Android 那样的 `gps` / `network` Provider 切换接口。定位逻辑先请求最高精度（通常走 GPS），2.5 秒后降低精度让系统使用 Wi-Fi/基站，8 秒总超时。
- 当前原生版没有移植 Vosk 离线模型；语音输出使用系统 TTS，画面文字使用 Apple Vision。后续可接入 iOS 版 Vosk 或 Apple 的离线语音识别。
- MediaPipe iOS API 会随 pod 版本变化。如果 `HandLandmarkerLiveStreamDelegate` 或 `MPImage` 初始化签名不一致，按 Xcode 的编译提示调整 `HandLandmarkerService.swift`。
