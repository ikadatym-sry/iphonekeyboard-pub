import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.session = session
            DispatchQueue.main.async {
                layer.frame = uiView.bounds
            }
        }
    }
}

struct WebcamView: View {
    @StateObject private var cameraManager = CameraManager()
    @AppStorage("webcam.savedURL") private var savedURL = "ws://192.168.1.100:8767"
    @AppStorage("webcam.savedToken") private var savedToken = "remotepad-token"
    
    var body: some View {
        VStack {
            if cameraManager.isStreaming {
                CameraPreviewView(session: cameraManager.captureSession)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .padding()
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 48))
                            Text("Camera Offline")
                                .font(.headline)
                            Text("Ready to stream to Windows")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    )
                    .padding()
            }
            
            VStack(spacing: 16) {
                Text(cameraManager.connectionStatus)
                    .font(.headline)
                    .foregroundColor(cameraManager.isStreaming ? .green : .primary)
                
                if let err = cameraManager.errorMessage {
                    Text(err)
                        .foregroundColor(.red)
                        .font(.caption)
                        .multilineTextAlignment(.center)
                }
                
                TextField("ws://<windows-ip>:8767", text: $savedURL)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                
                TextField("Token", text: $savedToken)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                
                if cameraManager.isStreaming {
                    Button("Stop Streaming") {
                        cameraManager.stopStreaming()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .frame(maxWidth: .infinity)
                } else {
                    Button("Start Streaming") {
                        cameraManager.startStreaming(url: savedURL, token: savedToken)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .cornerRadius(16)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .onDisappear {
            cameraManager.stopStreaming()
        }
    }
}
