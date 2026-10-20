import AVFoundation
import Combine
import CoreImage
import UIKit

final class CameraManager: NSObject, ObservableObject {
    let session = AVCaptureSession()

    @Published private(set) var isRunning = false
    @Published private(set) var permissionDenied = false

    var onImage: ((UIImage) -> Void)?

    private let sessionQueue = DispatchQueue(label: "org.signbridge.camera.session")
    private let videoQueue = DispatchQueue(label: "org.signbridge.camera.video")
    private let context = CIContext()
    private var configured = false
    private var lastFrameAt = CFAbsoluteTimeGetCurrent()

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startAuthorized()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.permissionDenied = !granted
                }
                if granted {
                    self?.startAuthorized()
                }
            }
        default:
            DispatchQueue.main.async { self.permissionDenied = true }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    private func startAuthorized() {
        sessionQueue.async {
            guard self.configureIfNeeded() else { return }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    private func configureIfNeeded() -> Bool {
        if configured { return true }

        session.beginConfiguration()
        session.sessionPreset = .high
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .front
        ) else {
            return false
        }

        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return false
        }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: videoQueue)

        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            connection.videoOrientation = .portrait
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = true
            }
        }

        configured = true
        return true
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrameAt >= 0.13 else { return }
        lastFrameAt = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = UIImage(cgImage: cgImage, scale: 1, orientation: .up)
        DispatchQueue.main.async {
            self.onImage?(image)
        }
    }
}
