# 没有 Mac 时如何把工程变成可安装的 iPhone App

当前工程是 Xcode 源码，不能直接在 iPhone 上安装。可以用下面的方式在没有 Mac 的 Windows 电脑上完成安装。

## 路线：GitHub Actions 云构建 + Sideloadly 签名

### 1. 把工程推到 GitHub

新建一个 GitHub 仓库，把 `ShouQiao` 目录里的内容作为仓库根目录上传。确保 `.github/workflows/ios-build.yml` 也在仓库里。

### 2. 运行云构建

在 GitHub 仓库的 Actions 页面选择 `Build unsigned iOS IPA`，点击 `Run workflow`。macOS runner 会：

- 安装 XcodeGen 和 CocoaPods；
- 安装 MediaPipeTasksVision；
- 编译 `ShouQiao.app`；
- 打包成 `ShouQiao-unsigned.ipa`；
- 作为 artifact 上传。

### 3. 在 Windows 上安装到 iPhone

1. 下载 GitHub Actions 里的 `ShouQiao-unsigned-ipa` artifact；
2. 在 Windows 安装 [Sideloadly](https://sideloadly.io/) 和 Apple Devices/iTunes；
3. 用数据线连接 iPhone，信任电脑；
4. 把 `ShouQiao-unsigned.ipa` 拖进 Sideloadly；
5. 输入你的 Apple ID，点击 Start；
6. 在 iPhone 的“设置 → 通用 → VPN 与设备管理”里信任开发者证书。

免费 Apple ID 签名的 App 通常 7 天后过期，需要重新签名；正式长期使用建议 Apple Developer Program + TestFlight 或 App Store。

## 注意

- GitHub Actions 需要仓库有 Actions 权限；
- 如果 MediaPipe pod 版本导致编译失败，按 Xcode 日志调整 `Podfile` 版本和 `HandLandmarkerService.swift` 的委托方法签名；
- 没有 Apple 签名，任何 IPA 都不能安装到普通 iPhone 上；
- 这不是 App Store 上架流程，只是开发/自用安装流程。
