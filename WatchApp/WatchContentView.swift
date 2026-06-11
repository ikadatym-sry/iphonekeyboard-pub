import SwiftUI
import CoreMotion
import Foundation

class WatchSensorManager: ObservableObject {
    private let altimeter = CMAltimeter()
    private let motionManager = CMMotionManager()

    @Published var altitude: Double = 0.0
    @Published var pressure: Double = 0.0
    @Published var estimatedAltitude: Double = 0.0
    @Published var isSupported: Bool = false
    @Published var accelerometerData: CMAcceleration = CMAcceleration(x: 0, y: 0, z: 0)
    
    var referenceSeaLevelPressure: Double = 1013.25

    init() {
        checkSupport()
    }

    private func checkSupport() {
        isSupported = CMAltimeter.isRelativeAltitudeAvailable()
    }

    func startUpdates() {
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
                guard let data = data, error == nil, let self = self else { return }
                self.altitude = data.relativeAltitude.doubleValue
                
                let currentPressure = data.pressure.doubleValue * 10.0 // Convert kPa to hPa (mbar)
                self.pressure = currentPressure
                
                // Calculate estimated absolute altitude
                self.estimatedAltitude = 44330.0 * (1.0 - pow(currentPressure / self.referenceSeaLevelPressure, 1.0 / 5.255))
            }
        }

        if motionManager.isAccelerometerAvailable {
            motionManager.accelerometerUpdateInterval = 1.0 / 10.0 // 10Hz
            motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
                guard let data = data, error == nil else { return }
                self?.accelerometerData = data.acceleration
            }
        }
    }

    func stopUpdates() {
        altimeter.stopRelativeAltitudeUpdates()
        motionManager.stopAccelerometerUpdates()
    }
}

struct WatchContentView: View {
    @StateObject private var sensorManager = WatchSensorManager()
    @AppStorage("seaLevelPressure") private var seaLevelPressure: Double = 1013.25

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if sensorManager.isSupported {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pressure: \(String(format: "%.2f", sensorManager.pressure)) hPa")
                            .font(.system(.body, design: .monospaced))
                        Text("Abs Alt: \(String(format: "%.2f", sensorManager.estimatedAltitude)) m")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.cyan)
                        Text("Rel Alt: \(String(format: "%.2f", sensorManager.altitude)) m")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.gray)
                            
                        Divider()
                        
                        Stepper(value: $seaLevelPressure, in: 900...1100, step: 1.0) {
                            VStack(alignment: .leading) {
                                Text("QNH (hPa)")
                                    .font(.caption)
                                Text("\(String(format: "%.0f", seaLevelPressure))")
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(8)
                } else {
                    Text("No Barometer")
                        .foregroundColor(.red)
                }

                VStack(alignment: .leading) {
                    Text("Accel X: \(String(format: "%.2f", sensorManager.accelerometerData.x))")
                        .font(.system(.caption, design: .monospaced))
                    Text("Accel Y: \(String(format: "%.2f", sensorManager.accelerometerData.y))")
                        .font(.system(.caption, design: .monospaced))
                    Text("Accel Z: \(String(format: "%.2f", sensorManager.accelerometerData.z))")
                        .font(.system(.caption, design: .monospaced))
                }
                .padding()
                .background(Color.green.opacity(0.2))
                .cornerRadius(8)
            }
            .padding(.horizontal)
        }
        .navigationTitle("Sensors")
        .onAppear {
            sensorManager.referenceSeaLevelPressure = seaLevelPressure
            sensorManager.startUpdates()
        }
        .onDisappear {
            sensorManager.stopUpdates()
        }
        .onChange(of: seaLevelPressure) { newValue in
            sensorManager.referenceSeaLevelPressure = newValue
        }
    }
}
