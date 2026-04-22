import AVFoundation
import CoreImage
import Foundation
import QuartzCore
import SwiftUI
import UIKit

enum WebcamResolutionPreset: String, CaseIterable, Identifiable {
    case p720 = "720p"
    case p1080 = "1080p"

    var id: String { rawValue }

    var title: String {
        rawValue
    }

    var sessionPreset: AVCaptureSession.Preset {
        switch self {
        case .p720:
            return .hd1280x720
        case .p1080:
            return .hd1920x1080
        }
    }
}

enum WebcamFPSPreset: String, CaseIterable, Identifiable {
    case fps30 = "30"
    case fps60 = "60"

    var id: String { rawValue }

    var title: String {
        "\(rawValue) FPS"
    }

    var value: Int {
        Int(rawValue) ?? 30
    }
}

enum WebcamCameraPosition: String, CaseIterable, Identifiable {
    case front
    case back

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front:
            return "Front"
        case .back:
            return "Back"
        }
    }

    var capturePosition: AVCaptureDevice.Position {
        switch self {
        case .front:
            return .front
        case .back:
            return .back
        }
    }

    init(devicePosition: AVCaptureDevice.Position) {
        self = devicePosition == .back ? .back : .front
    }
}

final class WebcamStreamingManager: NSObject, ObservableObject, URLSessionWebSocketDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var status = "Webcam idle"
    @Published private(set) var isStreaming = false
    @Published private(set) var isConnected = false
    @Published private(set) var transmittedFPS: Double = 0
    @Published private(set) var activeCameraPosition: WebcamCameraPosition = .front

    let captureSession = AVCaptureSession()

    private static let frameMagic = Data("WCM1".utf8)

    private let ciContext = CIContext()
    private let captureQueue = DispatchQueue(label: "WebcamStreamingManager.capture", qos: .userInteractive)

    private var urlSession: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var authToken: String = ""
    private var videoOutput: AVCaptureVideoDataOutput?
    private var videoInput: AVCaptureDeviceInput?

    private var selectedFPS: WebcamFPSPreset = .fps30
    private var selectedResolution: WebcamResolutionPreset = .p1080
    private var selectedCameraPosition: WebcamCameraPosition = .front
    private var micEnabled = false

    private var isWebSocketAuthenticated = false
    private var isSendingFrame = false
    private var frameIntervalSeconds: Double = 1.0 / 30.0
    private var lastFrameSentAt: CFTimeInterval = 0
    private var fpsWindowStartAt: CFTimeInterval = CACurrentMediaTime()
    private var fpsWindowCount = 0

    deinit {
        stopStreaming()
    }

    func startStreaming(
        urlString: String,
        token: String,
        resolution: WebcamResolutionPreset,
        fps: WebcamFPSPreset,
        cameraPosition: WebcamCameraPosition,
        micEnabled: Bool
    ) {
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "ws" || scheme == "wss" else {
            updateStatus("Webcam URL invalid. Use ws:// or wss://")
            return
        }

        guard !trimmedToken.isEmpty else {
            updateStatus("Webcam token required")
            return
        }

        requestPermissions(includeMic: micEnabled) { [weak self] granted, reason in
            guard let self else {
                return
            }

            guard granted else {
                self.updateStatus(reason ?? "Camera permission denied")
                return
            }

            self.beginStreaming(
                url: url,
                token: trimmedToken,
                resolution: resolution,
                fps: fps,
                cameraPosition: cameraPosition,
                micEnabled: micEnabled
            )
        }
    }

    func switchCamera(to position: WebcamCameraPosition) {
        captureQueue.async { [weak self] in
            guard let self else {
                return
            }

            self.selectedCameraPosition = position

            guard self.videoInput != nil else {
                DispatchQueue.main.async {
                    self.activeCameraPosition = position
                }
                return
            }

            do {
                try self.reconfigureVideoInput(cameraPosition: position)
            } catch {
                self.updateStatus("Camera switch failed: \(error.localizedDescription)")
            }
        }
    }

    func stopStreaming() {
        isWebSocketAuthenticated = false
        isSendingFrame = false

        captureQueue.async { [weak self] in
            guard let self else {
                return
            }

            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }

            self.videoInput = nil
            self.videoOutput = nil
        }

        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        DispatchQueue.main.async {
            self.isConnected = false
            self.isStreaming = false
            self.transmittedFPS = 0
            if self.status == "Webcam idle" {
                return
            }
            self.status = "Webcam stopped"
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocolValue: String?) {
        updateStatus("Webcam connected, authenticating...")
        let authMessage = "AUTH:\(authToken)"
        webSocketTask.send(.string(authMessage)) { [weak self] error in
            guard let self else {
                return
            }

            if let error {
                self.updateStatus("Webcam auth send failed: \(error.localizedDescription)")
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        isWebSocketAuthenticated = false
        DispatchQueue.main.async {
            self.isConnected = false
            self.isStreaming = false
            self.status = "Webcam disconnected (\(closeCode.rawValue))"
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task == webSocketTask else {
            return
        }

        if let error {
            updateStatus("Webcam socket error: \(error.localizedDescription)")
        }

        isWebSocketAuthenticated = false
        DispatchQueue.main.async {
            self.isConnected = false
            self.isStreaming = false
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isWebSocketAuthenticated else {
            return
        }

        let now = CACurrentMediaTime()
        if now - lastFrameSentAt < frameIntervalSeconds {
            return
        }

        guard !isSendingFrame else {
            return
        }

        guard let frame = makeFramePacket(from: sampleBuffer) else {
            return
        }

        isSendingFrame = true
        lastFrameSentAt = now

        webSocketTask?.send(.data(frame)) { [weak self] error in
            guard let self else {
                return
            }

            self.captureQueue.async {
                self.isSendingFrame = false
            }

            if let error {
                self.updateStatus("Webcam frame send failed: \(error.localizedDescription)")
                return
            }

            self.captureQueue.async {
                self.fpsWindowCount += 1
                let elapsed = CACurrentMediaTime() - self.fpsWindowStartAt
                if elapsed >= 1.0 {
                    let fpsValue = Double(self.fpsWindowCount) / elapsed
                    self.fpsWindowStartAt = CACurrentMediaTime()
                    self.fpsWindowCount = 0
                    DispatchQueue.main.async {
                        self.transmittedFPS = fpsValue
                    }
                }
            }
        }
    }

    private func beginStreaming(
        url: URL,
        token: String,
        resolution: WebcamResolutionPreset,
        fps: WebcamFPSPreset,
        cameraPosition: WebcamCameraPosition,
        micEnabled: Bool
    ) {
        stopStreaming()

        authToken = token
        selectedResolution = resolution
        selectedFPS = fps
        selectedCameraPosition = cameraPosition
        DispatchQueue.main.async {
            self.activeCameraPosition = cameraPosition
        }
        self.micEnabled = micEnabled
        frameIntervalSeconds = 1.0 / Double(max(fps.value, 15))
        lastFrameSentAt = 0
        fpsWindowStartAt = CACurrentMediaTime()
        fpsWindowCount = 0

        var setupError: Error?
        captureQueue.sync {
            do {
                try self.configureCaptureSession(
                    resolution: resolution,
                    fps: fps,
                    cameraPosition: cameraPosition,
                    includeMic: micEnabled
                )
            } catch {
                setupError = error
            }
        }

        if let setupError {
            updateStatus("Webcam setup failed: \(setupError.localizedDescription)")
            return
        }

        updateStatus("Connecting webcam stream...")

        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false

        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        webSocketTask = urlSession?.webSocketTask(with: url)
        webSocketTask?.resume()

        listenForMessages()
    }

    private func listenForMessages() {
        guard let webSocketTask else {
            return
        }

        webSocketTask.receive { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.listenForMessages()
            case .failure(let error):
                self.updateStatus("Webcam receive error: \(error.localizedDescription)")
                self.isWebSocketAuthenticated = false
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.isStreaming = false
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            if text == "AUTH_OK" {
                isWebSocketAuthenticated = true
                startCaptureIfNeeded()
                DispatchQueue.main.async {
                    self.isConnected = true
                    self.isStreaming = true
                    self.status = "Webcam streaming to Windows"
                }
            } else if text == "AUTH_FAIL" {
                updateStatus("Webcam authentication failed")
                stopStreaming()
            }
        case .data:
            break
        @unknown default:
            break
        }
    }

    private func requestPermissions(includeMic: Bool, completion: @escaping (Bool, String?) -> Void) {
        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)

        func requestMicIfNeeded() {
            guard includeMic else {
                completion(true, nil)
                return
            }

            let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            switch audioStatus {
            case .authorized:
                completion(true, nil)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    completion(granted, granted ? nil : "Microphone permission denied")
                }
            default:
                completion(false, "Microphone permission denied")
            }
        }

        switch videoStatus {
        case .authorized:
            requestMicIfNeeded()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if !granted {
                    completion(false, "Camera permission denied")
                    return
                }

                requestMicIfNeeded()
            }
        default:
            completion(false, "Camera permission denied")
        }
    }

    private func configureCaptureSession(
        resolution: WebcamResolutionPreset,
        fps: WebcamFPSPreset,
        cameraPosition: WebcamCameraPosition,
        includeMic: Bool
    ) throws {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }

        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }

        guard let videoDevice = resolveVideoDevice(preferred: cameraPosition) else {
            captureSession.commitConfiguration()
            throw WebcamError.cameraUnavailable
        }

        let videoInput = try AVCaptureDeviceInput(device: videoDevice)
        guard captureSession.canAddInput(videoInput) else {
            captureSession.commitConfiguration()
            throw WebcamError.cannotAddVideoInput
        }
        captureSession.addInput(videoInput)
        self.videoInput = videoInput
        let actualCameraPosition = WebcamCameraPosition(devicePosition: videoDevice.position)
        selectedCameraPosition = actualCameraPosition
        DispatchQueue.main.async {
            self.activeCameraPosition = actualCameraPosition
        }

        if includeMic,
           let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)

        guard captureSession.canAddOutput(output) else {
            captureSession.commitConfiguration()
            throw WebcamError.cannotAddVideoOutput
        }

        captureSession.addOutput(output)
        videoOutput = output

        applyCaptureResolutionPreset(resolution)
        applyVideoConnectionSettings(output: output, cameraPosition: actualCameraPosition)

        try configureFrameRate(device: videoDevice, fps: fps)

        captureSession.commitConfiguration()
    }

    private func reconfigureVideoInput(cameraPosition: WebcamCameraPosition) throws {
        guard let videoDevice = resolveVideoDevice(preferred: cameraPosition) else {
            throw WebcamError.cameraUnavailable
        }

        let newInput = try AVCaptureDeviceInput(device: videoDevice)
        let previousInput = videoInput

        captureSession.beginConfiguration()
        if let previousInput {
            captureSession.removeInput(previousInput)
        }

        guard captureSession.canAddInput(newInput) else {
            if let previousInput, captureSession.canAddInput(previousInput) {
                captureSession.addInput(previousInput)
                videoInput = previousInput
            }
            captureSession.commitConfiguration()
            throw WebcamError.cannotAddVideoInput
        }

        captureSession.addInput(newInput)
        videoInput = newInput

        let actualCameraPosition = WebcamCameraPosition(devicePosition: videoDevice.position)
        selectedCameraPosition = actualCameraPosition

        if let output = videoOutput {
            applyVideoConnectionSettings(output: output, cameraPosition: actualCameraPosition)
        }

        applyCaptureResolutionPreset(selectedResolution)
        try configureFrameRate(device: videoDevice, fps: selectedFPS)
        captureSession.commitConfiguration()

        DispatchQueue.main.async {
            self.activeCameraPosition = actualCameraPosition
        }
    }

    private func resolveVideoDevice(preferred cameraPosition: WebcamCameraPosition) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition.capturePosition)
            ?? AVCaptureDevice.default(
                .builtInWideAngleCamera,
                for: .video,
                position: cameraPosition == .front ? .back : .front
            )
    }

    private func applyVideoConnectionSettings(output: AVCaptureVideoDataOutput, cameraPosition: WebcamCameraPosition) {
        guard let connection = output.connection(with: .video) else {
            return
        }

        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = cameraPosition == .front
        }

        if connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    private func applyCaptureResolutionPreset(_ resolution: WebcamResolutionPreset) {
        if captureSession.canSetSessionPreset(resolution.sessionPreset) {
            captureSession.sessionPreset = resolution.sessionPreset
            selectedResolution = resolution
            return
        }

        if captureSession.canSetSessionPreset(.hd1280x720) {
            captureSession.sessionPreset = .hd1280x720
            selectedResolution = .p720
            if resolution != .p720 {
                updateStatus("1080p not supported on this camera. Falling back to 720p.")
            }
            return
        }

        if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        }
    }

    private func configureFrameRate(device: AVCaptureDevice, fps: WebcamFPSPreset) throws {
        let target = Double(fps.value)
        let duration = CMTime(value: 1, timescale: CMTimeScale(max(fps.value, 15)))

        try device.lockForConfiguration()
        defer {
            device.unlockForConfiguration()
        }

        let supportsTarget = device.activeFormat.videoSupportedFrameRateRanges.contains {
            $0.maxFrameRate >= target && $0.minFrameRate <= target
        }

        if supportsTarget {
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        }
    }

    private func startCaptureIfNeeded() {
        captureQueue.async { [weak self] in
            guard let self else {
                return
            }

            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }

    private func makeFramePacket(from sampleBuffer: CMSampleBuffer) -> Data? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let rect = CGRect(x: 0, y: 0, width: width, height: height)

        guard let cgImage = ciContext.createCGImage(ciImage, from: rect) else {
            return nil
        }

        let jpegQuality: CGFloat = selectedResolution == .p1080 ? 0.62 : 0.68
        guard let jpegData = UIImage(cgImage: cgImage).jpegData(compressionQuality: jpegQuality) else {
            return nil
        }

        var packet = Data()
        packet.append(Self.frameMagic)
        packet.appendLittleEndian(UInt16(clamping: width))
        packet.appendLittleEndian(UInt16(clamping: height))
        packet.append(UInt8(clamping: selectedFPS.value))
        packet.append(micEnabled ? 0x01 : 0x00)

        let timestampMs = UInt32((CACurrentMediaTime() * 1000).truncatingRemainder(dividingBy: Double(UInt32.max)))
        packet.appendLittleEndian(timestampMs)
        packet.append(jpegData)
        return packet
    }

    private func updateStatus(_ newStatus: String) {
        DispatchQueue.main.async {
            self.status = newStatus
        }
    }

    private enum WebcamError: LocalizedError {
        case cameraUnavailable
        case cannotAddVideoInput
        case cannotAddVideoOutput

        var errorDescription: String? {
            switch self {
            case .cameraUnavailable:
                return "No camera available"
            case .cannotAddVideoInput:
                return "Cannot configure camera input"
            case .cannotAddVideoOutput:
                return "Cannot configure camera output"
            }
        }
    }
}

struct WebcamPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.previewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
}

final class PreviewHostView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        guard let previewLayer = layer as? AVCaptureVideoPreviewLayer else {
            fatalError("Unexpected layer type")
        }
        return previewLayer
    }
}

private extension Data {
    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
            append(contentsOf: bytes)
        }
    }
}
