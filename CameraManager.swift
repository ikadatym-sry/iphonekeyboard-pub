import Foundation
import AVFoundation
import UIKit
import CoreImage

class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var isStreaming = false
    @Published var connectionStatus = "Disconnected"
    @Published var errorMessage: String? = nil
    
    let captureSession = AVCaptureSession()
    private var videoOutput = AVCaptureVideoDataOutput()
    private var webSocket: URLSessionWebSocketTask?
    
    private var currentURL: String = ""
    private var currentToken: String = ""
    
    private let frameQueue = DispatchQueue(label: "com.remotepad.videoQueue")
    
    private var startTime = Date()
    private var isConnected = false
    private let context = CIContext()
    
    override init() {
        super.init()
        setupCamera()
    }
    
    private func setupCamera() {
        captureSession.sessionPreset = .vga640x480 // 640x480 for decent bandwidth
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            errorMessage = "Failed to access camera."
            return
        }
        
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        
        videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            if let connection = videoOutput.connection(with: .video) {
                // Ensure orientation is correct
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
        }
    }
    
    func startStreaming(url: String, token: String) {
        guard !isStreaming else { return }
        errorMessage = nil
        
        // Request permissions
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.currentURL = url
                    self?.currentToken = token
                    self?.connectWebSocket()
                } else {
                    self?.errorMessage = "Camera permission denied. Please allow it in Settings."
                }
            }
        }
    }
    
    func stopStreaming() {
        isStreaming = false
        isConnected = false
        frameQueue.async {
            self.captureSession.stopRunning()
        }
        webSocket?.cancel(with: .normalClosure, reason: nil)
        webSocket = nil
        DispatchQueue.main.async {
            self.connectionStatus = "Disconnected"
        }
    }
    
    private func connectWebSocket() {
        guard let wsURL = URL(string: currentURL) else {
            self.errorMessage = "Invalid WebSocket URL"
            return
        }
        
        self.connectionStatus = "Connecting..."
        
        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: wsURL)
        webSocket?.resume()
        
        // Send Auth
        let authMessage = URLSessionWebSocketTask.Message.string("AUTH:\(currentToken)")
        webSocket?.send(authMessage) { [weak self] error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.connectionStatus = "Error: \(error.localizedDescription)"
                    self?.stopStreaming()
                }
            } else {
                self?.receiveAuthResponse()
            }
        }
    }
    
    private func receiveAuthResponse() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    if text == "AUTH_OK" {
                        DispatchQueue.main.async {
                            self?.connectionStatus = "Streaming"
                            self?.isConnected = true
                            self?.isStreaming = true
                        }
                        self?.frameQueue.async {
                            self?.captureSession.startRunning()
                            self?.startTime = Date()
                        }
                    } else {
                        DispatchQueue.main.async {
                            self?.connectionStatus = "Auth Failed: \(text)"
                            self?.stopStreaming()
                        }
                    }
                default:
                    self?.receiveAuthResponse() // Keep listening if unexpected format
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.connectionStatus = "Error: \(error.localizedDescription)"
                    self?.stopStreaming()
                }
            }
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isConnected, isStreaming else { return }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let uiImage = UIImage(cgImage: cgImage)
        
        // Compress to JPEG
        guard let jpegData = uiImage.jpegData(compressionQuality: 0.6) else { return }
        
        // Build packet: WCM1 (4) + width (2) + height (2) + fps (1) + mic (1) + timestamp_ms (4) + jpeg
        var packet = Data()
        packet.append(contentsOf: [0x57, 0x43, 0x4D, 0x31]) // "WCM1"
        
        let width = UInt16(cgImage.width).littleEndian
        let height = UInt16(cgImage.height).littleEndian
        
        withUnsafeBytes(of: width) { packet.append(contentsOf: $0) }
        withUnsafeBytes(of: height) { packet.append(contentsOf: $0) }
        
        packet.append(30) // FPS (placeholder, not strictly enforced receiver-side for parsing logic except metadata)
        packet.append(0)  // MIC off
        
        let elapsedMs = UInt32(Date().timeIntervalSince(startTime) * 1000).littleEndian
        withUnsafeBytes(of: elapsedMs) { packet.append(contentsOf: $0) }
        
        packet.append(jpegData)
        
        let message = URLSessionWebSocketTask.Message.data(packet)
        webSocket?.send(message) { [weak self] error in
            if let error = error {
                print("WebSocket send error: \(error)")
                // Connection might have dropped, but ignore small frame drops for now
                // Optional: handle reconnect or stop
            }
        }
    }
}
