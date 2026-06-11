import SwiftUI
import CoreMotion

class SensorManager: ObservableObject {
    private let altimeter = CMAltimeter()
    private let motionManager = CMMotionManager()

    @Published var altitude: Double = 0.0
    @Published var pressure: Double = 0.0
    @Published var isSupported: Bool = false
    @Published var accelerometerData: CMAcceleration = CMAcceleration(x: 0, y: 0, z: 0)
    @Published var gyroData: CMRotationRate = CMRotationRate(x: 0, y: 0, z: 0)

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

        if motionManager.isGyroAvailable {
            motionManager.gyroUpdateInterval = 1.0 / 10.0 // 10Hz
            motionManager.startGyroUpdates(to: .main) { [weak self] data, error in
                guard let data = data, error == nil else { return }
                self?.gyroData = data.rotationRate
            }
        }
    }

    func stopUpdates() {
        altimeter.stopRelativeAltitudeUpdates()
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
    }
}

struct SensorTestView: View {
    @StateObject private var sensorManager = SensorManager()

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Barometer / Altimeter")) {
                    if sensorManager.isSupported {
                        HStack {
                            Text("Relative Altitude")
                            Spacer()
                            Text(String(format: "%.2f m", sensorManager.altitude))
                        }
                        HStack {
                            Text("Pressure")
                            Spacer()
                            Text(String(format: "%.2f hPa", sensorManager.pressure))
                        }
                    } else {
                        Text("Barometer not supported on this device.")
                            .foregroundColor(.red)
                    }
                }

                Section(header: Text("Accelerometer (G)")) {
                    HStack {
                        Text("X")
                        Spacer()
                        Text(String(format: "%.3f", sensorManager.accelerometerData.x))
                    }
                    HStack {
                        Text("Y")
                        Spacer()
                        Text(String(format: "%.3f", sensorManager.accelerometerData.y))
                    }
                    HStack {
                        Text("Z")
                        Spacer()
                        Text(String(format: "%.3f", sensorManager.accelerometerData.z))
                    }
                }

                Section(header: Text("Gyroscope (rad/s)")) {
                    HStack {
                        Text("X")
                        Spacer()
                        Text(String(format: "%.3f", sensorManager.gyroData.x))
                    }
                    HStack {
                        Text("Y")
                        Spacer()
                        Text(String(format: "%.3f", sensorManager.gyroData.y))
                    }
                    HStack {
                        Text("Z")
                        Spacer()
                        Text(String(format: "%.3f", sensorManager.gyroData.z))
                    }
                }
            }
            .navigationTitle("Sensor Data")
            .onAppear {
                sensorManager.startUpdates()
            }
            .onDisappear {
                sensorManager.stopUpdates()
            }
        }
    }
}
