import SwiftUI
import CoreMotion

class WatchSensorManager: ObservableObject {
    private let altimeter = CMAltimeter()
    private let motionManager = CMMotionManager()

    @Published var altitude: Double = 0.0
    @Published var pressure: Double = 0.0
    @Published var isSupported: Bool = false
    @Published var accelerometerData: CMAcceleration = CMAcceleration(x: 0, y: 0, z: 0)

    init() {
        checkSupport()
    }

    private func checkSupport() {
        isSupported = CMAltimeter.isRelativeAltitudeAvailable()
    }

    func startUpdates() {
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
                guard let data = data, error == nil else { return }
                self?.altitude = data.relativeAltitude.doubleValue
                self?.pressure = data.pressure.doubleValue * 10 // Convert kPa to hPa (mbar)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if sensorManager.isSupported {
                    VStack(alignment: .leading) {
                        Text("Altitude: \(String(format: "%.2f", sensorManager.altitude)) m")
                        Text("Pressure: \(String(format: "%.2f", sensorManager.pressure)) hPa")
                    }
                    .padding()
                    .background(Color.blue.opacity(0.3))
                    .cornerRadius(8)
                } else {
                    Text("No Barometer")
                        .foregroundColor(.red)
                }

                VStack(alignment: .leading) {
                    Text("Accel X: \(String(format: "%.2f", sensorManager.accelerometerData.x))")
                    Text("Accel Y: \(String(format: "%.2f", sensorManager.accelerometerData.y))")
                    Text("Accel Z: \(String(format: "%.2f", sensorManager.accelerometerData.z))")
                }
                .padding()
                .background(Color.green.opacity(0.3))
                .cornerRadius(8)
            }
        }
        .navigationTitle("Sensors")
        .onAppear {
            sensorManager.startUpdates()
        }
        .onDisappear {
            sensorManager.stopUpdates()
        }
    }
}
